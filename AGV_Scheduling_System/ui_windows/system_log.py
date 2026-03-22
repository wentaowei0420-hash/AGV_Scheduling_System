import requests
from PyQt5.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QLabel, QTabWidget, QWidget, QPushButton, QTableWidget, \
    QTableWidgetItem, QHeaderView, QMessageBox, QListWidget, QListWidgetItem, QSplitter, QTextEdit
from PyQt5.QtGui import QFont, QColor
from PyQt5.QtCore import Qt


class SystemLogWindow(QDialog):
    """纯 API 驱动的系统事件与日志中心窗口"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("系统事件与日志中心")
        self.resize(950, 650)
        self.api_base_url = "http://127.0.0.1:5000/api/logs"
        self.initUI()

        # 启动时通知后端解析报文，然后拉取通信日志
        self.load_logs()

    # ============================================================================
    # 统一的网络请求方法
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

    def initUI(self):
        self.setStyleSheet("QDialog { background-color: #F4F6F9; }")
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(20, 20, 20, 20)

        header_label = QLabel("📋 系统事件与日志中心")
        header_label.setFont(QFont("Microsoft YaHei", 16, QFont.Bold))
        header_label.setStyleSheet("color: #2C3E50; margin-bottom: 10px;")
        main_layout.addWidget(header_label)

        self.tabs = QTabWidget()
        self.tabs.setFont(QFont("Microsoft YaHei", 11))
        self.tabs.setStyleSheet("""
            QTabWidget::pane { border: 1px solid #E0E4E8; background: #FFFFFF; border-radius: 8px; }
            QTabBar::tab { background: #E2E6EA; color: #495057; padding: 10px 20px; margin-right: 2px; border-top-left-radius: 6px; border-top-right-radius: 6px; }
            QTabBar::tab:selected { background: #FFFFFF; color: #007BFF; font-weight: bold; border: 1px solid #E0E4E8; border-bottom-color: #FFFFFF; }
            QTabBar::tab:hover:!selected { background: #D6DCE1; }
        """)

        self.tab_comm_log = QWidget()
        self.tab_event_handle = QWidget()
        self.tab_code_log = QWidget()

        self.tabs.addTab(self.tab_comm_log, "📡 通信交互日志 (MES/AGV)")
        self.tabs.addTab(self.tab_event_handle, "⚠️ 设备事件处理")
        self.tabs.addTab(self.tab_code_log, "📝 代码运行日志")

        self.setup_comm_log_tab()
        self.setup_event_handle_tab()
        self.setup_code_log_tab()
        main_layout.addWidget(self.tabs)

        bottom_layout = QHBoxLayout()
        bottom_layout.addStretch()
        self.btn_return = QPushButton("关闭日志中心")
        self.btn_return.setStyleSheet("""
            QPushButton { background-color: #6C757D; color: white; padding: 10px 30px; border-radius: 6px; font-weight: bold; font-size: 14px;}
            QPushButton:hover { background-color: #5A6268; }
        """)
        self.btn_return.clicked.connect(self.close)
        bottom_layout.addWidget(self.btn_return)
        main_layout.addLayout(bottom_layout)

    # =========================================================================
    # 第一页：通信交互日志 (API 重构)
    # =========================================================================
    def setup_comm_log_tab(self):
        layout = QVBoxLayout(self.tab_comm_log)
        layout.setContentsMargins(15, 15, 15, 15)

        tool_layout = QHBoxLayout()
        self.btn_refresh_comm = QPushButton("🔄 刷新日志")
        self.btn_clear_comm = QPushButton("🗑️ 清空日志")
        self.btn_export_comm = QPushButton("📤 导出为 Excel")

        btn_style = "padding: 6px 15px; border-radius: 4px; border: 1px solid #ccc; background-color: #fff; font-weight:bold;"
        self.btn_refresh_comm.setStyleSheet(btn_style)
        self.btn_clear_comm.setStyleSheet(btn_style)
        self.btn_export_comm.setStyleSheet(btn_style)

        self.btn_refresh_comm.clicked.connect(self.load_logs)
        self.btn_clear_comm.clicked.connect(self.clear_logs)

        tool_layout.addWidget(self.btn_refresh_comm)
        tool_layout.addWidget(self.btn_clear_comm)
        tool_layout.addWidget(self.btn_export_comm)
        tool_layout.addStretch()
        layout.addLayout(tool_layout)

        self.comm_table = QTableWidget()
        self.comm_table.setColumnCount(5)
        self.comm_table.setHorizontalHeaderLabels(["时间", "通信节点 (源->目的)", "命令类型", "数据内容摘要", "状态"])
        self.comm_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.comm_table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.comm_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.comm_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.comm_table.setStyleSheet(
            "QTableWidget { background-color: white; border: 1px solid #ccc; border-radius: 5px; }")
        layout.addWidget(self.comm_table)

    def load_logs(self):
        """[GET] 从后台读取通信日志"""
        res = self.safe_request("GET", "/comm/list")
        self.comm_table.setRowCount(0)

        if not res or not res.get("data"): return

        logs = res["data"]
        self.comm_table.setRowCount(len(logs))
        for row_idx, row in enumerate(logs):
            time_str = str(row['log_time']).split('.')[0]
            self.comm_table.setItem(row_idx, 0, QTableWidgetItem(time_str))
            self.comm_table.setItem(row_idx, 1, QTableWidgetItem(row['node_path']))
            self.comm_table.setItem(row_idx, 2, QTableWidgetItem(row['msg_type']))
            self.comm_table.setItem(row_idx, 3, QTableWidgetItem(row['content']))

            item_status = QTableWidgetItem(row['status'])
            item_status.setForeground(QColor(40, 167, 69))
            self.comm_table.setItem(row_idx, 4, item_status)

    def clear_logs(self):
        """[DELETE] 请求后端清空表"""
        if QMessageBox.question(self, '确认', "确定要清空所有通信交互日志吗？",
                                QMessageBox.Yes | QMessageBox.No) == QMessageBox.Yes:
            res = self.safe_request("DELETE", "/comm/clear")
            if res and res.get("status") == "success":
                self.load_logs()
            else:
                QMessageBox.warning(self, "错误", res.get("msg", "清空日志失败") if res else "无响应")

    # =========================================================================
    # 第三页：代码运行日志 (API 重构)
    # =========================================================================
    def setup_code_log_tab(self):
        layout = QHBoxLayout(self.tab_code_log)
        layout.setContentsMargins(15, 15, 15, 15)
        splitter = QSplitter(Qt.Horizontal)

        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        list_title = QLabel("🕒 历史运行记录")
        list_title.setFont(QFont("Microsoft YaHei", 10, QFont.Bold))
        left_layout.addWidget(list_title)

        self.history_list = QListWidget()
        self.history_list.setStyleSheet("""
            QListWidget { border: 1px solid #ccc; border-radius: 5px; background: white; font-size: 13px;}
            QListWidget::item { padding: 8px; border-bottom: 1px solid #f0f0f0; }
            QListWidget::item:selected { background-color: #007BFF; color: white; font-weight: bold;}
        """)
        self.history_list.itemClicked.connect(self.load_log_content)
        left_layout.addWidget(self.history_list)
        splitter.addWidget(left_widget)

        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        detail_title = QLabel("📃 日志详细内容")
        detail_title.setFont(QFont("Microsoft YaHei", 10, QFont.Bold))
        right_layout.addWidget(detail_title)

        self.log_content_display = QTextEdit()
        self.log_content_display.setReadOnly(True)
        self.log_content_display.setStyleSheet("""
            QTextEdit { background-color: #1E1E1E; color: #A9B7C6; border: 1px solid #3C3F41; border-radius: 5px; 
                        font-family: Consolas, "Microsoft YaHei"; font-size: 13px; padding: 10px; }
        """)
        right_layout.addWidget(self.log_content_display)
        splitter.addWidget(right_widget)

        splitter.setSizes([200, 800])
        layout.addWidget(splitter)
        self.load_history_list()

    def load_history_list(self):
        """[GET] 获取左侧时间列表"""
        self.history_list.clear()
        res = self.safe_request("GET", "/code/history")

        if res and res.get("data"):
            for row in res["data"]:
                item = QListWidgetItem(f"运行于: {row['run_time']}")
                item.setData(Qt.UserRole, row['id'])
                self.history_list.addItem(item)
        else:
            self.history_list.addItem(QListWidgetItem("暂无运行记录"))

    def load_log_content(self, item):
        """[GET] 点击列表时获取右侧详情"""
        log_id = item.data(Qt.UserRole)
        if not log_id: return

        res = self.safe_request("GET", f"/code/detail/{log_id}")
        if res and res.get("status") == "success":
            self.log_content_display.setPlainText(res.get("data"))
        else:
            self.log_content_display.setPlainText(res.get("msg", "读取日志失败") if res else "无响应")

        # =========================================================================
        # 第二页：路径冲突监控看板 (API 重构)
        # =========================================================================
    def setup_event_handle_tab(self):
            layout = QVBoxLayout(self.tab_event_handle)
            layout.setContentsMargins(15, 15, 15, 15)

            # 顶部操作按钮区 (替换掉原来的 处理/忽略 按钮)
            tool_layout = QHBoxLayout()
            self.btn_refresh_conflict = QPushButton("🔄 刷新冲突记录")
            self.btn_clear_conflict = QPushButton("🗑️ 清空冲突记录")

            btn_style = "padding: 6px 15px; border-radius: 4px; border: 1px solid #ccc; background-color: #fff; font-weight:bold;"
            self.btn_refresh_conflict.setStyleSheet(btn_style)
            self.btn_clear_conflict.setStyleSheet(btn_style)

            self.btn_refresh_conflict.clicked.connect(self.load_conflict_events)
            self.btn_clear_conflict.clicked.connect(self.clear_conflict_events)

            tool_layout.addWidget(self.btn_refresh_conflict)
            tool_layout.addWidget(self.btn_clear_conflict)
            tool_layout.addStretch()
            layout.addLayout(tool_layout)

            # 冲突日志数据表格
            self.event_table = QTableWidget()
            self.event_table.setColumnCount(6)
            # 根据数据库字段重新设定表头
            self.event_table.setHorizontalHeaderLabels(
                ["记录时间", "仿真步数(T)", "主动方 (AGV-X)", "被动方 (AGV-Y)", "冲突类型", "发生坐标"])
            self.event_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
            self.event_table.setSelectionBehavior(QTableWidget.SelectRows)
            self.event_table.setEditTriggers(QTableWidget.NoEditTriggers)
            self.event_table.setStyleSheet(
                "QTableWidget { background-color: white; border: 1px solid #ccc; border-radius: 5px; }")
            layout.addWidget(self.event_table)

            # 初始化加载数据
            self.load_conflict_events()

    def load_conflict_events(self):
            """[GET] 从后台加载真实的冲突日志"""
            res = self.safe_request("GET", "/conflict/list")
            self.event_table.setRowCount(0)

            if not res or not res.get("data"):
                return

            events = res["data"]
            self.event_table.setRowCount(len(events))

            for row_idx, row in enumerate(events):
                # 格式化数据
                time_str = str(row['report_time']).split('.')[0]
                step_str = f"T={row['sim_step']}"
                agv1_str = f"AGV-{row['agv1_id']:02d}"
                agv2_str = f"AGV-{row['agv2_id']:02d}"
                type_str = row['conflict_type']
                # 将双方坐标拼在一起直观展示
                pos_str = f"A:{row['agv1_pos']} ⚡ B:{row['agv2_pos']}"

                self.event_table.setItem(row_idx, 0, QTableWidgetItem(time_str))
                self.event_table.setItem(row_idx, 1, QTableWidgetItem(step_str))
                self.event_table.setItem(row_idx, 2, QTableWidgetItem(agv1_str))
                self.event_table.setItem(row_idx, 3, QTableWidgetItem(agv2_str))
                self.event_table.setItem(row_idx, 5, QTableWidgetItem(pos_str))

                # 【UI高亮美化】：根据不同的冲突类型赋予不同的颜色
                type_item = QTableWidgetItem(type_str)
                if "相向" in type_str or "对穿" in type_str:
                    type_item.setForeground(QColor("#DC3545"))  # 红色 (最危险)
                elif "违停" in type_str or "占位" in type_str:
                    type_item.setForeground(QColor("#FFC107"))  # 橙色
                else:
                    type_item.setForeground(QColor("#17A2B8"))  # 蓝色 (普通追尾/路口)

                # 加粗字体显示冲突类型
                font = QFont()
                font.setBold(True)
                type_item.setFont(font)
                self.event_table.setItem(row_idx, 4, type_item)

    def clear_conflict_events(self):
            """[DELETE] 清空冲突日志表"""
            reply = QMessageBox.question(self, '确认', "确定要彻底清空所有的路径冲突记录吗？",
                                         QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            if reply == QMessageBox.Yes:
                res = self.safe_request("DELETE", "/conflict/clear")
                if res and res.get("status") == "success":
                    self.load_conflict_events()
                else:
                    QMessageBox.warning(self, "错误", res.get("msg", "清空失败") if res else "请求无响应")