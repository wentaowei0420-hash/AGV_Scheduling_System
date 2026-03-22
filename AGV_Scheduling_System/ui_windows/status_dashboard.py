import requests
from PyQt5.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel,
                             QTableWidget, QTableWidgetItem, QProgressBar, QGroupBox, QFrame, QMessageBox)
from PyQt5.QtGui import QFont
from PyQt5.QtCore import Qt


class StatusDashboardWindow(QDialog):
    """纯 API 驱动的系统状态自检监控大屏"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("系统状态自检监控大屏")
        self.resize(850, 600)
        self.api_base_url = "http://127.0.0.1:5000/api/dashboard"

        # 初始化框架 -> 请求后台同步 CSV -> 加载最终数据
        self.initUI()
        self.sync_agv_metrics_to_db()
        self.load_dashboard_data()

    def safe_request(self, method, endpoint, **kwargs):
        """统一的网络请求异常拦截器"""
        try:
            url = f"{self.api_base_url}{endpoint}"
            res = requests.request(method, url, timeout=3, **kwargs)
            return res.json()
        except requests.exceptions.RequestException as e:
            QMessageBox.critical(self, "网络异常", f"无法连接到后端服务器，请检查 API 是否开启！\n{e}")
            return None

    def sync_agv_metrics_to_db(self):
        """[POST] 通知后端解析它自己目录下的 MATLAB 报文，写入数据库"""
        self.safe_request("POST", "/sync")

    def initUI(self):
        main_layout = QVBoxLayout(self)

        # ================= 1. 顶部：系统订单宏观指标 =================
        order_group = QGroupBox("📊 生产订单全局指标 (MES_ORDERS)")
        order_layout = QHBoxLayout()

        self.lbl_total = self.create_metric_card("总计订单数", "0")
        self.lbl_completed = self.create_metric_card("已完成订单", "0", color="#28A745")
        self.lbl_pending = self.create_metric_card("排队中订单", "0", color="#FFC107")
        self.lbl_rate = self.create_metric_card("整体完成率", "0.0%", color="#17A2B8")

        order_layout.addWidget(self.lbl_total)
        order_layout.addWidget(self.lbl_completed)
        order_layout.addWidget(self.lbl_pending)
        order_layout.addWidget(self.lbl_rate)
        order_group.setLayout(order_layout)
        main_layout.addWidget(order_group)

        # ================= 2. 中部：AGV 设备健康度大屏 =================
        agv_group = QGroupBox("🤖 AGV 物理设备状态自检 (AGV_MONITOR_STATUS)")
        agv_layout = QVBoxLayout()

        self.agv_table = QTableWidget()
        self.agv_table.setColumnCount(5)
        self.agv_table.setHorizontalHeaderLabels(
            ["设备编号", "设备类型", "剩余电量 (Battery)", "总行驶里程", "转弯/机电磨损"])
        self.agv_table.horizontalHeader().setStretchLastSection(True)
        agv_layout.addWidget(self.agv_table)

        agv_group.setLayout(agv_layout)
        main_layout.addWidget(agv_group)

    def create_metric_card(self, title, value, color="#333333"):
        """创建一个美观的指标卡片"""
        card = QFrame()
        card.setStyleSheet("background-color: #F8F9FA; border: 1px solid #DDDDDD; border-radius: 8px; padding: 10px;")
        card_layout = QVBoxLayout(card)

        title_lbl = QLabel(title)
        title_lbl.setAlignment(Qt.AlignCenter)
        title_lbl.setStyleSheet("color: #6c757d; font-weight: bold; border: none;")

        val_lbl = QLabel(value)
        val_lbl.setAlignment(Qt.AlignCenter)
        val_lbl.setStyleSheet(f"color: {color}; font-size: 24px; font-weight: bold; border: none;")

        card_layout.addWidget(title_lbl)
        card_layout.addWidget(val_lbl)

        card.val_lbl = val_lbl  # 挂载变量方便后续更新
        return card

    def load_dashboard_data(self):
        """[GET] 从后台一次性拉取算好的订单指标和 AGV 状态"""
        res = self.safe_request("GET", "/metrics")

        if not res or res.get("status") != "success":
            return

        data = res.get("data", {})
        orders = data.get("orders", {})
        agvs = data.get("agvs", [])

        # 1. 更新顶部指标卡片
        self.lbl_total.val_lbl.setText(str(orders.get("total", 0)))
        self.lbl_completed.val_lbl.setText(str(orders.get("completed", 0)))
        self.lbl_pending.val_lbl.setText(str(orders.get("pending", 0)))
        self.lbl_rate.val_lbl.setText(orders.get("rate", "0.0%"))

        # 2. 更新下方 AGV 数据表
        self.agv_table.setRowCount(len(agvs))
        for i, row in enumerate(agvs):
            self.agv_table.setItem(i, 0, QTableWidgetItem(f"AGV-{row['agv_id']:02d}"))
            type_str = "托举式 (Type 1)" if row['agv_type'] == 1 else "叉车式 (Type 2)"
            self.agv_table.setItem(i, 1, QTableWidgetItem(type_str))

            # 进度条显示电量
            battery = float(row['battery'])
            bar = QProgressBar()
            bar.setValue(int(battery))
            if battery > 50:
                bar.setStyleSheet("QProgressBar::chunk {background-color: #28A745;}")
            elif battery > 20:
                bar.setStyleSheet("QProgressBar::chunk {background-color: #FFC107;}")
            else:
                bar.setStyleSheet("QProgressBar::chunk {background-color: #DC3545;}")
            self.agv_table.setCellWidget(i, 2, bar)

            self.agv_table.setItem(i, 3, QTableWidgetItem(f"{row['total_distance']} 格"))
            self.agv_table.setItem(i, 4, QTableWidgetItem(f"{row['total_turns']} 次"))