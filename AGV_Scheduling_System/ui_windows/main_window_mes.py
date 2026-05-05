import csv
import os

import requests
from PyQt5.QtCore import QDateTime, QThread, QTimer, Qt, pyqtSignal
from PyQt5.QtGui import QPixmap, QTextOption
from PyQt5.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QSizePolicy,
    QStatusBar,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from db_manager import DatabaseManager
from ui_windows.agv_manager import AGVManagerWindow
from ui_windows.status_dashboard import StatusDashboardWindow
from ui_windows.system_log_mes import SystemLogWindow
from ui_windows.task_manager import TaskManagerWindow
from ui_windows.user_manager import UserManagerWindow

# 用于自适应显示图片
class AspectRatioLabel(QLabel):
    # 初始化图片标签，设置最小尺寸和缩放策略。
    def __init__(self, text=""):
        super().__init__(text)
        self.original_pixmap = None
        self.setMinimumSize(1, 1)
        self.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
    # 接收原始图片
    def setPixmap(self, pixmap):
        self.original_pixmap = pixmap
        self.update_pixmap()
    # 当窗口大小变化时自动触发，重新缩放图片。
    def resizeEvent(self, event):
        if self.original_pixmap is not None:
            self.update_pixmap()
        super().resizeEvent(event)
    # 按照当前控件大小，对图片进行等比例缩放
    def update_pixmap(self):
        if self.original_pixmap and not self.original_pixmap.isNull():
            scaled_pixmap = self.original_pixmap.scaled(
                self.size(),
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation,
            )
            super().setPixmap(scaled_pixmap)
# 用于后台请求工厂地图
class MapFetchThread(QThread):
    log_signal = pyqtSignal(str)
    finished_signal = pyqtSignal(bytes)
    def run(self):
        self.log_signal.emit("正在请求工厂地图，请稍候。")
        try:
            response = requests.get("http://127.0.0.1:5000/api/map/generate", timeout=60)
            if response.status_code == 200:
                self.log_signal.emit("工厂地图已更新。")
                self.finished_signal.emit(response.content)
            else:
                self.log_signal.emit(f"地图请求失败，状态码 {response.status_code}。")
        except Exception as exc:
            self.log_signal.emit(f"获取地图失败：{exc}")

class MainWindow(QMainWindow):
    """工业风主控窗口，独立承载控制中心逻辑。"""

    # <editor-fold desc="初始化与界面构建">
    # 创建主窗口时自动执行
    def __init__(self):
        super().__init__()
        self.setWindowTitle("基于AGV的转向架组装生产线配件输送系统 - 控制中心")
        self.api_url = "http://127.0.0.1:5000/api"
        self.last_log_count = 0
        self.api_poll_timer = QTimer(self)
        self.api_poll_timer.timeout.connect(self.poll_backend_status)
        self.map_thread = None

        self.initUI()
        self.setup_status_bar()
        self.check_backend_status()
    # 搭建主界面布局
    def initUI(self):
        self.resize(1360, 840)
        self.setMinimumSize(1200, 760)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        root_layout = QHBoxLayout(central_widget)
        root_layout.setContentsMargins(20, 18, 20, 18)
        root_layout.setSpacing(16)

        nav_panel = QFrame()
        nav_panel.setObjectName("NavPanel")
        nav_panel.setFixedWidth(280)
        nav_layout = QVBoxLayout(nav_panel)
        nav_layout.setContentsMargins(20, 20, 20, 20)
        nav_layout.setSpacing(12)

        nav_title = QLabel("控制中心")
        nav_title.setObjectName("WindowTitle")
        nav_title.setStyleSheet("font-size: 15pt;")
        nav_desc = QLabel("")
        nav_desc.setObjectName("MutedText")
        nav_desc.setWordWrap(True)

        nav_layout.addWidget(nav_title)
        nav_layout.addWidget(nav_desc)
        nav_layout.addSpacing(6)

        buttons_info = [
            ("任务管理", self.open_task_manager, "nav"),
            ("AGV 设备管理", self.open_agv_manager, "nav"),
            ("启动路径规划", self.run_matlab_planning, "primary"),
            ("用户信息管理", self.open_user_manager, "nav"),
            ("刷新工厂地图", self.fetch_factory_map, "nav"),
            ("系统日志中心", self.open_system_log, "nav"),
            ("状态监控", self.open_status_dashboard, "nav"),
            ("系统复位", self.dummy_action, "danger"),
        ]

        for text, callback, kind in buttons_info:
            button = QPushButton(text)
            button.setCursor(Qt.PointingHandCursor)
            if kind == "primary":
                button.setObjectName("PrimaryNavButton")
            elif kind == "danger":
                button.setObjectName("DangerButton")
            else:
                button.setObjectName("NavButton")
            button.clicked.connect(callback)
            nav_layout.addWidget(button)

        nav_layout.addStretch()

        content_layout = QVBoxLayout()
        content_layout.setSpacing(14)

        header_strip = QFrame()
        header_strip.setObjectName("HeaderStrip")
        header_layout = QHBoxLayout(header_strip)
        header_layout.setContentsMargins(22, 18, 22, 18)
        header_layout.setSpacing(18)

        header_text_layout = QVBoxLayout()
        header_text_layout.setSpacing(4)
        header_title = QLabel("AGV 调度与配送控制台")
        header_title.setStyleSheet(
            "color: #F4F7FA; font-size: 17pt; font-weight: 700; background: transparent;"
        )
        header_subtitle = QLabel("")
        header_subtitle.setStyleSheet("color: #AABBCB; background: transparent;")
        header_subtitle.setWordWrap(True)
        header_text_layout.addWidget(header_title)
        header_text_layout.addWidget(header_subtitle)

        header_layout.addLayout(header_text_layout, 3)
        header_layout.addStretch(1)

        self.backend_badge = QLabel("后端待检测")
        self.backend_badge.setObjectName("BadgeNeutral")
        self.scheduler_badge = QLabel("调度待机")
        self.scheduler_badge.setObjectName("BadgeNeutral")
        self.queue_badge = QLabel("待执行任务 --")
        self.queue_badge.setObjectName("BadgeNeutral")

        header_layout.addWidget(self.backend_badge, 0, Qt.AlignRight | Qt.AlignVCenter)
        header_layout.addWidget(self.scheduler_badge, 0, Qt.AlignRight | Qt.AlignVCenter)
        header_layout.addWidget(self.queue_badge, 0, Qt.AlignRight | Qt.AlignVCenter)
        content_layout.addWidget(header_strip)

        card_row = QHBoxLayout()
        card_row.setSpacing(14)
        self.card_backend_value = self._create_status_card(card_row, "后端连接", "未检测")
        self.card_runtime_value = self._create_status_card(card_row, "运行状态", "待机")
        self.card_sync_value = self._create_status_card(card_row, "MES 同步", "仿真模式")
        self.card_outbox_value = self._create_status_card(card_row, "待回传消息", "0")
        content_layout.addLayout(card_row)

        map_card = QFrame()
        map_card.setObjectName("Card")
        map_layout = QVBoxLayout(map_card)
        map_layout.setContentsMargins(18, 16, 18, 16)
        map_layout.setSpacing(10)

        map_header = QHBoxLayout()
        map_title = QLabel("数字化电子栅格")
        map_title.setObjectName("SectionTitle")
        map_hint = QLabel("")
        map_hint.setObjectName("MutedText")
        map_button = QPushButton("更新地图")
        map_button.clicked.connect(self.fetch_factory_map)
        map_header.addWidget(map_title)
        map_header.addSpacing(10)
        map_header.addWidget(map_hint)
        map_header.addStretch()
        map_header.addWidget(map_button)

        self.map_label = AspectRatioLabel("暂无地图")
        self.map_label.setAlignment(Qt.AlignCenter)
        self.map_label.setMinimumHeight(320)
        self.map_label.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.map_label.setStyleSheet(
            "QLabel { background-color: #F4F7FA; border: 1px solid #CFD8E3; border-radius: 4px; color: #61788F; font-weight: 600; }"
        )

        map_layout.addLayout(map_header)
        map_layout.addWidget(self.map_label, 1)
        content_layout.addWidget(map_card, 5)

        log_card = QFrame()
        log_card.setObjectName("Card")
        log_layout = QVBoxLayout(log_card)
        log_layout.setContentsMargins(18, 16, 18, 16)
        log_layout.setSpacing(10)

        log_header = QHBoxLayout()
        log_title = QLabel("运行日志")
        log_title.setObjectName("SectionTitle")
        log_hint = QLabel("")
        log_hint.setObjectName("MutedText")
        clear_button = QPushButton("清空显示")
        clear_button.clicked.connect(lambda: self.log_output.clear())
        log_header.addWidget(log_title)
        log_header.addSpacing(10)
        log_header.addWidget(log_hint)
        log_header.addStretch()
        log_header.addWidget(clear_button)

        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setMinimumHeight(220)
        self.log_output.setLineWrapMode(QTextEdit.WidgetWidth)
        self.log_output.setWordWrapMode(QTextOption.WrapAnywhere)
        self.log_output.setStyleSheet(
            "QTextEdit { background-color: #0F1720; color: #D4DEE7; border: 1px solid #243647; border-radius: 4px; font-family: Consolas, 'Microsoft YaHei'; font-size: 10pt; padding: 10px; }"
        )

        log_layout.addLayout(log_header)
        log_layout.addWidget(self.log_output)
        content_layout.addWidget(log_card, 4)

        root_layout.addWidget(nav_panel)
        root_layout.addLayout(content_layout, 1)
    # 创建顶部状态卡片
    def _create_status_card(self, parent_layout, title, value):
        card = QFrame()
        card.setObjectName("StatusCard")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(6)
        title_label = QLabel(title)
        title_label.setObjectName("MetricTitle")
        value_label = QLabel(value)
        value_label.setObjectName("MetricValue")
        layout.addWidget(title_label)
        layout.addWidget(value_label)
        parent_layout.addWidget(card)
        return value_label
    # </editor-fold>
    #<editor-fold desc="状态栏与日志显示">
    # 创建窗口底部状态栏
    def setup_status_bar(self):
        self.statusBar = QStatusBar()
        self.setStatusBar(self.statusBar)
        self.status_message = QLabel("就绪")
        self.time_label = QLabel()
        self.statusBar.addWidget(self.status_message)
        self.statusBar.addPermanentWidget(self.time_label)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_time)
        self.timer.start(1000)
        self.update_time()
    # 更新时间显示
    def update_time(self):
        self.time_label.setText(QDateTime.currentDateTime().toString("yyyy-MM-dd HH:mm:ss"))
    # 向主界面的运行日志框追加日志
    def append_log(self, text):
        time_str = QDateTime.currentDateTime().toString("HH:mm:ss")
        level = "INFO"
        color = "#9FB3C8"
        if any(flag in text for flag in ["错误", "异常", "失败"]):
            level = "ERROR"
            color = "#E76F51"
        elif "警告" in text:
            level = "WARN"
            color = "#F4A261"
        elif any(flag in text for flag in ["成功", "完成"]):
            level = "OK"
            color = "#6CBF84"
        safe_text = text.replace("\n", "<br>")
        formatted = (
            f"<span style='color:#7D8A97;'>[{time_str}]</span> "
            f"<span style='color:{color}; font-weight:700;'>[{level}]</span> "
            f"<span style='color:#D4DEE7;'>{safe_text}</span>"
        )
        self.log_output.append(formatted)
        self.log_output.verticalScrollBar().setValue(self.log_output.verticalScrollBar().maximum())
        if hasattr(self, "status_message"):
            self.status_message.setText(text if len(text) < 90 else text[:87] + "...")
    # 更新顶部状态徽标的文字和颜色
    def _set_badge_state(self, widget, text, state):
        mapping = {
            "neutral": "BadgeNeutral",
            "info": "BadgeInfo",
            "success": "BadgeSuccess",
            "warning": "BadgeWarning",
            "danger": "BadgeDanger",
        }
        widget.setObjectName(mapping.get(state, "BadgeNeutral"))
        widget.setText(text)
        widget.style().unpolish(widget)
        widget.style().polish(widget)
        widget.update()
    # 刷新首页摘要信息
    def _refresh_summary_snapshot(self):
        try:
            tasks_res = requests.get(f"{self.api_url}/tasks/list", params={"view_type": 0}, timeout=1)
            if tasks_res.status_code == 200:
                task_rows = tasks_res.json().get("data", [])
                pending_count = len(task_rows)
                self.queue_badge.setText(f"待执行任务 {pending_count}")
        except Exception:
            pass

        try:
            outbox_res = requests.get("http://127.0.0.1:5000/api/mes/outbox/list", params={"limit": 200}, timeout=1)
            if outbox_res.status_code == 200:
                outbox_rows = outbox_res.json().get("data", [])
                pending_msgs = [row for row in outbox_rows if row.get("send_status") in ("PENDING", "FAILED")]
                self.card_sync_value.setText("仿真回传")
                self.card_outbox_value.setText(str(len(pending_msgs)))
            else:
                self.card_outbox_value.setText("--")
        except Exception:
            self.card_sync_value.setText("未连接")
            self.card_outbox_value.setText("--")
    # </editor-fold>
    #<editor-fold desc="打开子功能窗口">
    # 打开系统日志中心窗口
    def open_system_log(self):
        self.sys_log_win = SystemLogWindow(self)
        self.sys_log_win.exec_()
    # 打开任务管理窗口
    def open_task_manager(self):
        self.append_log("正在打开任务管理页面。")
        self.task_win = TaskManagerWindow(self)
        self.task_win.exec_()
    # 打开 AGV 设备管理窗口
    def open_agv_manager(self):
        self.append_log("正在打开 AGV 设备管理页面。")
        self.agv_win = AGVManagerWindow(self)
        self.agv_win.exec_()
    # 打开用户管理窗口
    def open_user_manager(self):
        self.append_log("正在打开用户信息管理页面。")
        self.user_win = UserManagerWindow(self)
        self.user_win.exec_()
    # 打开状态监控窗口
    def open_status_dashboard(self):
        self.append_log("正在打开状态监控页面。")
        self.dashboard = StatusDashboardWindow(self)
        self.dashboard.exec_()

    def dummy_action(self):
        sender = self.sender()
        self.append_log(f"[{sender.text()}] 暂未启用。")
    # </editor-fold>
    #<editor-fold desc="后端通信与调度控制">
    # 检查 Flask 后端是否在线
    def check_backend_status(self):
        try:
            res = requests.get(f"{self.api_url}/status", timeout=1)
            if res.status_code == 200:
                payload = res.json()
                status = payload.get("status", "idle")
                self.card_backend_value.setText("已连接")
                self._set_badge_state(self.backend_badge, "后端在线", "success")
                self._refresh_summary_snapshot()
                if status == "running":
                    self.card_runtime_value.setText("运行中")
                    self._set_badge_state(self.scheduler_badge, "调度运行中", "info")
                    self.append_log("检测到后台任务运行中。")
                    self.api_poll_timer.start(1000)
                else:
                    self.card_runtime_value.setText("待机")
                    self._set_badge_state(self.scheduler_badge, "调度待机", "neutral")
            else:
                raise RuntimeError("status endpoint unavailable")
        except Exception:
            self.card_backend_value.setText("离线")
            self.card_runtime_value.setText("未连接")
            self._set_badge_state(self.backend_badge, "后端离线", "danger")
            self._set_badge_state(self.scheduler_badge, "等待连接", "warning")
            self.append_log("未连接后台服务。")
    # 启动路径规划
    def run_matlab_planning(self):
        self.append_log("发送路径规划指令。")
        try:
            response = requests.post(f"{self.api_url}/start", timeout=2)
            if response.status_code == 200:
                self.last_log_count = 0
                self.card_runtime_value.setText("启动中")
                self._set_badge_state(self.scheduler_badge, "任务已提交", "info")
                self.api_poll_timer.start(1000)
                self._refresh_summary_snapshot()
            else:
                self.append_log(f"请求被拒绝: {response.json().get('msg')}")
        except requests.exceptions.ConnectionError:
            self.append_log("无法连接后台服务。")
    # 定时查询后端运行状态
    def poll_backend_status(self):
        try:
            res = requests.get(f"{self.api_url}/status", timeout=1)
            data = res.json()
            logs = data.get("logs", [])
            new_logs = logs[self.last_log_count:]
            for log in new_logs:
                self.append_log(log)
            self.last_log_count = len(logs)

            status = data.get("status")
            if status == "running":
                self.card_runtime_value.setText("运行中")
                self._set_badge_state(self.scheduler_badge, "调度运行中", "info")
            elif status == "finished":
                self.card_runtime_value.setText("已完成")
                self._set_badge_state(self.scheduler_badge, "调度完成", "success")
            elif status == "error":
                self.card_runtime_value.setText("异常")
                self._set_badge_state(self.scheduler_badge, "调度异常", "danger")
            else:
                self.card_runtime_value.setText("待机")
                self._set_badge_state(self.scheduler_badge, "调度待机", "neutral")

            self._refresh_summary_snapshot()

            if status in ["finished", "error"]:
                self.api_poll_timer.stop()
                if status == "finished":
                    self.on_planning_finished()

        except requests.exceptions.ConnectionError:
            pass

    def on_planning_finished(self):
        db = DatabaseManager()
        current_dir = os.path.dirname(os.path.abspath(__file__))
        matlab_dir = os.path.join(current_dir, "matlab_code")
        metrics_path = os.path.join(matlab_dir, "task_metrics.csv")

        if os.path.exists(metrics_path):
            try:
                with open(metrics_path, "r", encoding="utf-8") as file_obj:
                    reader = csv.DictReader(file_obj)
                    for row in reader:
                        tid = row["task_id"]
                        agv = row["agv_id"]
                        t_sec = float(row["time_sec"])
                        dist = int(row["distance"])
                        sql = """UPDATE MES_ORDERS
                                 SET status=2, executor_agv=%s, actual_time=%s, actual_distance=%s
                                 WHERE order_id=%s"""
                        db.execute_update(sql, (agv, t_sec, dist, tid))
                self.append_log("任务执行指标已同步至 MES_ORDERS。")
            except Exception as exc:
                self.append_log(f"任务指标同步失败：{exc}")

        full_log = self.log_output.toPlainText()
        if full_log.strip():
            try:
                current_time = QDateTime.currentDateTime().toString("yyyy-MM-dd HH:mm:ss")
                db.execute_update(
                    "INSERT INTO matlab_run_logs (run_time, log_content) VALUES (%s, %s)",
                    (current_time, full_log),
                )
                self.append_log("本次运行日志已归档到数据库。")
            except Exception as exc:
                self.append_log(f"运行日志归档失败：{exc}")

        self.append_log("后台规划流程已结束。")
    # </editor-fold>
    #<editor-fold desc="地图刷新">
    # 创建 MapFetchThread 后台线程，请求后端生成工厂地图
    def fetch_factory_map(self):
        self.map_thread = MapFetchThread()
        self.map_thread.log_signal.connect(self.append_log)
        self.map_thread.finished_signal.connect(self.display_downloaded_map)
        self.map_thread.start()
    # 接收后端返回的 PNG 图片二进制数据，把它转换成 QPixmap，然后显示到主界面的地图区域。
    def display_downloaded_map(self, image_bytes):
        pixmap = QPixmap()
        pixmap.loadFromData(image_bytes)
        self.map_label.setStyleSheet(
            "QLabel { background-color: #FFFFFF; border: 1px solid #D0D7DE; border-radius: 8px; }"
        )
        self.map_label.setPixmap(pixmap)
    # </editor-fold>
