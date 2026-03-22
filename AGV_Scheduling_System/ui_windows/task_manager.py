import requests
from PyQt5.QtWidgets import (QWidget, QLabel, QPushButton, QVBoxLayout, QHBoxLayout, QMessageBox,
                             QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QSpinBox)


class TaskManagerWindow(QDialog):
    """纯 API 驱动的任务管理窗口 (MES 订单池)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("任务管理 (MES 订单池)")
        self.resize(1700, 800)

        # 定义后端 API 的基础 URL
        self.api_base_url = "http://127.0.0.1:5000/api/tasks"
        self.current_task_view = 0  # 0: 待分配/执行中, 2: 已完成

        self.initUI()
        self.load_data()

    def initUI(self):
        """UI布局代码保持不变，负责渲染界面"""
        main_layout = QVBoxLayout(self)

        # ==================== 1. 顶部：状态切换按钮 ====================
        top_layout = QHBoxLayout()
        self.btn_active_tasks = QPushButton("⏳ 待分配 任务")
        self.btn_completed_tasks = QPushButton("✅ 已完成历史任务")

        self.btn_style_active = "background-color: #007BFF; color: white; padding: 8px; font-weight: bold; border-radius: 5px;"
        self.btn_style_inactive = "background-color: #E0E0E0; color: black; padding: 8px; border-radius: 5px;"
        self.btn_active_tasks.setStyleSheet(self.btn_style_active)
        self.btn_completed_tasks.setStyleSheet(self.btn_style_inactive)

        self.btn_active_tasks.clicked.connect(lambda: self.switch_view(0))
        self.btn_completed_tasks.clicked.connect(lambda: self.switch_view(2))

        top_layout.addWidget(self.btn_active_tasks)
        top_layout.addWidget(self.btn_completed_tasks)
        top_layout.addStretch()
        main_layout.addLayout(top_layout)

        # ==================== 2. 中间：数据表格 ====================
        self.table = QTableWidget()
        self.table.setColumnCount(10)
        self.table.setHorizontalHeaderLabels([
            "订单ID", "目标工位", "货物类型", "重量", "截止时间",
            "执行状态", "执行 AGV", "耗时(秒)", "路程(格)", "下发时间"
        ])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Interactive)
        self.table.setColumnWidth(0, 60)
        self.table.setColumnWidth(2, 100)
        self.table.setColumnWidth(9, 160)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        main_layout.addWidget(self.table)

        # ==================== 3. 底部：操作区域 ====================
        self.form_widget = QWidget()
        form_layout = QHBoxLayout(self.form_widget)
        form_layout.setContentsMargins(0, 10, 0, 0)

        form_layout.addWidget(QLabel("目标工位(1-16):"))
        self.station_input = QSpinBox()
        self.station_input.setRange(1, 16)
        form_layout.addWidget(self.station_input)

        form_layout.addWidget(QLabel("重量:"))
        self.weight_input = QSpinBox()
        self.weight_input.setRange(1, 300)
        form_layout.addWidget(self.weight_input)

        form_layout.addWidget(QLabel("截止时间:"))
        self.deadline_input = QSpinBox()
        self.deadline_input.setRange(100, 10000)
        self.deadline_input.setValue(300)
        self.deadline_input.setSingleStep(50)
        form_layout.addWidget(self.deadline_input)

        self.add_btn = QPushButton("新增任务")
        self.add_btn.setStyleSheet("background-color: #4CAF50; color: white; padding: 6px; border-radius: 4px;")
        self.add_btn.clicked.connect(self.add_task)
        form_layout.addWidget(self.add_btn)

        self.del_btn = QPushButton("删除选中任务")
        self.del_btn.setStyleSheet("background-color: #F44336; color: white; padding: 6px; border-radius: 4px;")
        self.del_btn.clicked.connect(self.delete_task)
        form_layout.addWidget(self.del_btn)

        self.restore_btn = QPushButton("一键复原")
        self.restore_btn.setStyleSheet("background-color: #17A2B8; color: white; padding: 6px; border-radius: 4px; ")
        self.restore_btn.clicked.connect(self.restore_all_completed)
        form_layout.addWidget(self.restore_btn)

        main_layout.addWidget(self.form_widget)

    # ============================================================================
    # 核心改造：纯 API 网络请求方法
    # ============================================================================

    def safe_request(self, method, endpoint, **kwargs):
        """统一的网络请求异常拦截器"""
        try:
            url = f"{self.api_base_url}{endpoint}"
            res = requests.request(method, url, timeout=3, **kwargs)
            return res.json()
        except requests.exceptions.RequestException as e:
            QMessageBox.critical(self, "网络异常", f"无法连接到后端服务器，请检查 API 是否开启！\n{e}")
            return None

    def switch_view(self, view_type):
        """切换视图并刷新样式"""
        self.current_task_view = view_type
        if view_type == 0:
            self.btn_active_tasks.setStyleSheet(self.btn_style_active)
            self.btn_completed_tasks.setStyleSheet(self.btn_style_inactive)
        else:
            self.btn_active_tasks.setStyleSheet(self.btn_style_inactive)
            self.btn_completed_tasks.setStyleSheet(self.btn_style_active)
        self.load_data()

    def load_data(self):
        """[GET] 从 API 根据当前视图加载任务数据"""
        self.table.setRowCount(0)
        data = self.safe_request("GET", f"/list?view_type={self.current_task_view}")

        if not data or not data.get("data"):
            return

        orders = data["data"]
        self.table.setRowCount(len(orders))

        for row_idx, order in enumerate(orders):
            status_map = {0: "待分配", 1: "执行中", 2: "已完成"}
            status_str = status_map.get(order['status'], "未知")
            type_str = "小型配件" if order['item_type'] == 1 else "大型配件"
            create_time = str(order['create_time']) if order.get('create_time') else ""

            executor = str(order['executor_agv']) if order.get('executor_agv') else "-"
            duration = f"{order['actual_time']:.1f}" if order.get('actual_time') is not None else "-"
            distance = str(order['actual_distance']) if order.get('actual_distance') is not None else "-"

            self.table.setItem(row_idx, 0, QTableWidgetItem(str(order['order_id'])))
            self.table.setItem(row_idx, 1, QTableWidgetItem(str(order['target_station'])))
            self.table.setItem(row_idx, 2, QTableWidgetItem(type_str))
            self.table.setItem(row_idx, 3, QTableWidgetItem(str(order['weight'])))
            self.table.setItem(row_idx, 4, QTableWidgetItem(str(order['deadline'])))
            self.table.setItem(row_idx, 5, QTableWidgetItem(status_str))
            self.table.setItem(row_idx, 6, QTableWidgetItem(executor))
            self.table.setItem(row_idx, 7, QTableWidgetItem(duration))
            self.table.setItem(row_idx, 8, QTableWidgetItem(distance))
            self.table.setItem(row_idx, 9, QTableWidgetItem(create_time))

    def add_task(self):
        """[POST] 向 API 发送新增任务请求"""
        station = self.station_input.value()
        weight = self.weight_input.value()
        deadline = self.deadline_input.value()
        item_type = 1 if station <= 12 else 2

        payload = {
            "station": station,
            "weight": weight,
            "deadline": deadline,
            "item_type": item_type
        }

        res = self.safe_request("POST", "/add", json=payload)

        if res and res.get("status") == "success":
            QMessageBox.information(self, "成功", "任务添加成功！")
            if self.current_task_view != 0:
                self.switch_view(0)
            else:
                self.load_data()
        else:
            QMessageBox.warning(self, "错误", res.get("msg", "任务添加失败！") if res else "请求无响应")

    def delete_task(self):
        """[DELETE] 向 API 发送删除指定任务请求"""
        selected_rows = self.table.selectedItems()
        if not selected_rows:
            QMessageBox.warning(self, "提示", "请先在表格中选中要删除的任务！")
            return

        row = selected_rows[0].row()
        order_id = self.table.item(row, 0).text()
        status_str = self.table.item(row, 5).text()

        if status_str == "执行中":
            QMessageBox.warning(self, "警告", "该任务正在执行中，无法删除！")
            return

        warn_text = f"确定要彻底删除该历史订单(ID: {order_id})吗？" if status_str == "已完成" else f"确定要删除尚未执行的订单(ID: {order_id})吗？"
        reply = QMessageBox.question(self, '确认删除', warn_text, QMessageBox.Yes | QMessageBox.No, QMessageBox.No)

        if reply == QMessageBox.Yes:
            res = self.safe_request("DELETE", f"/delete/{order_id}")
            if res and res.get("status") == "success":
                self.load_data()
                QMessageBox.information(self, "成功", "任务已删除。")

    def restore_all_completed(self):
        """[POST] 通知 API 一键复原所有历史任务"""
        reply = QMessageBox.question(self, '确认复原',
                                     "确定要将所有【已完成】的历史任务重新恢复为【待分配】状态吗？\n",
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)

        if reply == QMessageBox.Yes:
            res = self.safe_request("POST", "/restore")
            if res:
                if res.get("status") == "success":
                    QMessageBox.information(self, "成功", f"成功复原了 {res.get('rows')} 条任务！")
                    if self.current_task_view != 0:
                        self.switch_view(0)
                    else:
                        self.load_data()
                else:
                    QMessageBox.information(self, "提示", res.get("msg", "复原操作未执行。"))