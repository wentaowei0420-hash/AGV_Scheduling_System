import json

import requests
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QColor, QFont
from PyQt5.QtWidgets import (
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QSplitter,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
    QHeaderView,
)


class SystemLogWindow(QDialog):
    """工业风系统日志中心，聚焦通信、MES 同步与运行记录。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("系统日志中心")
        self.resize(1120, 760)
        self.log_api_base = "http://127.0.0.1:5000/api/logs"
        self.mes_api_base = "http://127.0.0.1:5000/api/mes"
        self.init_ui()
        self.load_all_data()

    def safe_request(self, base_url, method, endpoint, show_error=True, **kwargs):
        try:
            response = requests.request(method, f"{base_url}{endpoint}", timeout=3, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as exc:
            if show_error:
                QMessageBox.critical(self, "网络异常", f"无法连接后端服务。\n{exc}")
            return None
        except ValueError as exc:
            if show_error:
                QMessageBox.critical(self, "响应异常", f"后端返回了无法解析的内容。\n{exc}")
            return None

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(14)

        title = QLabel("系统日志中心")
        title.setObjectName("WindowTitle")
        subtitle = QLabel("")
        subtitle.setObjectName("MutedText")
        layout.addWidget(title)
        layout.addWidget(subtitle)

        self.tabs = QTabWidget()
        layout.addWidget(self.tabs, 1)

        self.tab_comm = QWidget()
        self.tab_mes = QWidget()
        self.tab_conflict = QWidget()
        self.tab_code = QWidget()
        self.tabs.addTab(self.tab_comm, "通信日志")
        self.tabs.addTab(self.tab_mes, "MES 同步")
        self.tabs.addTab(self.tab_conflict, "冲突事件")
        self.tabs.addTab(self.tab_code, "运行记录")

        self.setup_comm_tab()
        self.setup_mes_tab()
        self.setup_conflict_tab()
        self.setup_code_tab()

        footer = QHBoxLayout()
        footer.addStretch()
        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.close)
        footer.addWidget(close_btn)
        layout.addLayout(footer)

    def make_button(self, text, primary=False):
        button = QPushButton(text)
        if primary:
            button.setObjectName("PrimaryButton")
        return button

    def normalize_comm_row(self, row):
        node_path = str(row.get("node_path", "") or "")
        msg_type = str(row.get("msg_type", "") or "")
        content = str(row.get("content", "") or "")

        if '"type": "conflict_event"' in content or '"type":"conflict_event"' in content:
            node_path = 'MATLAB -> 后端'
            msg_type = '冲突事件'
        elif '"type": "schedule_result"' in content or '"type":"schedule_result"' in content:
            node_path = '调度系统 -> 后端'
            msg_type = '调度结果'
        elif '"cmd": "assign"' in content or '"cmd":"assign"' in content:
            msg_type = '派工指令'
            try:
                payload = json.loads(content)
                agv_name = payload.get('agv') or 'AGV'
                node_path = f'上位机 -> {agv_name}'
            except Exception:
                node_path = '上位机 -> AGV'

        if node_path == 'MATLAB -> Backend':
            node_path = 'MATLAB -> 后端'
        elif node_path == 'Scheduler -> Backend':
            node_path = '调度系统 -> 后端'
        elif node_path.startswith('Upper -> '):
            node_path = '上位机 -> ' + node_path[len('Upper -> '):]

        if msg_type == 'Conflict Event':
            msg_type = '冲突事件'
        elif msg_type == 'Schedule Result':
            msg_type = '调度结果'
        elif msg_type == 'Dispatch Command':
            msg_type = '派工指令'

        return node_path, msg_type

    def load_all_data(self):
        self.load_comm_logs(show_error=False)
        self.load_mes_sync(show_error=False)
        self.load_conflict_events(show_error=False)
        self.load_history_list(show_error=False)

    def setup_comm_tab(self):
        layout = QVBoxLayout(self.tab_comm)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        tools = QHBoxLayout()
        self.btn_refresh_comm = self.make_button("刷新")
        self.btn_clear_comm = self.make_button("清空")
        tools.addWidget(self.btn_refresh_comm)
        tools.addWidget(self.btn_clear_comm)
        tools.addStretch()
        layout.addLayout(tools)

        self.comm_table = QTableWidget()
        self.comm_table.setColumnCount(5)
        self.comm_table.setHorizontalHeaderLabels(["时间", "节点", "类型", "摘要", "状态"])
        self.comm_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.comm_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.comm_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.comm_table.setAlternatingRowColors(True)
        layout.addWidget(self.comm_table)

        self.btn_refresh_comm.clicked.connect(self.load_comm_logs)
        self.btn_clear_comm.clicked.connect(self.clear_comm_logs)

    def load_comm_logs(self, show_error=True):
        res = self.safe_request(self.log_api_base, "GET", "/comm/list", show_error=show_error)
        self.comm_table.setRowCount(0)
        if not res or not res.get("data"):
            return
        rows = res["data"]
        self.comm_table.setRowCount(len(rows))
        for row_idx, row in enumerate(rows):
            node_path, msg_type = self.normalize_comm_row(row)
            values = [
                str(row.get("log_time", "")).split(".")[0],
                node_path,
                msg_type,
                row.get("content", ""),
                row.get("status", row.get("protocol", "")),
            ]
            for col_idx, value in enumerate(values):
                item = QTableWidgetItem("" if value is None else str(value))
                if col_idx == 4:
                    item.setForeground(QColor("#2D6A4F"))
                self.comm_table.setItem(row_idx, col_idx, item)

    def clear_comm_logs(self):
        reply = QMessageBox.question(self, "确认", "确定要清空通信日志吗？", QMessageBox.Yes | QMessageBox.No)
        if reply != QMessageBox.Yes:
            return
        res = self.safe_request(self.log_api_base, "DELETE", "/comm/clear")
        if res and res.get("status") == "success":
            self.load_comm_logs()

    def setup_mes_tab(self):
        layout = QVBoxLayout(self.tab_mes)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        tools = QHBoxLayout()
        self.btn_refresh_mes = self.make_button("刷新")
        self.btn_process_mes = self.make_button("处理待发送", primary=True)
        self.btn_retry_mes = self.make_button("重试选中")
        tools.addWidget(self.btn_refresh_mes)
        tools.addWidget(self.btn_process_mes)
        tools.addWidget(self.btn_retry_mes)
        tools.addStretch()
        layout.addLayout(tools)

        splitter = QSplitter(Qt.Vertical)
        layout.addWidget(splitter)

        self.mes_inbox_table = QTableWidget()
        self.mes_inbox_table.setColumnCount(6)
        self.mes_inbox_table.setHorizontalHeaderLabels(["接收时间", "请求号", "外部订单号", "来源", "状态", "内部订单号"])
        self.mes_inbox_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.mes_inbox_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.mes_inbox_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.mes_inbox_table.setAlternatingRowColors(True)

        self.mes_outbox_table = QTableWidget()
        self.mes_outbox_table.setColumnCount(7)
        self.mes_outbox_table.setHorizontalHeaderLabels(["记录号", "创建时间", "业务类型", "业务ID", "目标系统", "发送状态", "重试次数"])
        self.mes_outbox_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.mes_outbox_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.mes_outbox_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.mes_outbox_table.setAlternatingRowColors(True)

        self.mes_detail = QTextEdit()
        self.mes_detail.setReadOnly(True)
        self.mes_detail.setStyleSheet("QTextEdit { font-family: Consolas, 'Microsoft YaHei'; font-size: 10pt; }")

        splitter.addWidget(self._wrap_table("MES 入站消息", self.mes_inbox_table))
        splitter.addWidget(self._wrap_table("MES 出站消息", self.mes_outbox_table))
        splitter.addWidget(self._wrap_table("消息详情", self.mes_detail))
        splitter.setSizes([220, 240, 180])

        self.btn_refresh_mes.clicked.connect(self.load_mes_sync)
        self.btn_process_mes.clicked.connect(self.process_pending_outbox)
        self.btn_retry_mes.clicked.connect(self.retry_selected_outbox)
        self.mes_inbox_table.itemSelectionChanged.connect(self.show_selected_inbox_detail)
        self.mes_outbox_table.itemSelectionChanged.connect(self.show_selected_outbox_detail)

    def _wrap_table(self, title_text, widget):
        frame = QFrame()
        frame.setObjectName("Card")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)
        title = QLabel(title_text)
        title.setObjectName("SectionTitle")
        title.setStyleSheet("font-size: 10pt;")
        layout.addWidget(title)
        layout.addWidget(widget)
        return frame

    def load_mes_sync(self, show_error=True):
        inbox_res = self.safe_request(self.mes_api_base, "GET", "/inbox/list", show_error=show_error)
        outbox_res = self.safe_request(self.mes_api_base, "GET", "/outbox/list", show_error=show_error)
        self.mes_inbox_table.setRowCount(0)
        self.mes_outbox_table.setRowCount(0)

        if inbox_res and inbox_res.get("data"):
            rows = inbox_res["data"]
            self.mes_inbox_table.setRowCount(len(rows))
            for row_idx, row in enumerate(rows):
                values = [
                    str(row.get("received_at", "")).split(".")[0],
                    row.get("request_id", ""),
                    row.get("external_order_id", ""),
                    row.get("source_system", ""),
                    row.get("receive_status", ""),
                    row.get("internal_order_id", ""),
                ]
                for col_idx, value in enumerate(values):
                    item = QTableWidgetItem("" if value is None else str(value))
                    if col_idx == 0:
                        item.setData(Qt.UserRole, row)
                    self.mes_inbox_table.setItem(row_idx, col_idx, item)

        if outbox_res and outbox_res.get("data"):
            rows = outbox_res["data"]
            self.mes_outbox_table.setRowCount(len(rows))
            for row_idx, row in enumerate(rows):
                values = [
                    row.get("id", ""),
                    str(row.get("created_at", "")).split(".")[0],
                    row.get("biz_type", ""),
                    row.get("biz_id", ""),
                    row.get("target_system", ""),
                    row.get("send_status", ""),
                    row.get("retry_count", 0),
                ]
                for col_idx, value in enumerate(values):
                    item = QTableWidgetItem("" if value is None else str(value))
                    if col_idx == 0:
                        item.setData(Qt.UserRole, row)
                    if col_idx == 5:
                        status = str(value)
                        color = "#2D6A4F" if status == "ACKED" else "#1F5F8B" if status == "SENT" else "#B42318" if status == "FAILED" else "#9A6700"
                        item.setForeground(QColor(color))
                    self.mes_outbox_table.setItem(row_idx, col_idx, item)

        if not inbox_res and not outbox_res:
            self.mes_detail.setPlainText("未连接后台服务。")

    def show_selected_inbox_detail(self):
        row = self.mes_inbox_table.currentRow()
        if row < 0:
            return
        item = self.mes_inbox_table.item(row, 0)
        payload = item.data(Qt.UserRole) if item else None
        if payload:
            self.mes_detail.setPlainText(json.dumps(payload, ensure_ascii=False, indent=2, default=str))

    def show_selected_outbox_detail(self):
        row = self.mes_outbox_table.currentRow()
        if row < 0:
            return
        item = self.mes_outbox_table.item(row, 0)
        payload = item.data(Qt.UserRole) if item else None
        if payload:
            self.mes_detail.setPlainText(json.dumps(payload, ensure_ascii=False, indent=2, default=str))

    def process_pending_outbox(self):
        res = self.safe_request(self.mes_api_base, "POST", "/outbox/process", json={"limit": 20})
        if res and res.get("status") == "success":
            QMessageBox.information(self, "处理完成", res.get("msg", "待发送消息已处理"))
            self.load_mes_sync(show_error=False)

    def retry_selected_outbox(self):
        row = self.mes_outbox_table.currentRow()
        if row < 0:
            QMessageBox.information(self, "提示", "请先选中一条出站消息。")
            return
        item = self.mes_outbox_table.item(row, 0)
        payload = item.data(Qt.UserRole) if item else None
        if not payload:
            return
        record_id = payload.get("id")
        res = self.safe_request(self.mes_api_base, "POST", f"/outbox/retry/{record_id}")
        if res:
            QMessageBox.information(self, "重试结果", res.get("msg", "重试请求已发送"))
            self.load_mes_sync(show_error=False)

    def setup_conflict_tab(self):
        layout = QVBoxLayout(self.tab_conflict)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        tools = QHBoxLayout()
        self.btn_refresh_conflict = self.make_button("刷新")
        self.btn_clear_conflict = self.make_button("清空")
        tools.addWidget(self.btn_refresh_conflict)
        tools.addWidget(self.btn_clear_conflict)
        tools.addStretch()
        layout.addLayout(tools)

        self.event_table = QTableWidget()
        self.event_table.setColumnCount(6)
        self.event_table.setHorizontalHeaderLabels(["记录时间", "仿真步", "主动方", "被动方", "冲突类型", "发生坐标"])
        self.event_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.event_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.event_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.event_table.setAlternatingRowColors(True)
        layout.addWidget(self.event_table)

        self.btn_refresh_conflict.clicked.connect(self.load_conflict_events)
        self.btn_clear_conflict.clicked.connect(self.clear_conflict_events)

    def load_conflict_events(self, show_error=True):
        res = self.safe_request(self.log_api_base, "GET", "/conflict/list", show_error=show_error)
        self.event_table.setRowCount(0)
        if not res or not res.get("data"):
            return
        rows = res["data"]
        self.event_table.setRowCount(len(rows))
        for row_idx, row in enumerate(rows):
            values = [
                str(row.get("report_time", "")).split(".")[0],
                f"T={row.get('sim_step', '')}",
                f"AGV-{int(row.get('agv1_id', 0)):02d}" if row.get("agv1_id") is not None else "",
                f"AGV-{int(row.get('agv2_id', 0)):02d}" if row.get("agv2_id") is not None else "",
                row.get("conflict_type", ""),
                f"A:{row.get('agv1_pos', '')} | B:{row.get('agv2_pos', '')}",
            ]
            for col_idx, value in enumerate(values):
                item = QTableWidgetItem("" if value is None else str(value))
                if col_idx == 4:
                    text = str(value)
                    color = "#B42318" if ("相向" in text or "对穿" in text) else "#9A6700" if ("占位" in text or "违停" in text) else "#1F5F8B"
                    item.setForeground(QColor(color))
                    font = QFont()
                    font.setBold(True)
                    item.setFont(font)
                self.event_table.setItem(row_idx, col_idx, item)

    def clear_conflict_events(self):
        reply = QMessageBox.question(self, "确认", "确定要清空冲突记录吗？", QMessageBox.Yes | QMessageBox.No)
        if reply != QMessageBox.Yes:
            return
        res = self.safe_request(self.log_api_base, "DELETE", "/conflict/clear")
        if res and res.get("status") == "success":
            self.load_conflict_events()

    def setup_code_tab(self):
        layout = QHBoxLayout(self.tab_code)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        left_frame = QFrame()
        left_frame.setObjectName("Card")
        left_layout = QVBoxLayout(left_frame)
        left_layout.setContentsMargins(12, 12, 12, 12)
        left_layout.setSpacing(8)
        history_title = QLabel("历史运行记录")
        history_title.setObjectName("SectionTitle")
        history_title.setStyleSheet("font-size: 10pt;")
        self.history_list = QListWidget()
        self.history_list.itemClicked.connect(self.load_log_content)
        left_layout.addWidget(history_title)
        left_layout.addWidget(self.history_list)

        right_frame = QFrame()
        right_frame.setObjectName("Card")
        right_layout = QVBoxLayout(right_frame)
        right_layout.setContentsMargins(12, 12, 12, 12)
        right_layout.setSpacing(8)
        detail_title = QLabel("日志详情")
        detail_title.setObjectName("SectionTitle")
        detail_title.setStyleSheet("font-size: 10pt;")
        self.log_content_display = QTextEdit()
        self.log_content_display.setReadOnly(True)
        self.log_content_display.setStyleSheet("QTextEdit { font-family: Consolas, 'Microsoft YaHei'; font-size: 10pt; }")
        right_layout.addWidget(detail_title)
        right_layout.addWidget(self.log_content_display)

        layout.addWidget(left_frame, 3)
        layout.addWidget(right_frame, 7)

    def load_history_list(self, show_error=True):
        self.history_list.clear()
        res = self.safe_request(self.log_api_base, "GET", "/code/history", show_error=show_error)
        if not res or not res.get("data"):
            self.history_list.addItem(QListWidgetItem("无记录"))
            return
        for row in res["data"]:
            item = QListWidgetItem(f"运行于 {row.get('run_time', '')}")
            item.setData(Qt.UserRole, row.get("id"))
            self.history_list.addItem(item)

    def load_log_content(self, item):
        log_id = item.data(Qt.UserRole)
        if not log_id:
            self.log_content_display.setPlainText("")
            return
        res = self.safe_request(self.log_api_base, "GET", f"/code/detail/{log_id}")
        if res and res.get("status") == "success":
            self.log_content_display.setPlainText(res.get("data", ""))
        else:
            self.log_content_display.setPlainText("读取日志失败")

