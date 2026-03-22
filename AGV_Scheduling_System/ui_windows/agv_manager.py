import requests  # 导入 requests 库，用于发送 HTTP 请求
from PyQt5.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QTableWidget,
                             QTableWidgetItem, QHeaderView, QFrame, QGridLayout, QLineEdit,
                             QSpinBox, QComboBox, QLabel, QMessageBox, QDoubleSpinBox)
# 从 PyQt5 导入所需的控件类


class AGVManagerWindow(QDialog):
    """纯 API 驱动的 AGV设备管理窗口"""

    def __init__(self, parent=None):
        """构造函数：初始化窗口属性、API 地址和 UI，并加载数据"""
        super().__init__(parent)  # 调用父类 QDialog 的构造函数
        self.setWindowTitle("AGV 设备管理")  # 设置窗口标题
        self.resize(1000, 650)  # 设置窗口初始宽度 1000，高度 650 像素
        self.api_base_url = "http://127.0.0.1:5000/api/agv"  # 定义后端 API 的基础地址
        self.current_agv_type = 1  # 当前显示的 AGV 类型：1 表示托举式，2 表示叉车式
        self.initUI()  # 调用初始化 UI 的方法
        self.load_data()  # 调用加载数据的方法，从 API 获取数据并显示

    def initUI(self):
        """初始化用户界面：顶部类型切换按钮、中间表格、底部表单和操作按钮"""
        # 创建主垂直布局
        main_layout = QVBoxLayout(self)

        # ==================== 1. 顶部：类型切换按钮 ====================
        top_layout = QHBoxLayout()  # 创建水平布局用于放置按钮
        self.btn_lifting = QPushButton("📦 托举式 AGV ")   # 托举式 AGV 按钮
        self.btn_forklift = QPushButton("🚜 叉车式 AGV ")   # 叉车式 AGV 按钮
        self.btn_garage_status = QPushButton("🅿️ 车库占用情况")  # 车库占用情况按钮

        # 定义按钮激活样式：蓝色背景、白色文字、加粗、圆角
        self.btn_style_active = "background-color: #007BFF; color: white; padding: 8px; font-weight: bold; border-radius: 5px;"
        # 定义按钮非激活样式：灰色背景、黑色文字、圆角
        self.btn_style_inactive = "background-color: #E0E0E0; color: black; padding: 8px; border-radius: 5px;"
        # 为车库按钮单独设置样式（蓝绿色背景）
        self.btn_garage_status.setStyleSheet(
            "background-color: #17A2B8; color: white; padding: 8px; border-radius: 5px;")

        # 初始状态：托举式按钮为激活，叉车式按钮为非激活
        self.btn_lifting.setStyleSheet(self.btn_style_active)
        self.btn_forklift.setStyleSheet(self.btn_style_inactive)

        # 绑定按钮点击事件：托举式点击时切换到类型 1，叉车式点击时切换到类型 2
        self.btn_lifting.clicked.connect(lambda: self.switch_type(1))
        self.btn_forklift.clicked.connect(lambda: self.switch_type(2))
        # 车库按钮点击时调用 show_garage_status 方法
        self.btn_garage_status.clicked.connect(self.show_garage_status)

        # 将三个按钮添加到顶部水平布局
        top_layout.addWidget(self.btn_lifting)
        top_layout.addWidget(self.btn_forklift)
        top_layout.addWidget(self.btn_garage_status)
        top_layout.addStretch()  # 添加伸缩因子，使按钮靠左对齐
        main_layout.addLayout(top_layout)  # 将顶部布局添加到主布局

        # ==================== 2. 中间：数据表格 ====================
        self.table = QTableWidget()  # 创建表格控件
        self.table.setColumnCount(9)  # 设置表格列数为 9
        # 设置表格列标题
        self.table.setHorizontalHeaderLabels(
            ["AGV 编号", "设备自重(kg)", "初始位置", "速度(m/s)", "满电量(%)", "当前状态", "空载耗电", "负载耗电","设备类型"])
        # 设置列宽自适应：均匀拉伸填满表格
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        # 设置选择行为：选中整行
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        # 设置编辑触发器：禁止编辑表格内容
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        # 绑定表格选中项变化事件到 on_table_select 方法
        self.table.itemSelectionChanged.connect(self.on_table_select)
        main_layout.addWidget(self.table)  # 将表格添加到主布局

        # ==================== 3. 底部：增删改查表单 ====================
        form_group = QFrame()  # 创建一个 QFrame 作为表单容器
        # 设置框架样式：灰色边框、圆角、内边距
        form_group.setStyleSheet("QFrame { border: 1px solid #ccc; border-radius: 5px; padding: 5px; }")
        form_layout = QGridLayout(form_group)  # 为框架创建网格布局

        # 创建各种输入控件
        self.id_input = QLineEdit()  # AGV 编号输入框
        self.id_input.setPlaceholderText("例如: AGV-01")  # 设置占位符提示
        self.ip_input = QLineEdit()  # 设备自重输入框（实际用于 ip_address 字段，但标签是设备自重）
        self.ip_input.setPlaceholderText("例如: 40kg")  # 占位符提示
        self.pos_input = QComboBox()  # 初始车库下拉框
        self.battery_input = QSpinBox()  # 当前电量数字输入框
        self.battery_input.setRange(0, 100)  # 设置范围 0-100
        self.status_input = QComboBox()  # 当前状态下拉框
        self.status_input.addItems(["空闲", "任务中", "充电中", "故障", "离线"])  # 添加选项
        self.speed_input = QDoubleSpinBox()  # 运行速度浮点数输入框
        self.speed_input.setRange(0.1, 10.0)  # 设置范围
        self.speed_input.setDecimals(1)  # 设置小数位数 1 位
        self.speed_input.setSingleStep(0.1)  # 设置步长
        self.e_base_input = QDoubleSpinBox()  # 空载耗电系数输入框
        self.e_base_input.setRange(0.000, 1.000)  # 范围
        self.e_base_input.setDecimals(3)  # 3 位小数
        self.e_base_input.setSingleStep(0.01)  # 步长
        self.e_load_input = QDoubleSpinBox()  # 负载耗电系数输入框
        self.e_load_input.setRange(0.000, 1.000)
        self.e_load_input.setDecimals(3)
        self.e_load_input.setSingleStep(0.01)

        # 第一行：AGV 编号、设备自重、初始车库
        form_layout.addWidget(QLabel("AGV 编号:"), 0, 0)  # 标签 (行0,列0)
        form_layout.addWidget(self.id_input, 0, 1)        # 输入框 (行0,列1)
        form_layout.addWidget(QLabel("设备自重:"), 0, 2)  # 标签 (行0,列2)
        form_layout.addWidget(self.ip_input, 0, 3)        # 输入框 (行0,列3)
        form_layout.addWidget(QLabel("初始车库:"), 0, 4)  # 标签 (行0,列4)
        form_layout.addWidget(self.pos_input, 0, 5)       # 下拉框 (行0,列5)

        # 第二行：当前电量、当前状态、运行速度
        form_layout.addWidget(QLabel("当前电量:"), 1, 0)
        form_layout.addWidget(self.battery_input, 1, 1)
        form_layout.addWidget(QLabel("当前状态:"), 1, 2)
        form_layout.addWidget(self.status_input, 1, 3)
        form_layout.addWidget(QLabel("运行速度(m/s):"), 1, 4)
        form_layout.addWidget(self.speed_input, 1, 5)

        # 第三行：空载耗电系数、负载耗电系数
        form_layout.addWidget(QLabel("空载耗电系数:"), 2, 0)
        form_layout.addWidget(self.e_base_input, 2, 1)
        form_layout.addWidget(QLabel("负载耗电系数:"), 2, 2)
        form_layout.addWidget(self.e_load_input, 2, 3)

        main_layout.addWidget(form_group)  # 将表单框架添加到主布局

        # ==================== 4. 操作按钮 ====================
        action_layout = QHBoxLayout()  # 创建水平布局放置按钮
        self.btn_add = QPushButton("➕ 新增设备")   # 新增按钮
        self.btn_update = QPushButton("💾 保存修改") # 修改按钮
        self.btn_delete = QPushButton("🗑️ 删除选中") # 删除按钮

        # 设置按钮样式：新增绿色、修改橙色、删除红色
        self.btn_add.setStyleSheet("background-color: #4CAF50; color: white; padding: 6px; border-radius: 4px;")
        self.btn_update.setStyleSheet("background-color: #FF9800; color: white; padding: 6px; border-radius: 4px;")
        self.btn_delete.setStyleSheet("background-color: #F44336; color: white; padding: 6px; border-radius: 4px;")

        # 绑定按钮点击事件到对应方法
        self.btn_add.clicked.connect(self.add_agv)
        self.btn_update.clicked.connect(self.update_agv)
        self.btn_delete.clicked.connect(self.delete_agv)

        # 将三个按钮添加到水平布局
        action_layout.addWidget(self.btn_add)
        action_layout.addWidget(self.btn_update)
        action_layout.addWidget(self.btn_delete)
        main_layout.addLayout(action_layout)  # 将按钮布局添加到主布局

        self.clear_inputs()  # 清空输入框，设置为默认值

    def safe_request(self, method, endpoint, **kwargs):
        """统一的网络请求异常拦截器：发送 HTTP 请求，捕获异常并提示"""
        try:
            url = f"{self.api_base_url}{endpoint}"  # 拼接完整的 URL
            res = requests.request(method, url, timeout=3, **kwargs)  # 发送请求，超时 3 秒
            return res.json()  # 返回解析后的 JSON 数据
        except Exception as e:
            # 如果发生任何异常（网络不通、超时、JSON 解析错误等），弹出错误对话框
            QMessageBox.critical(self, "网络异常", f"无法连接到后端服务器，请检查 API 是否开启！\n{e}")
            return None  # 返回 None

    def load_data(self):
        """[GET] 从 API 拉取表格数据，根据当前 AGV 类型刷新表格"""
        # 发送 GET 请求到 /list 端点，附带类型参数
        data = self.safe_request("GET", f"/list?type={self.current_agv_type}")
        if not data:  # 如果请求失败或返回 None，直接返回
            return

        devices = data.get("data", [])  # 从响应中获取设备列表，默认为空列表
        self.table.setRowCount(len(devices))  # 设置表格行数

        # 遍历设备列表，填充表格每一行
        for row, dev in enumerate(devices):
            # 根据设备类型确定显示文字
            type_str = "托举式" if dev['agv_type'] == 1 else "叉车"
            # 格式化初始位置显示
            garage_str = f"车库 {dev['initial_position']}" if dev['initial_position'] else "未分配"

            # 设置每一列的单元格内容
            self.table.setItem(row, 0, QTableWidgetItem(str(dev['agv_id'])))          # AGV 编号
            self.table.setItem(row, 1, QTableWidgetItem(str(dev['ip_address'])))      # 设备自重（ip_address 字段）
            self.table.setItem(row, 2, QTableWidgetItem(garage_str))                  # 初始位置
            self.table.setItem(row, 3, QTableWidgetItem(str(dev['speed'])))           # 速度
            self.table.setItem(row, 4, QTableWidgetItem(str(dev['battery'])))         # 电量
            self.table.setItem(row, 5, QTableWidgetItem(str(dev['status'])))          # 状态
            self.table.setItem(row, 6, QTableWidgetItem(str(dev['e_base'])))          # 空载耗电
            self.table.setItem(row, 7, QTableWidgetItem(str(dev['e_load_factor'])))   # 负载耗电
            self.table.setItem(row, 8, QTableWidgetItem(type_str))                    # 设备类型

    def update_garage_combobox(self, current_pos=None):
        """[GET] 从 API 拉取车库占用情况，刷新下拉列表，可选当前已占用的车库位置"""
        self.pos_input.clear()  # 清空下拉框所有选项
        # 根据当前 AGV 类型确定车库总数：托举式 8 个，叉车式 9 个
        total_garages = 8 if self.current_agv_type == 1 else 9

        # 发送 GET 请求获取车库占用信息
        data = self.safe_request("GET", "/garages")
        occupied = []  # 用于存储已被占用的车库编号
        if data and data.get("status") == "success":
            # 从响应中提取与当前类型相同且已分配的车库编号
            occupied = [r['initial_position'] for r in data['data']
                        if r['agv_type'] == self.current_agv_type and r['initial_position']]

        # 遍历所有车库编号
        for i in range(1, total_garages + 1):
            # 如果该车库未被占用，或者它是当前设备正在使用的车库（编辑时允许保留当前车库）
            if (i not in occupied) or (i == current_pos):
                self.pos_input.addItem(f"车库 {i}", i)  # 添加选项，显示文本为"车库 i"，用户数据为 i

        # 如果没有空闲车库，添加一个提示选项
        if self.pos_input.count() == 0:
            self.pos_input.addItem("暂无空闲车库", -1)

    def show_garage_status(self):
        """[GET] 从 API 拉取全量占用数据并弹窗显示（HTML 格式）"""
        data = self.safe_request("GET", "/garages")  # 请求车库数据
        if not data:  # 如果请求失败，返回
            return

        # 初始化两个字典，存储每个车库的占用状态 HTML 字符串，默认空闲（绿色）
        lift_garages = {i: "<span style='color: #28A745;'>🟢 空闲</span>" for i in range(1, 9)}
        fork_garages = {i: "<span style='color: #28A745;'>🟢 空闲</span>" for i in range(1, 10)}

        # 遍历 API 返回的数据，将已被占用的车库状态更新为已占用（红色）
        for r in data.get("data", []):
            pos = r['initial_position']
            occupied_text = f"<span style='color: #DC3545;'>🔴 已占用 ({r['agv_id']})</span>"
            if r['agv_type'] == 1 and pos in lift_garages:
                lift_garages[pos] = occupied_text
            elif r['agv_type'] == 2 and pos in fork_garages:
                fork_garages[pos] = occupied_text

        # 构建完整的 HTML 内容
        html_content = "<h2>全系统车库实时监控</h2>"
        html_content += "<h3 style='color: #007BFF;'>📦 托举式 AGV 车库 (共 8 个)</h3><div style='font-size: 14px;'>"
        for i in range(1, 9): html_content += f"<b>车库 {i}</b>: {lift_garages[i]}<br>"
        html_content += "</div><h3 style='color: #007BFF;'>🚜 叉车式 AGV 车库 (共 9 个)</h3><div style='font-size: 14px;'>"
        for i in range(1, 10): html_content += f"<b>车库 {i}</b>: {fork_garages[i]}<br>"
        html_content += "</div>"

        # 创建并显示自定义 QMessageBox，设置最小宽度以容纳 HTML
        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("🅿️ 车库占用情况")
        msg_box.setText(html_content)
        msg_box.setStyleSheet("QLabel { min-width: 500px; }")
        msg_box.exec_()

    def add_agv(self):
        """[POST] 提交新增请求给 API"""
        agv_id = self.id_input.text().strip()  # 获取输入的 AGV 编号，去除首尾空格
        pos = self.pos_input.currentData()      # 获取下拉框选中的车库编号（用户数据）

        # 输入校验
        if not agv_id:
            QMessageBox.warning(self, "提示", "请输入 AGV 编号！")
            return
        if pos is None or pos == -1:
            QMessageBox.warning(self, "提示", "当前没有空闲车库可分配！")
            return

        # 构造要发送的 JSON 数据
        payload = {
            "agv_id": agv_id,
            "agv_type": self.current_agv_type,
            "ip_address": self.ip_input.text().strip(),  # 设备自重
            "initial_position": pos,
            "battery": self.battery_input.value(),
            "status": self.status_input.currentText(),
            "speed": self.speed_input.value(),
            "e_base": self.e_base_input.value(),
            "e_load_factor": self.e_load_input.value()
        }

        # 发送 POST 请求到 /add 端点
        data = self.safe_request("POST", "/add", json=payload)
        if data:
            if data.get("status") == "success":
                QMessageBox.information(self, "成功", "AGV设备添加成功！配置已自动同步给底层。")
                self.load_data()      # 重新加载表格数据
                self.clear_inputs()   # 清空输入框
            else:
                QMessageBox.warning(self, "错误", data.get("msg", "添加失败"))

    def update_agv(self):
        """[PUT] 提交修改请求给 API"""
        agv_id = self.id_input.text().strip()  # 获取当前输入的 AGV 编号
        pos = self.pos_input.currentData()

        if not agv_id:
            return QMessageBox.warning(self, "提示", "请先在表格中选择要修改的设备！")
        if pos is None or pos == -1:
            return QMessageBox.warning(self, "提示", "请选择有效的初始车库！")

        # 构造更新数据（不包括 agv_type，因为类型不可变）
        payload = {
            "agv_id": agv_id,
            "ip_address": self.ip_input.text().strip(),
            "initial_position": pos,
            "battery": self.battery_input.value(),
            "status": self.status_input.currentText(),
            "speed": self.speed_input.value(),
            "e_base": self.e_base_input.value(),
            "e_load_factor": self.e_load_input.value()
        }

        # 发送 PUT 请求到 /update 端点
        data = self.safe_request("PUT", "/update", json=payload)
        if data and data.get("status") == "success":
            QMessageBox.information(self, "成功", "AGV设备信息更新成功！配置已自动同步给底层。")
            self.load_data()

    def delete_agv(self):
        """[DELETE] 发送删除指令给 API"""
        selected_rows = self.table.selectedItems()  # 获取表格中选中的项
        if not selected_rows:
            return QMessageBox.warning(self, "提示", "请先在表格中选中要删除的设备！")

        # 获取选中行第一列（AGV 编号）的文本
        agv_id = self.table.item(selected_rows[0].row(), 0).text()
        # 弹出确认对话框
        if QMessageBox.question(self, '确认', f"确定要删除设备 [{agv_id}] 吗？",
                                QMessageBox.Yes | QMessageBox.No) == QMessageBox.Yes:
            # 发送 DELETE 请求到 /delete/{agv_id}
            data = self.safe_request("DELETE", f"/delete/{agv_id}")
            if data and data.get("status") == "success":
                QMessageBox.information(self, "成功", "设备已删除。")
                self.load_data()      # 重新加载表格
                self.clear_inputs()   # 清空输入框

    # --- 本地 UI 辅助控制函数（不涉及网络请求）---
    def switch_type(self, agv_type):
        """切换 AGV 类型并刷新界面"""
        self.current_agv_type = agv_type
        if agv_type == 1:
            self.btn_lifting.setStyleSheet(self.btn_style_active)
            self.btn_forklift.setStyleSheet(self.btn_style_inactive)
        else:
            self.btn_lifting.setStyleSheet(self.btn_style_inactive)
            self.btn_forklift.setStyleSheet(self.btn_style_active)
        self.clear_inputs()  # 清空输入框
        self.load_data()     # 重新加载对应类型的数据

    def on_table_select(self):
        """当表格中选中行变化时，将选中行的数据填充到表单中"""
        selected_rows = self.table.selectedItems()
        if selected_rows:
            row = selected_rows[0].row()  # 获取选中行的行索引
            # 从表格中读取各列数据，并设置到对应的输入控件
            self.id_input.setText(self.table.item(row, 0).text())                # AGV 编号
            self.ip_input.setText(self.table.item(row, 1).text())                # 设备自重

            pos_text = self.table.item(row, 2).text()                            # 初始位置文本
            current_pos = int(pos_text.replace("车库 ", "")) if "车库" in pos_text else None  # 提取车库编号
            self.update_garage_combobox(current_pos)                             # 更新下拉框，并选中当前车库
            self.pos_input.setCurrentText(pos_text)                              # 设置下拉框显示文本

            self.speed_input.setValue(float(self.table.item(row, 3).text()))     # 速度
            self.battery_input.setValue(int(self.table.item(row, 4).text()))     # 电量
            self.status_input.setCurrentText(self.table.item(row, 5).text())     # 状态
            self.e_base_input.setValue(float(self.table.item(row, 6).text()))    # 空载耗电
            self.e_load_input.setValue(float(self.table.item(row, 7).text()))    # 负载耗电
            self.id_input.setReadOnly(True)  # 编号设为只读，防止修改（因为编号是主键）
        else:
            self.clear_inputs()  # 如果没有选中行，清空输入框

    def clear_inputs(self):
        """清空所有输入控件，恢复默认值，并使编号可编辑"""
        self.id_input.clear()               # 清空编号输入框
        self.id_input.setReadOnly(False)    # 允许编辑编号
        self.ip_input.clear()                # 清空自重输入框
        self.battery_input.setValue(100)     # 电量默认 100%
        self.status_input.setCurrentIndex(0) # 状态默认选择第一项（空闲）
        self.update_garage_combobox()        # 更新车库下拉框（显示当前空闲车库）

        # 根据当前 AGV 类型设置默认的速度和耗电系数
        if self.current_agv_type == 1:
            self.speed_input.setValue(3.0)   # 托举式默认速度 3.0
            self.e_base_input.setValue(0.02) # 空载耗电默认 0.02
            self.e_load_input.setValue(0.02) # 负载耗电默认 0.02
        else:
            self.speed_input.setValue(2.0)   # 叉车式默认速度 2.0
            self.e_base_input.setValue(0.04) # 空载耗电默认 0.04
            self.e_load_input.setValue(0.03) # 负载耗电默认 0.03