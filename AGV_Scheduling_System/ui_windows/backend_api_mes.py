import json
from datetime import datetime

from flask import jsonify, request

from db_manager import DatabaseManager

try:
    from ui_windows import backend_api as base_backend
except ImportError:
    import backend_api as base_backend

app = base_backend.app
sim_state = base_backend.sim_state
_ORIGINAL_RUN_SIMULATION_TASK = base_backend.run_simulation_task
MES_SIMULATION_MODE = True

def safe_json_dumps(payload):
    try:
        return json.dumps(payload, ensure_ascii=False)
    except Exception:
        return json.dumps({"raw": str(payload)}, ensure_ascii=False)

def ensure_mes_sync_tables(db=None):
    local_db = db or DatabaseManager()
    statements = [
        """
        CREATE TABLE IF NOT EXISTS mes_inbox (
            id INT PRIMARY KEY AUTO_INCREMENT,
            request_id VARCHAR(64) NOT NULL UNIQUE,
            external_order_id VARCHAR(64) NOT NULL,
            msg_type VARCHAR(32) DEFAULT 'ORDER_INBOUND',
            source_system VARCHAR(64) DEFAULT 'MES',
            payload_json LONGTEXT,
            receive_status VARCHAR(32) DEFAULT 'RECEIVED',
            internal_order_id INT NULL,
            error_msg VARCHAR(255) NULL,
            received_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            processed_at DATETIME NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS mes_outbox (
            id INT PRIMARY KEY AUTO_INCREMENT,
            biz_type VARCHAR(32) NOT NULL,
            biz_id VARCHAR(64) NOT NULL,
            external_order_id VARCHAR(64) NULL,
            target_system VARCHAR(64) DEFAULT 'MES',
            payload_json LONGTEXT,
            send_status VARCHAR(32) DEFAULT 'PENDING',
            retry_count INT DEFAULT 0,
            last_error VARCHAR(255) NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            sent_at DATETIME NULL,
            acked_at DATETIME NULL,
            UNIQUE KEY uq_mes_outbox_biz (biz_type, biz_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS mes_order_links (
            id INT PRIMARY KEY AUTO_INCREMENT,
            request_id VARCHAR(64) NOT NULL UNIQUE,
            external_order_id VARCHAR(64) NOT NULL UNIQUE,
            internal_order_id INT NOT NULL UNIQUE,
            source_system VARCHAR(64) DEFAULT 'MES',
            sync_status VARCHAR(32) DEFAULT 'RECEIVED',
            last_push_time DATETIME NULL,
            last_ack_time DATETIME NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    ]

    for statement in statements:
        local_db.execute_update(statement)

def write_comm_log(node_path, msg_type, content, protocol='HTTP/JSON'):
    db = DatabaseManager()
    try:
        sql = "INSERT INTO SYS_COMM_LOGS (node_path, msg_type, content, protocol) VALUES (%s, %s, %s, %s)"
        db.execute_update(sql, (node_path, msg_type, content, protocol))
    except Exception as exc:
        print(f"MES communication log write failed: {exc}")

def update_mes_link_status(db, internal_order_id=None, external_order_id=None, sync_status=None, push=False, ack=False):
    if not sync_status and not push and not ack:
        return

    filters = []
    filter_params = []
    if internal_order_id is not None:
        filters.append("internal_order_id = %s")
        filter_params.append(internal_order_id)
    if external_order_id is not None:
        filters.append("external_order_id = %s")
        filter_params.append(external_order_id)
    if not filters:
        return

    set_parts = []
    params = []
    if sync_status:
        set_parts.append("sync_status = %s")
        params.append(sync_status)
    if push:
        set_parts.append("last_push_time = NOW()")
    if ack:
        set_parts.append("last_ack_time = NOW()")
    params.extend(filter_params)

    sql = f"UPDATE mes_order_links SET {', '.join(set_parts)} WHERE {' OR '.join(filters)}"
    db.execute_update(sql, tuple(params))

def enqueue_mes_outbox(db, biz_type, biz_id, external_order_id, payload, target_system='MES'):
    ensure_mes_sync_tables(db)
    exists = db.execute_query(
        "SELECT id FROM mes_outbox WHERE biz_type = %s AND biz_id = %s LIMIT 1",
        (biz_type, str(biz_id))
    )
    if exists:
        return exists[0]["id"], False

    sql = """
        INSERT INTO mes_outbox (biz_type, biz_id, external_order_id, target_system, payload_json, send_status)
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    db.execute_update(sql, (biz_type, str(biz_id), external_order_id, target_system, safe_json_dumps(payload), 'PENDING'))
    created = db.execute_query(
        "SELECT id FROM mes_outbox WHERE biz_type = %s AND biz_id = %s LIMIT 1",
        (biz_type, str(biz_id))
    )
    return (created[0]["id"] if created else None), True

def process_mes_outbox_record(record_id, db=None):
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)
    rows = local_db.execute_query("SELECT * FROM mes_outbox WHERE id = %s LIMIT 1", (record_id,))
    if not rows:
        return {"status": "error", "msg": "未找到对应的出站消息"}

    record = rows[0]
    if not record.get("payload_json"):
        local_db.execute_update(
            "UPDATE mes_outbox SET send_status = %s, retry_count = retry_count + 1, last_error = %s WHERE id = %s",
            ('FAILED', 'empty payload', record_id)
        )
        return {"status": "error", "msg": "消息体为空，无法发送"}

    local_db.execute_update(
        "UPDATE mes_outbox SET send_status = %s, sent_at = NOW(), last_error = NULL WHERE id = %s",
        ('SENT', record_id)
    )

    if MES_SIMULATION_MODE:
        local_db.execute_update(
            "UPDATE mes_outbox SET send_status = %s, acked_at = NOW(), last_error = NULL WHERE id = %s",
            ('ACKED', record_id)
        )
        update_mes_link_status(
            local_db,
            external_order_id=record.get("external_order_id"),
            sync_status='ACKED',
            push=True,
            ack=True
        )
        write_comm_log(
            "AGV调度系统 -> MES",
            "MES回传",
            safe_json_dumps({
                "mode": "simulation",
                "biz_type": record.get("biz_type"),
                "biz_id": record.get("biz_id"),
                "external_order_id": record.get("external_order_id")
            })
        )
        return {"status": "success", "msg": "仿真模式已确认回传", "record_id": record_id}

    return {"status": "success", "msg": "消息已发送，等待外部 MES 确认", "record_id": record_id}

def process_pending_mes_outbox(limit=20, db=None):
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)
    pending = local_db.execute_query(
        "SELECT id FROM mes_outbox WHERE send_status IN ('PENDING', 'FAILED') ORDER BY created_at ASC LIMIT %s",
        (int(limit),)
    )
    return [process_mes_outbox_record(row["id"], local_db) for row in pending if row.get("id") is not None]

def create_completion_reports_for_finished_orders(db=None):
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)
    rows = local_db.execute_query(
        """
        SELECT o.order_id, o.target_station, o.weight, o.deadline, l.external_order_id
        FROM mes_orders o
        LEFT JOIN mes_order_links l ON l.internal_order_id = o.order_id
        WHERE o.status = 2
        ORDER BY o.order_id DESC
        LIMIT 200
        """
    )

    created_ids = []
    for order in rows:
        order_id = order.get("order_id")
        external_order_id = order.get("external_order_id") or f"LOCAL-{order_id}"
        payload = {
            "request_id": f"RPT-{order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "external_order_id": external_order_id,
            "internal_order_id": order_id,
            "status": "COMPLETED",
            "target_station": order.get("target_station"),
            "weight": order.get("weight"),
            "deadline": order.get("deadline"),
            "report_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        outbox_id, created = enqueue_mes_outbox(
            local_db,
            "TASK_COMPLETED",
            order_id,
            external_order_id,
            payload,
            target_system='MES'
        )
        if created and outbox_id:
            created_ids.append(outbox_id)
            update_mes_link_status(local_db, internal_order_id=order_id, sync_status='COMPLETED', push=True)
    return created_ids

def run_simulation_task_with_mes():
    ensure_mes_sync_tables()
    _ORIGINAL_RUN_SIMULATION_TASK()

    if sim_state.get("status") != "finished":
        return

    db = DatabaseManager()
    created_ids = create_completion_reports_for_finished_orders(db)
    if created_ids:
        results = process_pending_mes_outbox(limit=len(created_ids), db=db)
        sim_state["logs"].append(f"MES 同步扩展：已生成 {len(created_ids)} 条完成回传消息。")
        sim_state["logs"].append(f"MES 同步扩展：已处理 {len(results)} 条待发送消息。")

base_backend.run_simulation_task = run_simulation_task_with_mes
ensure_mes_sync_tables()

@app.route('/api/mes/orders/inbound', methods=['POST'])
def api_mes_orders_inbound():
    data = request.get_json(silent=True) or {}
    db = DatabaseManager()
    ensure_mes_sync_tables(db)

    request_id = str(data.get('request_id', '')).strip()
    external_order_id = str(data.get('external_order_id', '')).strip()
    target_station = data.get('target_station', data.get('station'))
    item_type = data.get('item_type', 1)
    weight = data.get('weight')
    deadline = data.get('deadline')
    source_system = str(data.get('source_system', 'MES')).strip() or 'MES'

    if not request_id or not external_order_id or target_station is None or weight is None or deadline is None:
        return jsonify({"status": "error", "msg": "缺少必要字段: request_id / external_order_id / target_station / weight / deadline"}), 400

    existed = db.execute_query("SELECT * FROM mes_inbox WHERE request_id = %s LIMIT 1", (request_id,))
    if existed:
        return jsonify({
            "status": "success",
            "msg": "请求已处理，已按幂等规则返回历史结果",
            "idempotent": True,
            "data": existed[0]
        })

    same_external = db.execute_query(
        "SELECT * FROM mes_order_links WHERE external_order_id = %s LIMIT 1",
        (external_order_id,)
    )
    if same_external:
        db.execute_update(
            """
            INSERT INTO mes_inbox (request_id, external_order_id, msg_type, source_system, payload_json, receive_status, internal_order_id, processed_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
            """,
            (request_id, external_order_id, 'ORDER_INBOUND', source_system, safe_json_dumps(data), 'DUPLICATE', same_external[0]['internal_order_id'])
        )
        return jsonify({
            "status": "success",
            "msg": "外部订单已存在，已忽略重复建单",
            "idempotent": True,
            "data": same_external[0]
        })

    db.execute_update(
        """
        INSERT INTO mes_inbox (request_id, external_order_id, msg_type, source_system, payload_json, receive_status)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (request_id, external_order_id, 'ORDER_INBOUND', source_system, safe_json_dumps(data), 'RECEIVED')
    )

    try:
        insert_sql = "INSERT INTO mes_orders (target_station, item_type, weight, deadline, status) VALUES (%s, %s, %s, %s, 0)"
        db.execute_update(insert_sql, (target_station, item_type, weight, deadline))
        rows = db.execute_query(
            """
            SELECT order_id FROM mes_orders
            WHERE target_station = %s AND item_type = %s AND weight = %s AND deadline = %s AND status = 0
            ORDER BY order_id DESC LIMIT 1
            """,
            (target_station, item_type, weight, deadline)
        )
        if not rows:
            raise RuntimeError("订单已写入，但未能定位内部订单号")

        internal_order_id = rows[0]["order_id"]
        db.execute_update(
            """
            INSERT INTO mes_order_links (request_id, external_order_id, internal_order_id, source_system, sync_status)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (request_id, external_order_id, internal_order_id, source_system, 'RECEIVED')
        )
        db.execute_update(
            "UPDATE mes_inbox SET receive_status = %s, internal_order_id = %s, processed_at = NOW() WHERE request_id = %s",
            ('PROCESSED', internal_order_id, request_id)
        )

        accept_payload = {
            "request_id": f"ACK-{request_id}",
            "external_order_id": external_order_id,
            "internal_order_id": internal_order_id,
            "status": "ACCEPTED",
            "accepted_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        enqueue_mes_outbox(db, 'ORDER_ACCEPTED', internal_order_id, external_order_id, accept_payload, target_system=source_system)
        process_pending_mes_outbox(limit=5, db=db)
        write_comm_log('MES -> AGV调度系统', 'MES订单入站', safe_json_dumps(accept_payload))

        return jsonify({
            "status": "success",
            "msg": "MES 订单已入站并进入待调度队列",
            "data": {
                "internal_order_id": internal_order_id,
                "external_order_id": external_order_id,
                "request_id": request_id
            }
        })
    except Exception as exc:
        db.execute_update(
            "UPDATE mes_inbox SET receive_status = %s, error_msg = %s, processed_at = NOW() WHERE request_id = %s",
            ('FAILED', str(exc)[:255], request_id)
        )
        return jsonify({"status": "error", "msg": f"MES 订单入站失败: {exc}"}), 500

@app.route('/api/mes/inbox/list', methods=['GET'])
def api_mes_inbox_list():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    limit = request.args.get('limit', default=100, type=int)
    rows = db.execute_query(
        "SELECT * FROM mes_inbox ORDER BY received_at DESC LIMIT %s",
        (max(1, min(limit, 500)),)
    )
    return jsonify({"status": "success", "data": rows if rows else []})

@app.route('/api/mes/outbox/list', methods=['GET'])
def api_mes_outbox_list():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    limit = request.args.get('limit', default=100, type=int)
    rows = db.execute_query(
        "SELECT * FROM mes_outbox ORDER BY created_at DESC LIMIT %s",
        (max(1, min(limit, 500)),)
    )
    return jsonify({"status": "success", "data": rows if rows else []})

@app.route('/api/mes/outbox/process', methods=['POST'])
def api_mes_outbox_process():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    payload = request.get_json(silent=True) or {}
    limit = int(payload.get('limit', 20))
    results = process_pending_mes_outbox(limit=limit, db=db)
    return jsonify({
        "status": "success",
        "msg": f"已处理 {len(results)} 条待发送消息",
        "data": results
    })

@app.route('/api/mes/outbox/retry/<int:record_id>', methods=['POST'])
def api_mes_outbox_retry(record_id):
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    db.execute_update(
        "UPDATE mes_outbox SET send_status = %s, retry_count = retry_count + 1, last_error = NULL WHERE id = %s",
        ('PENDING', record_id)
    )
    result = process_mes_outbox_record(record_id, db)
    status_code = 200 if result.get("status") == "success" else 400
    return jsonify(result), status_code

if __name__ == '__main__':
    print('MES 增强后端已启动，运行在 http://127.0.0.1:5000')
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
