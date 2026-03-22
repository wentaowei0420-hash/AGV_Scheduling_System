from flask import Flask, jsonify, request, send_file
import threading
import io
import os
import json
from datetime import datetime

import matlab.engine

from db_manager import DatabaseManager


app = Flask(__name__)

sim_state = {"status": "idle", "logs": [], "progress": 0}
MES_SIMULATION_MODE = True

# 基础工具函数
def safe_json_dumps(payload):
    """
    安全地将给定的数据（payload）转换为 JSON 字符串。
    如果转换过程中发生异常，则返回一个包含原始数据字符串表示形式的 JSON 对象，
    确保在任何情况下都能返回一个字符串，避免程序崩溃。
    """
    try:
        # 尝试使用 json.dumps 将 payload 序列化为 JSON 字符串。
        # ensure_ascii=False 允许输出中包含非 ASCII 字符（如中文），
        # 使生成的 JSON 字符串更可读。
        return json.dumps(payload, ensure_ascii=False)
    except Exception:
        # 如果序列化过程中出现任何异常（例如 payload 包含不可序列化的类型），
        # 则捕获异常，并将原始 payload 转换为字符串，包装成一个字典，
        # 再对这个字典进行 JSON 序列化。这样可以保证函数始终返回一个字符串，
        # 且保留了原始数据的字符串形式，便于调试。
        return json.dumps({"raw": str(payload)}, ensure_ascii=False)

def write_system_log(log_type, content):
    """
    将系统日志写入数据库的 system_logs 表中。
    该函数通过 DatabaseManager 执行插入操作，不返回任何值。
    """
    # 创建 DatabaseManager 的实例（可能是一个单例或每次新建），
    # 并调用其 execute_update 方法执行数据库更新操作（INSERT）。
    DatabaseManager().execute_update(
        # 要执行的 SQL 语句：向 system_logs 表的 log_type 和 content 字段插入值。
        # 使用 %s 作为占位符，这是 MySQL 的格式化方式，参数以元组形式传递。
        "INSERT INTO system_logs (log_type, content) VALUES (%s, %s)",
        # 提供实际参数：log_type 和 content，作为元组传入，替换 SQL 中的占位符。
        (log_type, content),
    )
    # 注意：该方法没有异常处理，若数据库操作失败会抛出异常。
    # 也没有返回值，调用者无法得知插入是否成功。

def write_comm_log(node_path, msg_type, content, protocol="HTTP/JSON"):
    DatabaseManager().execute_update(
        "INSERT INTO SYS_COMM_LOGS (node_path, msg_type, content, protocol) VALUES (%s, %s, %s, %s)",
        (node_path, msg_type, content, protocol),
    )

def localize_comm_labels(node_path, msg_type, content):
    """
    将通信日志中的节点路径和消息类型进行本地化（中文化）处理。
    根据内容自动识别特定事件（如冲突事件、调度结果），并设置对应的中文标签。
    同时使用别名映射表将常见的英文标签转换为中文。
    返回处理后的 (node_path, msg_type) 元组。
    """
    # 将输入参数转换为字符串，如果为 None 或空则转为空字符串，确保后续操作安全
    node_path = str(node_path or "")
    msg_type = str(msg_type or "")
    content = str(content or "")

    # 根据内容中的关键词自动识别事件类型，并覆盖 node_path 和 msg_type
    # 检测冲突事件（content 中包含 "conflict_event" 字段）
    if '"type": "conflict_event"' in content or '"type":"conflict_event"' in content:
        node_path = "MATLAB -> 后端"          # 设置发送方为 MATLAB
        msg_type = "冲突事件"                  # 设置消息类型为冲突事件
    # 检测调度结果事件（content 中包含 "schedule_result" 字段）
    elif '"type": "schedule_result"' in content or '"type":"schedule_result"' in content:
        node_path = "调度系统 -> 后端"          # 设置发送方为调度系统
        msg_type = "调度结果"                  # 设置消息类型为调度结果
    # 检测派工指令（content 中包含 "cmd": "assign"）
    elif '"cmd": "assign"' in content or '"cmd":"assign"' in content:
        msg_type = "派工指令"                  # 设置消息类型为派工指令
        try:
            # 尝试解析 JSON 内容，从中提取 AGV 名称
            payload = json.loads(content)
            agv_name = payload.get("agv") or "AGV"   # 如果字段缺失或为空，默认用 "AGV"
            node_path = f"上位机 -> {agv_name}"       # 设置发送方为上位机到指定 AGV
        except Exception:
            # 如果 JSON 解析失败，使用默认名称
            node_path = "上位机 -> AGV"

    # 定义节点路径的别名映射表（英文 -> 中文）
    node_alias = {
        "MATLAB -> Backend": "MATLAB -> 后端",
        "Scheduler -> Backend": "调度系统 -> 后端",
        "Upper -> AGV": "上位机 -> AGV",
        "AGV Dispatch System -> MES": "AGV调度系统 -> MES",
    }
    # 定义消息类型的别名映射表（英文 -> 中文）
    type_alias = {
        "Conflict Event": "冲突事件",
        "Schedule Result": "调度结果",
        "Dispatch Command": "派工指令",
        "MES Callback": "MES回传",
    }

    # 特殊处理：对于以 "Upper -> " 开头的节点路径，替换为中文前缀 "上位机 -> "
    for prefix in ("Upper -> ",):
        if node_path.startswith(prefix):
            node_path = "上位机 -> " + node_path[len(prefix):]

    # 应用别名映射：如果 node_path 在映射表中存在，则替换为对应的中文；否则保留原值
    node_path = node_alias.get(node_path, node_path)
    # 应用别名映射：如果 msg_type 在映射表中存在，则替换为对应的中文；否则保留原值
    msg_type = type_alias.get(msg_type, msg_type)

    # 返回处理后的 node_path 和 msg_type
    return node_path, msg_type

def repair_comm_log_labels(db=None):
    local_db = db or DatabaseManager()
    try:
        rows = local_db.execute_query(
            "SELECT log_id, node_path, msg_type, content FROM SYS_COMM_LOGS ORDER BY log_id DESC LIMIT 500"
        )
        for row in rows or []:
            node_path = str(row.get('node_path') or '')
            msg_type = str(row.get('msg_type') or '')
            content = str(row.get('content') or '')
            log_id = row.get('log_id')
            if not log_id:
                continue

            patched_node, patched_type = localize_comm_labels(node_path, msg_type, content)

            if patched_node != node_path or patched_type != msg_type:
                local_db.execute_update(
                    "UPDATE SYS_COMM_LOGS SET node_path = %s, msg_type = %s WHERE log_id = %s",
                    (patched_node, patched_type, log_id),
                )
    except Exception as exc:
        print(f"repair_comm_log_labels failed: {exc}")

# 表结构保障函数
def ensure_runtime_log_tables(db=None):
    local_db = db or DatabaseManager()
    statements = [
        '''
        CREATE TABLE IF NOT EXISTS sys_conflict_logs (
            id INT PRIMARY KEY AUTO_INCREMENT,
            sim_step INT NULL,
            agv1_id INT NULL,
            agv1_pos VARCHAR(64) NULL,
            agv2_id INT NULL,
            agv2_pos VARCHAR(64) NULL,
            conflict_type VARCHAR(128) NULL,
            report_time DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ''',
    ]
    for statement in statements:
        local_db.execute_update(statement)

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
        """,
    ]
    for statement in statements:
        local_db.execute_update(statement)

# MES 同步辅助函数
def update_mes_link_status(db, internal_order_id=None, external_order_id=None, sync_status=None, push=False, ack=False):
    """
    更新 mes_order_links 表中记录的同步状态和时间戳。
    该表用于维护内部订单与外部订单（MES侧）的关联关系。
    参数：
        db: 数据库管理器实例
        internal_order_id: 内部订单ID（可选，用于筛选更新条件）
        external_order_id: 外部订单ID（可选，用于筛选更新条件）
        sync_status: 要设置的新同步状态（字符串，如 'RECEIVED', 'PUSHED', 'ACKED', 'COMPLETED'）
        push: 如果为True，则将 last_push_time 更新为当前时间
        ack: 如果为True，则将 last_ack_time 更新为当前时间

    说明：
        必须至少提供一个筛选条件（internal_order_id 或 external_order_id），
        且至少有一个更新内容（sync_status、push、ack 之一为真），否则函数直接返回。
        使用 OR 组合筛选条件（即满足任一条件的记录都会被更新）。
    """
    # 如果没有提供任何更新内容，则直接返回
    if not sync_status and not push and not ack:
        return

    # 构建筛选条件列表和对应的参数
    filters, filter_params = [], []
    if internal_order_id is not None:
        filters.append("internal_order_id = %s")
        filter_params.append(internal_order_id)
    if external_order_id is not None:
        filters.append("external_order_id = %s")
        filter_params.append(external_order_id)
    # 如果没有提供任何筛选条件，则无法执行更新，直接返回
    if not filters:
        return

    # 构建 SET 子句部分和对应的参数
    set_parts, params = [], []
    if sync_status:
        set_parts.append("sync_status = %s")
        params.append(sync_status)
    if push:
        set_parts.append("last_push_time = NOW()")  # 使用数据库函数获取当前时间
    if ack:
        set_parts.append("last_ack_time = NOW()")

    # 将筛选条件参数追加到参数列表末尾
    params.extend(filter_params)

    # 执行更新语句，使用 OR 连接筛选条件（即更新满足任一条件的记录）
    db.execute_update(
        f"UPDATE mes_order_links SET {', '.join(set_parts)} WHERE {' OR '.join(filters)}",
        tuple(params),
    )

def enqueue_mes_outbox(db, biz_type, biz_id, external_order_id, payload, target_system="MES"):
    """
    将一条待发送给 MES 的消息加入出站队列（mes_outbox 表）。
    如果同类型、同业务ID的消息已经存在（且未处理完），则不再重复创建，而是返回已存在的记录ID。

    参数：
        db: 数据库管理器实例
        biz_type: 业务类型，例如 'TASK_COMPLETED'、'AGV_STATUS' 等
        biz_id: 业务ID（如内部订单号），用于唯一标识一条业务记录
        external_order_id: 关联的外部订单号（可能为空）
        payload: 要发送的消息内容（字典或其他可JSON序列化的对象）
        target_system: 目标系统，默认为 'MES'

    返回：
        (record_id, created_flag) 元组：
            record_id: 出站消息记录的ID（如果创建成功或已存在则返回ID，否则返回None）
            created_flag: 布尔值，True 表示本次调用创建了新记录，False 表示记录已存在
    """
    # 确保出站表存在（如果未创建则自动创建）
    ensure_mes_sync_tables(db)

    # 检查同类型、同业务ID的记录是否已存在（限制1条）
    exists = db.execute_query(
        "SELECT id FROM mes_outbox WHERE biz_type = %s AND biz_id = %s LIMIT 1",
        (biz_type, str(biz_id)),  # 将 biz_id 转为字符串确保匹配
    )
    if exists:
        # 如果已存在，返回其ID并标志为未创建
        return exists[0]["id"], False

    # 插入新记录，send_status 默认为 'PENDING'
    db.execute_update(
        "INSERT INTO mes_outbox (biz_type, biz_id, external_order_id, target_system, payload_json, send_status) VALUES (%s, %s, %s, %s, %s, %s)",
        (biz_type, str(biz_id), external_order_id, target_system, safe_json_dumps(payload), "PENDING"),
    )

    # 插入后查询新记录的ID（再次查询以确保获取）
    created = db.execute_query(
        "SELECT id FROM mes_outbox WHERE biz_type = %s AND biz_id = %s LIMIT 1",
        (biz_type, str(biz_id)),
    )
    record_id = created[0]["id"] if created else None
    return record_id, True

def process_mes_outbox_record(record_id, db=None):
    """
    处理单条出站消息记录：发送消息，更新状态，并在仿真模式下模拟MES确认。
    参数：
        record_id: mes_outbox 表中的记录ID
        db: 可选的数据库管理器实例，若不提供则内部新建一个
    返回：
        字典，包含处理结果的状态和消息
    """
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)

    # 查询指定的记录
    rows = local_db.execute_query("SELECT * FROM mes_outbox WHERE id = %s LIMIT 1", (record_id,))
    if not rows:
        return {"status": "error", "msg": "未找到对应的出站消息"}

    record = rows[0]

    # 检查 payload 是否为空（避免发送空消息）
    if not record.get("payload_json"):
        # 更新状态为失败，并记录错误信息
        local_db.execute_update(
            "UPDATE mes_outbox SET send_status = %s, retry_count = retry_count + 1, last_error = %s WHERE id = %s",
            ("FAILED", "empty payload", record_id),
        )
        return {"status": "error", "msg": "消息体为空，无法发送"}

    # 模拟发送：将状态更新为 SENT，记录发送时间（实际发送逻辑需扩展）
    local_db.execute_update(
        "UPDATE mes_outbox SET send_status = %s, sent_at = NOW(), last_error = NULL WHERE id = %s",
        ("SENT", record_id),
    )

    # 如果处于仿真模式，则立即模拟 MES 确认
    if MES_SIMULATION_MODE:
        # 将状态更新为 ACKED，记录确认时间
        local_db.execute_update(
            "UPDATE mes_outbox SET send_status = %s, acked_at = NOW(), last_error = NULL WHERE id = %s",
            ("ACKED", record_id),
        )
        # 更新关联的 mes_order_links 状态：同步状态设为 ACKED，并更新推送和确认时间
        update_mes_link_status(
            local_db,
            external_order_id=record.get("external_order_id"),
            sync_status="ACKED",
            push=True,
            ack=True
        )
        # 写入通信日志，记录仿真确认事件
        write_comm_log(
            "AGV调度系统 -> MES",
            "MES回传",
            safe_json_dumps({
                "mode": "simulation",
                "biz_type": record.get("biz_type"),
                "biz_id": record.get("biz_id"),
                "external_order_id": record.get("external_order_id"),
            })
        )
        return {"status": "success", "msg": "仿真模式已确认回传", "record_id": record_id}

    # 非仿真模式下，消息已标记为 SENT，等待外部MES确认（实际确认逻辑需另行实现）
    return {"status": "success", "msg": "消息已发送，等待外部 MES 确认", "record_id": record_id}

def process_pending_mes_outbox(limit=20, db=None):
    """
    批量处理待发送的出站消息队列。
    参数：
        limit: 最大处理数量
        db: 可选的数据库管理器实例
    返回：
        列表，包含每条记录的处理结果字典（由 process_mes_outbox_record 返回）
    """
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)

    # 查询所有状态为 PENDING 或 FAILED 的记录，按创建时间升序，限制数量
    rows = local_db.execute_query(
        "SELECT id FROM mes_outbox WHERE send_status IN ('PENDING', 'FAILED') ORDER BY created_at ASC LIMIT %s",
        (int(limit),),
    )

    results = []
    for row in rows:
        if row.get("id") is not None:
            # 逐条调用处理函数
            results.append(process_mes_outbox_record(row["id"], local_db))
    return results

def create_completion_reports(order_rows, db=None):
    """
    为已完成的订单生成完成报告，并加入出站消息队列，准备回传 MES。

    参数：
        order_rows: 订单记录列表，每条记录为字典，必须包含 order_id、target_station、weight、deadline 等字段
        db: 可选的数据库管理器实例

    返回：
        列表，包含成功创建并加入出站队列的消息ID
    """
    local_db = db or DatabaseManager()
    ensure_mes_sync_tables(local_db)

    created_ids = []  # 记录成功创建的消息ID

    for order in order_rows:
        order_id = order.get("order_id")

        # 查询 mes_order_links 表，获取该内部订单对应的外部订单号
        link = local_db.execute_query(
            "SELECT external_order_id FROM mes_order_links WHERE internal_order_id = %s LIMIT 1",
            (order_id,)
        )
        if link:
            external_order_id = link[0]["external_order_id"]
        else:
            # 如果没有关联记录，则生成一个本地唯一标识
            external_order_id = f"LOCAL-{order_id}"

        # 构建报告负载（JSON 格式）
        payload = {
            "request_id": f"RPT-{order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "external_order_id": external_order_id,
            "internal_order_id": order_id,
            "status": "COMPLETED",
            "target_station": order.get("target_station"),
            "weight": order.get("weight"),
            "deadline": order.get("deadline"),
            "report_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        }

        # 将报告加入出站队列，业务类型为 "TASK_COMPLETED"
        outbox_id, created_flag = enqueue_mes_outbox(
            local_db,
            "TASK_COMPLETED",
            order_id,                # biz_id 使用内部订单号
            external_order_id,
            payload
        )

        if created_flag and outbox_id:
            created_ids.append(outbox_id)
            # 更新订单链接状态为 COMPLETED，并记录推送时间
            update_mes_link_status(
                local_db,
                internal_order_id=order_id,
                sync_status="COMPLETED",
                push=True
            )

    return created_ids

# 仿真与 MATLAB 协调函数
def run_simulation_task():
    """
    执行一次完整的仿真任务流程：
    1. 更新仿真状态为运行中
    2. 从数据库读取待执行的订单
    3. 启动 MATLAB 引擎并调用仿真脚本
    4. 捕获 MATLAB 输出并记录日志
    5. 更新订单状态为已完成
    6. 生成任务完成报告并处理 MES 待发送消息
    7. 更新仿真状态为 finished 或 error
    """
    # 更新全局仿真状态为 running
    sim_state["status"] = "running"
    sim_state["logs"].append("后台 API：开始扫描数据库中的待分配任务。")

    # 获取数据库管理器实例
    db = DatabaseManager()
    # 确保 MES 同步所需的数据库表存在
    ensure_mes_sync_tables(db)

    # 初始化 MATLAB 引擎变量为 None
    eng = None

    try:
        # 从 mes_orders 表中查询状态为 0（待分配）的订单，按 order_id 升序排列
        orders = db.execute_query(
            "SELECT order_id, target_station, weight, deadline FROM mes_orders WHERE status = 0 ORDER BY order_id ASC"
        )

        # 如果没有待执行任务，则记录日志并直接结束
        if not orders:
            sim_state["logs"].append("系统提示：数据库中没有待执行的任务。")
            sim_state["status"] = "finished"
            return

        # 将查询结果转换为 MATLAB 可接受的二维列表（浮点数）
        # 每个订单包含 [order_id, target_station, weight, deadline]
        task_list_py = [
            [float(o["order_id"]), float(o["target_station"]), float(o["weight"]), float(o["deadline"])]
            for o in orders
        ]
        # 将 Python 列表转换为 MATLAB 的 double 类型数据
        task_list_matlab = matlab.double(task_list_py)

        sim_state["logs"].append(f"已打包 {len(task_list_py)} 条任务，正在启动 MATLAB 引擎。")

        # 启动 MATLAB 引擎（需要已安装 MATLAB Engine API for Python）
        eng = matlab.engine.start_matlab()
        sim_state["logs"].append("MATLAB 引擎启动成功。")

        # 获取当前 Python 脚本所在目录
        current_dir = os.path.dirname(os.path.abspath(__file__))
        # 构建 MATLAB 代码存放的路径（假设在 matlab_code 子目录下）
        matlab_code_dir = os.path.join(current_dir, "matlab_code")
        # 将 MATLAB 代码目录添加到 MATLAB 搜索路径中（nargout=0 表示无返回值）
        eng.addpath(matlab_code_dir, nargout=0)

        # 创建 StringIO 对象用于捕获 MATLAB 的标准输出和标准错误
        standard_out = io.StringIO()
        standard_err = io.StringIO()

        sim_state["logs"].append("正在向 MATLAB 注入订单数据并开始仿真。")

        # 调用 MATLAB 函数 Final_Thesis_Simulation_Modular_python，传入任务列表
        # nargout=0 表示该函数无返回值，stdout/stderr 参数用于捕获输出
        eng.Final_Thesis_Simulation_Modular_python(
            task_list_matlab,
            nargout=0,
            stdout=standard_out,
            stderr=standard_err
        )

        # 将捕获的标准输出逐行添加到仿真日志中（过滤空行）
        for line in standard_out.getvalue().splitlines():
            if line.strip():
                sim_state["logs"].append(f"[底层调度] {line.strip()}")

        # 将捕获的标准错误逐行添加到仿真日志中（过滤空行）
        for line in standard_err.getvalue().splitlines():
            if line.strip():
                sim_state["logs"].append(f"[底层报错] {line.strip()}")

        # 生成所有已处理订单 ID 的逗号分隔字符串，用于 SQL IN 子句
        ids_str = ",".join(str(o["order_id"]) for o in orders)
        # 更新这些订单的状态为 2（已完成）
        db.execute_update(f"UPDATE mes_orders SET status = 2 WHERE order_id IN ({ids_str})")

        # 调用函数生成任务完成报告（具体实现未给出，但推测会根据 orders 生成）
        create_completion_reports(orders, db)

        # 处理待发送给 MES 的消息，limit 参数设为订单数量
        process_pending_mes_outbox(limit=len(orders), db=db)

        sim_state["logs"].append("仿真已结束，任务状态已更新为已完成。")
        sim_state["status"] = "finished"

    except Exception as exc:
        # 若发生任何异常，记录异常信息并更新状态为 error
        sim_state["logs"].append(f"运行异常：{exc}")
        sim_state["status"] = "error"

    finally:
        # 无论成功与否，确保 MATLAB 引擎被关闭，释放资源
        if eng is not None:
            eng.quit()

def auto_generate_matlab_config():
    """
    自动生成 MATLAB 配置文件（load_agv_config.m），
    从数据库中读取当前 AGV 设备信息，并写入该文件，
    供 MATLAB 仿真脚本加载使用。
    """
    # 获取数据库管理器实例
    db = DatabaseManager()

    try:
        # 从 agv_devices 表中查询所有 AGV 信息，按 agv_id 升序排列
        agvs = db.execute_query("SELECT * FROM agv_devices ORDER BY agv_id ASC") or []

        # 获取当前 Python 脚本所在目录
        current_dir = os.path.dirname(os.path.abspath(__file__))
        # 构建 MATLAB 代码存放路径（假设在 matlab_code 子目录下）
        matlab_dir = os.path.join(current_dir, "matlab_code")
        # 确保该目录存在（如果不存在则创建）
        os.makedirs(matlab_dir, exist_ok=True)

        # 构建配置文件的完整路径，并将反斜杠替换为斜杠（MATLAB 可识别）
        file_path = os.path.join(matlab_dir, "load_agv_config.m").replace('\\', '/')

        # 以写入模式打开文件（使用 UTF-8 编码）
        with open(file_path, 'w', encoding='utf-8') as f:
            # 写入文件头注释
            f.write("% Auto generated AGV config\n\n")

            # 写入 AGV 数量
            f.write(f"num_agvs = {len(agvs)};\n")

            # 写入 AGV 类型数组（将所有 agv_type 用逗号拼接）
            f.write(f"agv_types = [{', '.join(str(agv['agv_type']) for agv in agvs)}];\n\n")

            # 遍历每个 AGV，生成对应的 MATLAB 结构体字段赋值语句
            for idx, agv in enumerate(agvs, start=1):
                f.write(f"agv_params({idx}).agv_id = '{agv['agv_id']}';\n")
                f.write(f"agv_params({idx}).type = {agv['agv_type']};\n")
                # initial_position 可能为 None，此时使用默认值 1（或其他），这里直接使用数据库值或空
                f.write(f"agv_params({idx}).initial_position = {agv.get('initial_position') or 1};\n")
                f.write(f"agv_params({idx}).speed = {agv['speed']};\n")
                f.write(f"agv_params({idx}).battery_current = {agv['battery']};\n")
                f.write(f"agv_params({idx}).e_base = {agv['e_base']};\n")
                f.write(f"agv_params({idx}).e_load_factor = {agv['e_load_factor']};\n\n")

    except Exception as exc:
        # 如果生成过程中出现异常，打印错误信息（不中断程序）
        print(f"Generate MATLAB config failed: {exc}")

@app.route('/api/start', methods=['POST'])
def api_start():
    if sim_state["status"] == "running":
        return jsonify({"msg": "已有任务正在运行"}), 400
    sim_state["logs"].clear()
    threading.Thread(target=run_simulation_task, daemon=True).start()
    return jsonify({"msg": "指令已下发"})

@app.route('/api/status', methods=['GET'])
def api_status():
    return jsonify(sim_state)

@app.route('/api/map/generate', methods=['GET'])
def api_generate_map():
    eng = None
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        matlab_code_dir = os.path.join(current_dir, "matlab_code")
        image_path = os.path.join(current_dir, "temp_factory_map.png")
        eng = matlab.engine.start_matlab()
        eng.addpath(matlab_code_dir, nargout=0)
        eng.generate_beautiful_factory_map(nargout=0)
        eng.eval(f"exportgraphics(gcf, '{image_path}', 'Resolution', 300);", nargout=0)
        eng.eval("close(gcf);", nargout=0)
        return send_file(image_path, mimetype='image/png')
    except Exception as exc:
        return jsonify({"msg": f"后台生成地图失败: {exc}"}), 500
    finally:
        if eng is not None:
            eng.quit()

# AGV 管理路由
@app.route('/api/agv/list', methods=['GET'])
def api_agv_list():
    agv_type = request.args.get('type')
    db = DatabaseManager()
    records = db.execute_query("SELECT * FROM agv_devices WHERE agv_type = %s ORDER BY agv_id ASC", (agv_type,)) if agv_type else db.execute_query("SELECT * FROM agv_devices ORDER BY agv_id ASC")
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/agv/garages', methods=['GET'])
def api_agv_garages():
    records = DatabaseManager().execute_query("SELECT agv_id, agv_type, initial_position FROM agv_devices WHERE initial_position IS NOT NULL")
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/agv/add', methods=['POST'])
def api_agv_add():
    data = request.json or {}
    db = DatabaseManager()
    if db.execute_query("SELECT * FROM agv_devices WHERE agv_id = %s", (data['agv_id'],)):
        return jsonify({"status": "error", "msg": f"编号 {data['agv_id']} 已存在。"})
    rows = db.execute_update(
        "INSERT INTO agv_devices (agv_id, agv_type, ip_address, battery, status, e_base, e_load_factor, speed, initial_position) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (data['agv_id'], data['agv_type'], data['ip_address'], data['battery'], data['status'], data['e_base'], data['e_load_factor'], data['speed'], data['initial_position']),
    )
    if rows:
        auto_generate_matlab_config()
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/agv/update', methods=['PUT'])
def api_agv_update():
    data = request.json or {}
    rows = DatabaseManager().execute_update(
        "UPDATE agv_devices SET ip_address=%s, battery=%s, status=%s, e_base=%s, e_load_factor=%s, speed=%s, initial_position=%s WHERE agv_id=%s",
        (data['ip_address'], data['battery'], data['status'], data['e_base'], data['e_load_factor'], data['speed'], data['initial_position'], data['agv_id']),
    )
    if rows:
        auto_generate_matlab_config()
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库更新失败"})

@app.route('/api/agv/delete/<agv_id>', methods=['DELETE'])
def api_agv_delete(agv_id):
    if DatabaseManager().execute_update("DELETE FROM agv_devices WHERE agv_id = %s", (agv_id,)):
        auto_generate_matlab_config()
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库删除失败"})

# 任务管理路由
@app.route('/api/tasks/list', methods=['GET'])
def api_tasks_list():
    view_type = request.args.get('view_type', type=int, default=0)
    sql = "SELECT * FROM mes_orders WHERE status IN (0, 1) ORDER BY status ASC, order_id ASC" if view_type == 0 else "SELECT * FROM mes_orders WHERE status = 2 ORDER BY order_id ASC"
    records = DatabaseManager().execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/tasks/add', methods=['POST'])
def api_tasks_add():
    data = request.json or {}
    rows = DatabaseManager().execute_update(
        "INSERT INTO mes_orders (target_station, item_type, weight, deadline, status) VALUES (%s, %s, %s, %s, 0)",
        (data['station'], data['item_type'], data['weight'], data['deadline']),
    )
    if rows:
        write_system_log('INFO', f"MES -> 上位机[HTTP/REST]: 订单入池 (工位:{data['station']}, 重量:{data['weight']})")
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/tasks/delete/<int:order_id>', methods=['DELETE'])
def api_tasks_delete(order_id):
    if DatabaseManager().execute_update("DELETE FROM mes_orders WHERE order_id = %s", (order_id,)):
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库删除失败"})

@app.route('/api/tasks/restore', methods=['POST'])
def api_tasks_restore():
    rows = DatabaseManager().execute_update("UPDATE mes_orders SET status = 0, executor_agv = NULL, actual_time = NULL, actual_distance = NULL WHERE status = 2")
    return jsonify({"status": "success", "rows": rows}) if rows else jsonify({"status": "info", "msg": "当前没有已完成任务需要复原。"})

@app.route('/api/users/list', methods=['GET'])
def api_users_list():
    records = DatabaseManager().execute_query("SELECT emp_id, name, gender, job_type, phone, email FROM sys_users ORDER BY emp_id ASC")
    return jsonify({"status": "success", "data": records if records else []})

# 用户管理路由
@app.route('/api/users/query', methods=['GET'])
def api_users_query():
    keyword = request.args.get('keyword', '')
    records = DatabaseManager().execute_query("SELECT * FROM sys_users WHERE emp_id = %s OR name = %s LIMIT 1", (keyword, keyword))
    return jsonify({"status": "success", "data": records[0]}) if records else jsonify({"status": "error", "msg": "未找到匹配的用户"})

@app.route('/api/users/add', methods=['POST'])
def api_users_add():
    data = request.json or {}
    db = DatabaseManager()
    if db.execute_query("SELECT emp_id FROM sys_users WHERE emp_id = %s", (data['emp_id'],)):
        return jsonify({"status": "error", "msg": f"工号 {data['emp_id']} 已存在。"})
    rows = db.execute_update(
        "INSERT INTO sys_users (emp_id, name, gender, ethnicity, job_type, seniority, phone, email) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        (data['emp_id'], data['name'], data['gender'], data['ethnicity'], data['job_type'], data['seniority'], data['phone'], data['email']),
    )
    return jsonify({"status": "success"}) if rows else jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/users/update', methods=['PUT'])
def api_users_update():
    data = request.json or {}
    rows = DatabaseManager().execute_update(
        "UPDATE sys_users SET name=%s, gender=%s, ethnicity=%s, job_type=%s, seniority=%s, phone=%s, email=%s, photo_path=%s WHERE emp_id=%s",
        (data['name'], data['gender'], data['ethnicity'], data['job_type'], data['seniority'], data['phone'], data['email'], data['photo_path'], data['emp_id']),
    )
    return jsonify({"status": "success"}) if rows else jsonify({"status": "error", "msg": "数据库更新失败"})

@app.route('/api/users/delete/<emp_id>', methods=['DELETE'])
def api_users_delete(emp_id):
    return jsonify({"status": "success"}) if DatabaseManager().execute_update("DELETE FROM sys_users WHERE emp_id = %s", (emp_id,)) else jsonify({"status": "error", "msg": "数据库删除失败"})

# MATLAB 回调与日志路由
@app.route('/api/logs/comm/parse', methods=['POST'])
def api_logs_comm_parse():
    return jsonify({"status": "success", "msg": "已切换为 Webhook 实时主动推送，此接口已废弃"})

@app.route('/api/matlab/webhook', methods=['POST'])
def api_matlab_webhook():
    data = request.json or {}
    if not data:
        return jsonify({"status": "error", "msg": "未接收到数据"}), 400
    msg_type = data.get('type')
    if msg_type == 'schedule_result':
        db = DatabaseManager()
        assignments = data.get('assignments', [])
        try:
            db.execute_update(
                "INSERT INTO SYS_COMM_LOGS (node_path, msg_type, content, protocol) VALUES (%s, %s, %s, %s)",
                ("调度系统 -> 后端", "调度结果", safe_json_dumps({"type": "schedule_result", "status": "GA_Complete"}), "HTTP/JSON"),
            )
            for item in assignments:
                agv_id, task_id = item['agv_id'], item['task_id']
                content = safe_json_dumps({"cmd": "assign", "agv": f"AGV-{agv_id:02d}", "task_id": task_id})
                db.execute_update(
                    "INSERT INTO SYS_COMM_LOGS (node_path, msg_type, content, protocol) VALUES (%s, %s, %s, %s)",
                    (f"上位机 -> AGV-{agv_id:02d}", "派工指令", content, "HTTP/JSON"),
                )
            return jsonify({"status": "success", "msg": "调度结果已写入通信日志"})
        except Exception as exc:
            return jsonify({"status": "error", "msg": str(exc)}), 500

    if msg_type == 'conflict_event':
        def save_conflict_async(conflict_data):
            try:
                db = DatabaseManager()
                ensure_runtime_log_tables(db)
                inserted = db.execute_update(
                    "INSERT INTO sys_conflict_logs (sim_step, agv1_id, agv1_pos, agv2_id, agv2_pos, conflict_type) VALUES (%s, %s, %s, %s, %s, %s)",
                    (conflict_data.get('sim_step'), conflict_data.get('agv1_id'), conflict_data.get('agv1_pos'), conflict_data.get('agv2_id'), conflict_data.get('agv2_pos'), conflict_data.get('conflict_type')),
                )
                if inserted <= 0:
                    sim_state['logs'].append('[Conflict DB Error] sys_conflict_logs insert returned 0.')
                    return
                write_comm_log('MATLAB -> 后端', '冲突事件', safe_json_dumps(conflict_data))
                sim_state['logs'].append(
                    f"[Conflict] T={conflict_data.get('sim_step')} AGV-{conflict_data.get('agv1_id')} vs AGV-{conflict_data.get('agv2_id')} {conflict_data.get('conflict_type')}"
                )
            except Exception as exc:
                sim_state['logs'].append(f"[Conflict DB Error] {exc}")
                print(f"Conflict event save failed: {exc}")
        threading.Thread(target=save_conflict_async, args=(data,), daemon=True).start()
        return jsonify({"status": "success", "msg": "Conflict event accepted"})
    if msg_type == 'progress':
        sim_state['progress'] = data.get('current_gen', 0)
        return jsonify({"status": "success"})
    if msg_type == 'alert':
        sim_state['logs'].append(f"[报警] {data.get('msg')}")
        return jsonify({"status": "success"})
    return jsonify({"status": "warning", "msg": "未知的报文类型"})

@app.route('/api/logs/comm/list', methods=['GET'])
def api_logs_comm_list():
    db = DatabaseManager()
    repair_comm_log_labels(db)
    records = db.execute_query("SELECT * FROM SYS_COMM_LOGS ORDER BY log_time DESC LIMIT 100")
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/comm/clear', methods=['DELETE'])
def api_logs_comm_clear():
    try:
        DatabaseManager().execute_update("TRUNCATE TABLE SYS_COMM_LOGS")
        return jsonify({"status": "success"})
    except Exception as exc:
        return jsonify({"status": "error", "msg": str(exc)}), 500

@app.route('/api/logs/code/history', methods=['GET'])
def api_logs_code_history():
    records = DatabaseManager().execute_query("SELECT id, run_time FROM matlab_run_logs ORDER BY run_time DESC")
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/code/detail/<int:log_id>', methods=['GET'])
def api_logs_code_detail(log_id):
    records = DatabaseManager().execute_query("SELECT log_content FROM matlab_run_logs WHERE id = %s", (log_id,))
    return jsonify({"status": "success", "data": records[0]['log_content']}) if records else jsonify({"status": "error", "msg": "未找到日志详情"})
# 看板路由
@app.route('/api/dashboard/sync', methods=['POST'])
def api_dashboard_sync():
    db = DatabaseManager()
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        csv_path = os.path.join(current_dir, "matlab_code", "agv_metrics.csv")
        if os.path.exists(csv_path):
            with open(csv_path, 'r', encoding='utf-8') as f:
                for line in f.readlines()[1:]:
                    parts = line.strip().split(',')
                    if len(parts) == 5:
                        agv_id, agv_type, battery, dist, turns = parts
                        db.execute_update(
                            "INSERT INTO AGV_MONITOR_STATUS (agv_id, agv_type, battery, total_distance, total_turns) VALUES (%s, %s, %s, %s, %s) ON DUPLICATE KEY UPDATE battery = VALUES(battery), total_distance = total_distance + VALUES(total_distance), total_turns = total_turns + VALUES(total_turns)",
                            (agv_id, agv_type, battery, dist, turns),
                        )
            os.remove(csv_path)
            return jsonify({"status": "success", "msg": "AGV 状态同步完成"})
        return jsonify({"status": "info", "msg": "未发现需要同步的 CSV 文件"})
    except Exception as exc:
        return jsonify({"status": "error", "msg": str(exc)}), 500

@app.route('/api/dashboard/metrics', methods=['GET'])
def api_dashboard_metrics():
    db = DatabaseManager()
    try:
        res_orders = db.execute_query("SELECT status, COUNT(*) as count FROM mes_orders GROUP BY status")
        total = completed = pending = 0
        for row in res_orders or []:
            count_val = row.get('count') or row.get('COUNT(*)') or 0
            status_val = int(row['status'])
            total += count_val
            if status_val == 2:
                completed += count_val
            elif status_val in (0, 1):
                pending += count_val
        rate = (completed / total * 100) if total else 0.0
        agv_data = db.execute_query("SELECT * FROM AGV_MONITOR_STATUS ORDER BY agv_id ASC")
        return jsonify({"status": "success", "data": {"orders": {"total": total, "completed": completed, "pending": pending, "rate": f"{rate:.1f}%"}, "agvs": agv_data if agv_data else []}})
    except Exception as exc:
        return jsonify({"status": "error", "msg": str(exc)}), 500

# 冲突日志路由
@app.route('/api/logs/conflict/list', methods=['GET'])
def api_logs_conflict_list():
    db = DatabaseManager()
    ensure_runtime_log_tables(db)
    records = db.execute_query("SELECT * FROM sys_conflict_logs ORDER BY report_time DESC LIMIT 100")
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/conflict/clear', methods=['DELETE'])
def api_logs_conflict_clear():
    try:
        db = DatabaseManager()
        ensure_runtime_log_tables(db)
        db.execute_update("TRUNCATE TABLE sys_conflict_logs")
        return jsonify({"status": "success"})
    except Exception as exc:
        return jsonify({"status": "error", "msg": str(exc)}), 500
# MES 相关路由
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
        return jsonify({"status": "success", "msg": "请求已处理，已按幂等规则返回历史结果", "idempotent": True, "data": existed[0]})
    same_external = db.execute_query("SELECT * FROM mes_order_links WHERE external_order_id = %s LIMIT 1", (external_order_id,))
    if same_external:
        db.execute_update(
            "INSERT INTO mes_inbox (request_id, external_order_id, msg_type, source_system, payload_json, receive_status, internal_order_id, processed_at) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())",
            (request_id, external_order_id, 'ORDER_INBOUND', source_system, safe_json_dumps(data), 'DUPLICATE', same_external[0]['internal_order_id']),
        )
        return jsonify({"status": "success", "msg": "外部订单已存在，已忽略重复建单", "idempotent": True, "data": same_external[0]})
    db.execute_update(
        "INSERT INTO mes_inbox (request_id, external_order_id, msg_type, source_system, payload_json, receive_status) VALUES (%s, %s, %s, %s, %s, %s)",
        (request_id, external_order_id, 'ORDER_INBOUND', source_system, safe_json_dumps(data), 'RECEIVED'),
    )
    try:
        db.execute_update(
            "INSERT INTO mes_orders (target_station, item_type, weight, deadline, status) VALUES (%s, %s, %s, %s, 0)",
            (target_station, item_type, weight, deadline),
        )
        rows = db.execute_query(
            "SELECT order_id FROM mes_orders WHERE target_station = %s AND item_type = %s AND weight = %s AND deadline = %s AND status = 0 ORDER BY order_id DESC LIMIT 1",
            (target_station, item_type, weight, deadline),
        )
        if not rows:
            raise RuntimeError("订单已写入，但未能定位内部订单号")
        internal_order_id = rows[0]['order_id']
        db.execute_update(
            "INSERT INTO mes_order_links (request_id, external_order_id, internal_order_id, source_system, sync_status) VALUES (%s, %s, %s, %s, %s)",
            (request_id, external_order_id, internal_order_id, source_system, 'RECEIVED'),
        )
        db.execute_update(
            "UPDATE mes_inbox SET receive_status = %s, internal_order_id = %s, processed_at = NOW() WHERE request_id = %s",
            ('PROCESSED', internal_order_id, request_id),
        )
        accept_payload = {
            'request_id': f'ACK-{request_id}',
            'external_order_id': external_order_id,
            'internal_order_id': internal_order_id,
            'status': 'ACCEPTED',
            'accepted_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        }
        enqueue_mes_outbox(db, 'ORDER_ACCEPTED', internal_order_id, external_order_id, accept_payload, target_system=source_system)
        process_pending_mes_outbox(limit=5, db=db)
        write_comm_log('MES -> AGV调度系统', 'MES订单入站', safe_json_dumps(accept_payload))
        return jsonify({"status": "success", "msg": "MES 订单已入站并进入待调度队列", "data": {'internal_order_id': internal_order_id, 'external_order_id': external_order_id, 'request_id': request_id}})
    except Exception as exc:
        db.execute_update(
            "UPDATE mes_inbox SET receive_status = %s, error_msg = %s, processed_at = NOW() WHERE request_id = %s",
            ('FAILED', str(exc)[:255], request_id),
        )
        return jsonify({"status": "error", "msg": f"MES 订单入站失败: {exc}"}), 500

@app.route('/api/mes/inbox/list', methods=['GET'])
def api_mes_inbox_list():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    limit = request.args.get('limit', default=100, type=int)
    rows = db.execute_query("SELECT * FROM mes_inbox ORDER BY received_at DESC LIMIT %s", (max(1, min(limit, 500)),))
    return jsonify({"status": "success", "data": rows if rows else []})

@app.route('/api/mes/outbox/list', methods=['GET'])
def api_mes_outbox_list():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    limit = request.args.get('limit', default=100, type=int)
    rows = db.execute_query("SELECT * FROM mes_outbox ORDER BY created_at DESC LIMIT %s", (max(1, min(limit, 500)),))
    return jsonify({"status": "success", "data": rows if rows else []})

@app.route('/api/mes/outbox/process', methods=['POST'])
def api_mes_outbox_process():
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    payload = request.get_json(silent=True) or {}
    limit = int(payload.get('limit', 20))
    results = process_pending_mes_outbox(limit=limit, db=db)
    return jsonify({"status": "success", "msg": f"已处理 {len(results)} 条待发送消息", "data": results})

@app.route('/api/mes/outbox/retry/<int:record_id>', methods=['POST'])
def api_mes_outbox_retry(record_id):
    db = DatabaseManager()
    ensure_mes_sync_tables(db)
    db.execute_update(
        "UPDATE mes_outbox SET send_status = %s, retry_count = retry_count + 1, last_error = NULL WHERE id = %s",
        ('PENDING', record_id),
    )
    result = process_mes_outbox_record(record_id, db)
    return (jsonify(result), 200) if result.get('status') == 'success' else (jsonify(result), 400)

ensure_mes_sync_tables()
ensure_runtime_log_tables()
repair_comm_log_labels()

if __name__ == '__main__':
    print('Unified backend API started at http://127.0.0.1:5000')
    app.run(host='0.0.0.0', port=5000, debug=False)


