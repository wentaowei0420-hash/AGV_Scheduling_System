# backend_api.py
from flask import Flask, jsonify, request ,send_file      # 导入 Flask 框架的核心组件：Flask 应用类、jsonify（返回 JSON 响应）、request（获取请求数据）
import threading                               # 导入 threading 模块，用于在后台线程中运行耗时任务，避免阻塞 Flask 主线程
import io                                       # 导入 io 模块，虽然此处未直接使用，但可能是之前版本遗留，或用于其他用途（实际代码中用到了自定义流，未使用 io.StringIO）
import os                                       # 导入 os 模块，用于文件和路径操作（例如获取当前文件目录）
import matlab.engine                            # 导入 MATLAB 引擎 Python 包，用于启动 MATLAB 进程并调用 MATLAB 函数
from db_manager import DatabaseManager          # 从自定义模块导入数据库管理类，用于执行数据库查询和更新
import json
app = Flask(__name__)                           # 创建 Flask 应用实例，__name__ 是当前模块名，用于定位资源

# 全局状态字典，用于保存在内存中的仿真状态
sim_state = {
    "status": "idle",  # 当前任务状态：idle（空闲）、running（运行中）、finished（已完成）、error（出错）
    "logs": [],        # 存储运行过程中产生的日志列表，每条日志为字符串
    "progress": 0      # 进度百分比（目前未使用，但预留字段）
}
# ================= 新增：完美支持换行与 MATLAB 引擎检查的拦截器 =================

def run_simulation_task():
    """修改后的核心逻辑：使用自定义流实现实时同步打印"""
    sim_state["status"] = "running"                           # 将状态更新为运行中
    sim_state["logs"].append("后台 API：开始扫描数据库中的待分配任务...")  # 记录日志

    db = DatabaseManager()                                    # 实例化数据库管理器
    eng = None                                                # 初始化 MATLAB 引擎变量，以便在 finally 中安全退出

    try:
        # 1. 读取任务
        # 从 mes_orders 表查询所有状态为 0（待分配）的任务，按 order_id 升序排列
        sql = "SELECT order_id, target_station, weight, deadline FROM mes_orders WHERE status = 0 ORDER BY order_id ASC"
        orders = db.execute_query(sql)                        # 执行查询，返回字典列表

        if not orders:                                        # 如果没有待执行的任务
            sim_state["logs"].append("【系统提示】: 数据库中没有待执行的任务。")
            sim_state["status"] = "finished"                  # 将状态设为 finished，结束任务
            return

        # 2. 转换数据为 MATLAB 矩阵
        task_list_py = []                                     # 创建一个 Python 列表，用于存储转换后的任务数据
        for order in orders:                                  # 遍历每个任务
            task_list_py.append([                             # 将每个任务转换为 [order_id, target_station, weight, deadline] 的列表
                float(order['order_id']),                     # 将 order_id 转为浮点数（MATLAB 需要数值类型）
                float(order['target_station']),               # 目标站点
                float(order['weight']),                        # 权重或任务量
                float(order['deadline'])                       # 截止时间
            ])
        task_list_matlab = matlab.double(task_list_py)         # 将 Python 列表转换为 MATLAB 的 double 矩阵

        sim_state["logs"].append(f"成功打包 {len(task_list_py)} 条任务，正在启动 MATLAB 引擎...")

        # 3. 启动 MATLAB 引擎并执行
        eng = matlab.engine.start_matlab()                     # 启动 MATLAB 引擎进程
        sim_state["logs"].append("MATLAB 引擎启动成功！")

        current_dir = os.path.dirname(os.path.abspath(__file__))          # 获取当前 Python 文件所在目录
        matlab_code_dir = os.path.join(current_dir, "matlab_code")        # 拼接 MATLAB 代码文件夹路径
        eng.addpath(matlab_code_dir, nargout=0)                           # 将该路径添加到 MATLAB 的搜索路径中

        # ==================== 核心修改区域 ====================
        # 废弃原有的 out = io.StringIO() 和 err = io.StringIO()
        # 实例化自定义的实时流对象，并带上前端需要的识别前缀
        standard_out = io.StringIO()
        standard_err = io.StringIO()

        sim_state["logs"].append("正在向 MATLAB 注入订单数据并开始仿真...")

        eng.Final_Thesis_Simulation_Modular_python(                 # 调用 MATLAB 函数，函数名可能为 Final_Thesis_Simulation_Modular_python
            task_list_matlab,                                       # 传入任务数据矩阵
            nargout=0,                                              # 指定该函数没有返回值
            stdout=standard_out,                                    # 将 MATLAB 的标准输出重定向到 realtime_out
            stderr=standard_err                                     # 将 MATLAB 的错误输出重定向到 realtime_err
        )
        # 3. 仿真跑完后，一口气把桶里的东西全倒出来，切分换行，加上前缀存入日志
        out_text = standard_out.getvalue()
        if out_text:
            for line in out_text.splitlines():
                if line.strip():
                    sim_state["logs"].append(f"【底层调度】: {line.strip()}")

        err_text = standard_err.getvalue()
        if err_text:
            for line in err_text.splitlines():
                if line.strip():
                    sim_state["logs"].append(f"🚨【底层报错】: {line.strip()}")
        # 4. 更新数据库状态
        order_ids = [str(o['order_id']) for o in orders]           # 提取所有任务的 order_id，并转为字符串
        ids_str = ",".join(order_ids)                              # 用逗号连接成字符串，用于 SQL IN 子句
        # 更新 mes_orders 表，将这些任务的状态设为 2（已完成）
        update_sql = f"UPDATE mes_orders SET status = 2 WHERE order_id IN ({ids_str})"
        db.execute_update(update_sql)                               # 执行更新

        sim_state["logs"].append("仿真顺利结束！已将任务状态更新为【已完成】。")
        sim_state["status"] = "finished"                            # 更新状态为 finished

    except Exception as e:                                          # 捕获任何异常
        sim_state["logs"].append(f"【运行异常】: {str(e)}")         # 记录异常信息
        sim_state["status"] = "error"                               # 更新状态为 error
    finally:
        if eng is not None:                                         # 如果 MATLAB 引擎已启动
            eng.quit()                                              # 退出 MATLAB 引擎，释放资源

def auto_generate_matlab_config():
    """内部辅助函数：每当数据库 AGV 有变动时，自动更新 MATLAB 的 .m 配置文件"""
    db = DatabaseManager()
    try:
        agvs = db.execute_query("SELECT * FROM agv_devices ORDER BY agv_id ASC")
        if agvs is None:
            agvs = []

        current_dir = os.path.dirname(os.path.abspath(__file__))
        matlab_dir = os.path.join(current_dir, "matlab_code")
        os.makedirs(matlab_dir, exist_ok=True)
        file_path = os.path.join(matlab_dir, "load_agv_config.m").replace('\\', '/')

        with open(file_path, 'w', encoding='utf-8') as f:
            f.write("% ===================================================\n")
            f.write("% 自动生成的 AGV 物理参数配置文件 (API 自动触发更新)\n")
            f.write("% ===================================================\n\n")
            f.write(f"num_agvs = {len(agvs)};\n")

            agv_types = [str(agv['agv_type']) for agv in agvs]
            f.write(f"agv_types = [{', '.join(agv_types)}];\n\n")

            for i, agv in enumerate(agvs):
                idx = i + 1
                initial_pos = agv['initial_position'] if agv['initial_position'] else 1
                f.write(f"agv_params({idx}).agv_id = '{agv['agv_id']}';\n")
                f.write(f"agv_params({idx}).type = {agv['agv_type']};\n")
                f.write(f"agv_params({idx}).initial_position = {initial_pos};\n")
                f.write(f"agv_params({idx}).speed = {agv['speed']};\n")
                f.write(f"agv_params({idx}).battery_current = {agv['battery']};\n")
                f.write(f"agv_params({idx}).e_base = {agv['e_base']};\n")
                f.write(f"agv_params({idx}).e_load_factor = {agv['e_load_factor']};\n\n")
    except Exception as e:
        print(f"后台生成 MATLAB 配置文件失败: {e}")

@app.route('/api/start', methods=['POST'])                          # 定义路由 /api/start，仅接受 POST 请求
def api_start():
    if sim_state["status"] == "running":                            # 如果当前已有任务正在运行
        return jsonify({"msg": "已有任务正在运行"}), 400            # 返回错误响应，状态码 400

    sim_state["logs"].clear()                                       # 清空旧日志，为新的任务做准备
    # 启动后台独立线程执行仿真
    threading.Thread(target=run_simulation_task, daemon=True).start()  # 创建并启动一个守护线程，执行 run_simulation_task
    return jsonify({"msg": "指令已下发"})                            # 返回成功响应

@app.route('/api/status', methods=['GET'])                          # 定义路由 /api/status，仅接受 GET 请求
def api_status():
    return jsonify(sim_state)                                       # 直接将 sim_state 字典作为 JSON 返回

@app.route('/api/map/generate', methods=['GET'])
def api_generate_map():
    """
    接收前端请求，在后台隐式启动 MATLAB 渲染地图，
    导出为高清 PNG 图片并返回给前端。
    """
    eng = None
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        matlab_code_dir = os.path.join(current_dir, "matlab_code")

        # 定义生成的图片临时保存路径
        image_path = os.path.join(current_dir, "temp_factory_map.png")

        # 1. 启动 MATLAB 引擎
        eng = matlab.engine.start_matlab()
        eng.addpath(matlab_code_dir, nargout=0)

        # 调用您的地图生成脚本，图会画在刚才创建的不可见 figure 上
        eng.generate_beautiful_factory_map(nargout=0)

        # 3. 导出为高清图片并关闭图窗
        # '-dpng' 表示存为 PNG，'-r300' 表示 300 dpi 高分辨率
        eng.eval(f"exportgraphics(gcf, '{image_path}', 'Resolution', 300);", nargout=0)
        eng.eval("close(gcf);", nargout=0)  # 画完立刻关闭

        # 4. 将图片作为文件流发送给前端
        return send_file(image_path, mimetype='image/png')

    except Exception as e:
        return jsonify({"msg": f"后台生成地图失败: {str(e)}"}), 500
    finally:
        if eng is not None:
            eng.quit()

@app.route('/api/agv/list', methods=['GET'])
def api_agv_list():
    """获取 AGV 列表（可按类型过滤）"""
    agv_type = request.args.get('type')
    db = DatabaseManager()
    if agv_type:
        sql = "SELECT * FROM agv_devices WHERE agv_type = %s ORDER BY agv_id ASC"
        records = db.execute_query(sql, (agv_type,))
    else:
        sql = "SELECT * FROM agv_devices ORDER BY agv_id ASC"
        records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/agv/garages', methods=['GET'])
def api_agv_garages():
    """获取所有已被占用的车库信息"""
    db = DatabaseManager()
    sql = "SELECT agv_id, agv_type, initial_position FROM agv_devices WHERE initial_position IS NOT NULL"
    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/agv/add', methods=['POST'])
def api_agv_add():
    """新增 AGV"""
    data = request.json
    db = DatabaseManager()

    if db.execute_query("SELECT * FROM agv_devices WHERE agv_id = %s", (data['agv_id'],)):
        return jsonify({"status": "error", "msg": f"编号 {data['agv_id']} 已存在！"})

    sql = """INSERT INTO agv_devices 
             (agv_id, agv_type, ip_address, battery, status, e_base, e_load_factor, speed, initial_position) 
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)"""
    params = (data['agv_id'], data['agv_type'], data['ip_address'], data['battery'], data['status'],
              data['e_base'], data['e_load_factor'], data['speed'], data['initial_position'])

    if db.execute_update(sql, params) is not None:
        auto_generate_matlab_config()  # 数据库一变，立刻更新 MATLAB 文件
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/agv/update', methods=['PUT'])
def api_agv_update():
    """修改 AGV"""
    data = request.json
    db = DatabaseManager()
    sql = """UPDATE agv_devices SET 
             ip_address=%s, battery=%s, status=%s, e_base=%s, e_load_factor=%s, speed=%s, initial_position=%s 
             WHERE agv_id=%s"""
    params = (data['ip_address'], data['battery'], data['status'], data['e_base'],
              data['e_load_factor'], data['speed'], data['initial_position'], data['agv_id'])

    if db.execute_update(sql, params) is not None:
        auto_generate_matlab_config()  # 自动更新 MATLAB 文件
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库更新失败"})

@app.route('/api/agv/delete/<agv_id>', methods=['DELETE'])
def api_agv_delete(agv_id):
    """删除 AGV"""
    db = DatabaseManager()
    sql = "DELETE FROM agv_devices WHERE agv_id = %s"
    if db.execute_update(sql, (agv_id,)) is not None:
        auto_generate_matlab_config()  # 自动更新 MATLAB 文件
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库删除失败"})

@app.route('/api/tasks/list', methods=['GET'])
def api_tasks_list():
    """获取任务列表，支持分类视图过滤"""
    # 0: 待分配/执行中, 2: 已完成
    view_type = request.args.get('view_type', type=int, default=0)
    db = DatabaseManager()

    if view_type == 0:
        sql = "SELECT * FROM mes_orders WHERE status IN (0, 1) ORDER BY status ASC, order_id ASC"
    else:
        sql = "SELECT * FROM mes_orders WHERE status = 2 ORDER BY order_id ASC"

    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/tasks/add', methods=['POST'])
def api_tasks_add():
    """新增任务到订单池，并自动记录系统日志"""
    data = request.json
    db = DatabaseManager()

    sql = "INSERT INTO mes_orders (target_station, item_type, weight, deadline, status) VALUES (%s, %s, %s, %s, 0)"
    params = (data['station'], data['item_type'], data['weight'], data['deadline'])

    if db.execute_update(sql, params) is not None:
        # 【架构优化】后端自动写入系统日志，前端无需再碰日志表
        log_sql = "INSERT INTO system_logs (log_type, content) VALUES (%s, %s)"
        log_msg = f"MES -> 上位机 [HTTP/REST]: 订单入池 (工位:{data['station']}, 重量:{data['weight']})"
        db.execute_update(log_sql, ('INFO', log_msg))
        return jsonify({"status": "success"})

    return jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/tasks/delete/<int:order_id>', methods=['DELETE'])
def api_tasks_delete(order_id):
    """物理删除指定的任务"""
    db = DatabaseManager()
    sql = "DELETE FROM mes_orders WHERE order_id = %s"
    if db.execute_update(sql, (order_id,)) is not None:
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库删除失败"})

@app.route('/api/tasks/restore', methods=['POST'])
def api_tasks_restore():
    """一键复原：将所有已完成(2)的任务重置为待分配(0)"""
    db = DatabaseManager()
    sql = """UPDATE mes_orders 
             SET status = 0, executor_agv = NULL, actual_time = NULL, actual_distance = NULL 
             WHERE status = 2"""
    rows = db.execute_update(sql)

    if rows is not None and rows > 0:
        return jsonify({"status": "success", "rows": rows})
    return jsonify({"status": "info", "msg": "当前没有已完成的任务需要复原。"})

@app.route('/api/users/list', methods=['GET'])
def api_users_list():
    """获取所有用户列表（用于表格展示）"""
    db = DatabaseManager()
    sql = "SELECT emp_id, name, gender, job_type, phone, email FROM sys_users ORDER BY emp_id ASC"
    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/users/query', methods=['GET'])
def api_users_query():
    """精确查询单个用户详细信息（支持工号或姓名）"""
    keyword = request.args.get('keyword', '')
    db = DatabaseManager()
    sql = "SELECT * FROM sys_users WHERE emp_id = %s OR name = %s LIMIT 1"
    records = db.execute_query(sql, (keyword, keyword))
    if records:
        return jsonify({"status": "success", "data": records[0]})
    return jsonify({"status": "error", "msg": "未查找到匹配的用户"})

@app.route('/api/users/add', methods=['POST'])
def api_users_add():
    """新增用户信息"""
    data = request.json
    db = DatabaseManager()

    # 检查主键冲突
    check_sql = "SELECT emp_id FROM sys_users WHERE emp_id = %s"
    if db.execute_query(check_sql, (data['emp_id'],)):
        return jsonify({"status": "error", "msg": f"工号 {data['emp_id']} 已存在！"})

    sql = """INSERT INTO sys_users 
             (emp_id, name, gender, ethnicity, job_type, seniority, phone, email) 
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"""
    params = (data['emp_id'], data['name'], data['gender'], data['ethnicity'],
              data['job_type'], data['seniority'], data['phone'], data['email'])

    if db.execute_update(sql, params) is not None:
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库插入失败"})

@app.route('/api/users/update', methods=['PUT'])
def api_users_update():
    """修改更新用户信息"""
    data = request.json
    db = DatabaseManager()
    sql = """UPDATE sys_users SET 
             name=%s, gender=%s, ethnicity=%s, job_type=%s, 
             seniority=%s, phone=%s, email=%s, photo_path=%s
             WHERE emp_id=%s"""
    params = (data['name'], data['gender'], data['ethnicity'], data['job_type'],
              data['seniority'], data['phone'], data['email'], data['photo_path'], data['emp_id'])

    if db.execute_update(sql, params) is not None:
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库更新失败"})

@app.route('/api/users/delete/<emp_id>', methods=['DELETE'])
def api_users_delete(emp_id):
    """物理删除指定的单个用户"""
    db = DatabaseManager()
    sql = "DELETE FROM sys_users WHERE emp_id = %s"
    if db.execute_update(sql, (emp_id,)) is not None:
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "msg": "数据库删除失败"})

@app.route('/api/logs/comm/parse', methods=['POST'])
def api_logs_comm_parse():
    """【已废弃】保留此空接口，仅仅是为了防止旧版前端代码调用时弹窗报错"""
    return jsonify({"status": "success", "msg": "已切换为 Webhook 实时主动推送，此接口已废弃"})

@app.route('/api/matlab/webhook', methods=['POST'])
def api_matlab_webhook():
    """接收 MATLAB 主动推送过来的实时数据（完全替代原来的 CSV 文件）"""
    # 从 Flask 全局请求对象 request 中获取 JSON 格式的请求体，并解析为 Python 字典
    # request.json 只有在 Content-Type 为 application/json 时才会自动解析
    data = request.json
    # 如果没有接收到任何数据（data 为 None 或空字典），返回错误响应
    if not data:
        # 返回 JSON 格式的错误信息，状态码 400（客户端错误）
        return jsonify({"status": "error", "msg": "未接收到数据"}), 400

    # 从数据字典中获取 'type' 字段，用于判断报文类型（如 schedule_result, conflict_event 等）
    msg_type = data.get('type')

    # ========================================================
    # 1. 处理：GA 算法调度结果
    # ========================================================
    if msg_type == 'schedule_result':
        # 实例化数据库管理器（按需创建连接，优化资源使用）
        db = DatabaseManager()
        # 获取数据中的 'assignments' 字段，如果不存在则默认为空列表
        assignments = data.get('assignments', [])
        try:
            # 定义插入 SQL 语句，向 SYS_COMM_LOGS 表插入通信日志
            sql = "INSERT INTO SYS_COMM_LOGS (node_path, msg_type, content, protocol) VALUES (%s, %s, %s, %s)"
            # 记录宏观汇总日志：表示调度中心向上位机发送了算法结果
            db.execute_update(sql, ("调度中心 -> 上位机", "算法结果",
                                    "{'status': 'GA_Complete', 'msg': '最优路径组合已生成'}", "HTTP/JSON"))

            # 遍历分配清单中的每一个任务分配项
            for item in assignments:
                agv_id = item['agv_id']        # AGV 编号
                task_id = item['task_id']      # 任务编号
                # 构造派工指令的详细内容，格式化为 JSON 字符串
                content = json.dumps({"cmd": "assign", "agv": f"AGV-{agv_id:02d}", "task_id": task_id},
                                     ensure_ascii=False)  # ensure_ascii=False 允许中文等非 ASCII 字符
                # 将每条派工指令写入日志表，节点路径表示上位机向特定 AGV 发送指令
                db.execute_update(sql, (f"上位机 -> AGV-{agv_id:02d}", "派工指令", content, "HTTP/JSON"))

            # 打印成功信息，显示接收并入库的指令数量
            print(f"【MATLAB 主动汇报】已成功接收并入库 {len(assignments)} 条调度指令！")
            # 返回成功响应，状态码默认为 200
            return jsonify({"status": "success", "msg": "调度报文已入库"})
        except Exception as e:
            # 如果发生任何异常（数据库错误、JSON 解析错误等），打印错误并返回 500 服务器错误
            print(f"【报错】处理 MATLAB 调度结果失败: {e}")
            return jsonify({"status": "error", "msg": str(e)}), 500

    # ========================================================
    # 2. 处理：实时路径冲突与死锁告警 (异步处理)
    # ========================================================
    elif msg_type == 'conflict_event':

        # 内部函数：专门用于在后台线程中写数据库，避免阻塞主请求响应
        def save_conflict_async(conflict_data):
            try:
                # 在子线程中重新实例化 DatabaseManager 是极其正确的做法，防止线程抢占！
                # 因为主线程的数据库连接可能不是线程安全的，所以每个线程单独创建连接
                thread_db = DatabaseManager()
                # 插入冲突日志的 SQL 语句，包含仿真步数、两个 AGV 的 ID 和位置、冲突类型
                sql = """INSERT INTO sys_conflict_logs 
                         (sim_step, agv1_id, agv1_pos, agv2_id, agv2_pos, conflict_type) 
                         VALUES (%s, %s, %s, %s, %s, %s)"""
                # 执行插入，参数从 conflict_data 字典中获取
                thread_db.execute_update(sql, (
                    conflict_data.get('sim_step'),
                    conflict_data.get('agv1_id'),
                    conflict_data.get('agv1_pos'),
                    conflict_data.get('agv2_id'),
                    conflict_data.get('agv2_pos'),
                    conflict_data.get('conflict_type')
                ))

                # 打印冲突告警信息，方便实时监控
                print(f"⚠️【冲突告警】步数:{conflict_data.get('sim_step')} | "
                      f"AGV-{conflict_data.get('agv1_id')} {conflict_data.get('agv1_pos')} 与 "
                      f"AGV-{conflict_data.get('agv2_id')} {conflict_data.get('agv2_pos')} 发生 {conflict_data.get('conflict_type')}")
            except Exception as e:
                # 如果后台写库失败，打印错误但不影响主线程返回
                print(f"【后台写入报错】记录冲突日志失败: {e}")

        # 启动后台独立线程执行 save_conflict_async 函数，传入原始数据
        # daemon=True 表示当主线程结束时，该线程也会自动结束（防止程序无法退出）
        threading.Thread(target=save_conflict_async, args=(data,), daemon=True).start()

        # 主线程瞬间返回成功响应，绝不阻塞 MATLAB 动画（保证实时性）
        return jsonify({"status": "success", "msg": "已接收冲突事件，正在后台异步入库"})

    # ========================================================
    # 3. 处理：算法进度实时更新（预留扩展）
    # ========================================================
    elif msg_type == 'progress':
        # 获取当前迭代次数和最大迭代次数
        current_gen = data.get('current_gen')
        max_gen = data.get('max_gen')
        # 打印进度信息
        print(f"【MATLAB 进度汇报】遗传算法迭代中: {current_gen} / {max_gen}")
        # 返回成功响应，无需其他操作
        return jsonify({"status": "success"})

    # ========================================================
    # 4. 处理：设备异常告警（预留扩展）
    # ========================================================
    elif msg_type == 'alert':
        # 打印报警信息
        print(f"🚨【MATLAB 紧急报警】: {data.get('msg')}")
        return jsonify({"status": "success"})

    # ========================================================
    # 兜底：未知的报文类型
    # ========================================================
    # 如果 msg_type 不是以上任何一种，返回警告响应，状态码仍为 200（也可用 400，但通常不影响）
    return jsonify({"status": "warning", "msg": "未知的报文类型"})

@app.route('/api/logs/comm/list', methods=['GET'])
def api_logs_comm_list():
    """获取通信交互日志列表 (前 100 条)"""
    db = DatabaseManager()
    sql = "SELECT * FROM SYS_COMM_LOGS ORDER BY log_time DESC LIMIT 100"
    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/comm/clear', methods=['DELETE'])
def api_logs_comm_clear():
    """清空通信交互日志"""
    db = DatabaseManager()
    try:
        db.execute_update("TRUNCATE TABLE SYS_COMM_LOGS")
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500

@app.route('/api/logs/code/history', methods=['GET'])
def api_logs_code_history():
    """获取 MATLAB 运行历史记录的时间列表"""
    db = DatabaseManager()
    sql = "SELECT id, run_time FROM matlab_run_logs ORDER BY run_time DESC"
    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/code/detail/<int:log_id>', methods=['GET'])
def api_logs_code_detail(log_id):
    """获取特定一条 MATLAB 运行历史的具体代码日志内容"""
    db = DatabaseManager()
    sql = "SELECT log_content FROM matlab_run_logs WHERE id = %s"
    records = db.execute_query(sql, (log_id,))
    if records:
        return jsonify({"status": "success", "data": records[0]['log_content']})
    return jsonify({"status": "error", "msg": "未找到日志详情"})

@app.route('/api/dashboard/sync', methods=['POST'])
def api_dashboard_sync():
    """解析 MATLAB 生成的 AGV 状态 CSV 文件并同步到数据库 (支持里程与磨损累加)"""
    db = DatabaseManager()
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        csv_path = os.path.join(current_dir, "matlab_code", "agv_metrics.csv")

        if os.path.exists(csv_path):
            with open(csv_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()[1:]  # 跳过表头
                for line in lines:
                    parts = line.strip().split(',')
                    if len(parts) == 5:
                        agv_id, agv_type, battery, dist, turns = parts

                        sql = """
                            INSERT INTO AGV_MONITOR_STATUS 
                            (agv_id, agv_type, battery, total_distance, total_turns) 
                            VALUES (%s, %s, %s, %s, %s)
                            ON DUPLICATE KEY UPDATE 
                                battery = VALUES(battery),
                                total_distance = total_distance + VALUES(total_distance),
                                total_turns = total_turns + VALUES(total_turns)
                        """
                        # 使用参数化查询防注入，更加安全
                        db.execute_update(sql, (agv_id, agv_type, battery, dist, turns))

            # 同步完成后删除文件极其重要：防止下次启动时重复读旧文件导致数据多算一倍！
            os.remove(csv_path)
            return jsonify({"status": "success", "msg": "AGV 状态同步并累加完成"})
        return jsonify({"status": "info", "msg": "未发现需要同步的 CSV 文件"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500

@app.route('/api/dashboard/metrics', methods=['GET'])
def api_dashboard_metrics():
    """获取看板所需的 宏观订单指标 和 物理设备状态"""
    db = DatabaseManager()
    try:
        # 1. 统计订单全局指标
        res_orders = db.execute_query("SELECT status, COUNT(*) as count FROM mes_orders GROUP BY status")
        total, completed, pending = 0, 0, 0

        if res_orders:
            for row in res_orders:
                count_val = row.get('count') or row.get('COUNT(*)') or 0
                status_val = int(row['status'])
                total += count_val
                if status_val == 2:
                    completed += count_val
                elif status_val in (0, 1):
                    pending += count_val

        rate = (completed / total * 100) if total > 0 else 0.0
        orders_data = {
            "total": total,
            "completed": completed,
            "pending": pending,
            "rate": f"{rate:.1f}%"
        }

        # 2. 拉取 AGV 设备健康度
        agv_data = db.execute_query("SELECT * FROM AGV_MONITOR_STATUS ORDER BY agv_id ASC")

        return jsonify({
            "status": "success",
            "data": {
                "orders": orders_data,
                "agvs": agv_data if agv_data else []
            }
        })
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500

@app.route('/api/logs/conflict/list', methods=['GET'])
def api_logs_conflict_list():
    """获取路径冲突告警日志列表"""
    db = DatabaseManager()
    # 按照时间倒序，最新的冲突排在最前面
    sql = "SELECT * FROM sys_conflict_logs ORDER BY report_time DESC LIMIT 100"
    records = db.execute_query(sql)
    return jsonify({"status": "success", "data": records if records else []})

@app.route('/api/logs/conflict/clear', methods=['DELETE'])
def api_logs_conflict_clear():
    """清空路径冲突日志"""
    db = DatabaseManager()
    try:
        db.execute_update("TRUNCATE TABLE sys_conflict_logs")
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500

if __name__ == '__main__':                                          # 如果直接运行此脚本（而不是被导入）
    print("后台引擎 API 服务已启动，运行在 http://127.0.0.1:5000")   # 打印启动信息
    app.run(host='0.0.0.0', port=5000, debug=False)                 # 启动 Flask 开发服务器，监听所有网络接口，端口 5000，关闭调试模式