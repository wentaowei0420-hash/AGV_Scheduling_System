from PyQt5.QtCore import QDateTime, QTimer
from PyQt5.QtWidgets import (
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

from db_manager import DatabaseManager
from ui_windows.login_window import LoginWindow as BaseLoginWindow
from ui_windows.main_window_mes import MainWindow


class LoginWindow(BaseLoginWindow):
    def initUI(self):
        self.resize(980, 620)
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        root_layout = QHBoxLayout(central_widget)
        root_layout.setContentsMargins(48, 40, 48, 40)
        root_layout.setSpacing(24)

        brand_panel = QFrame()
        brand_panel.setObjectName("BrandPanel")
        brand_panel.setMinimumWidth(360)
        brand_layout = QVBoxLayout(brand_panel)
        brand_layout.setContentsMargins(36, 36, 36, 36)
        brand_layout.setSpacing(10)

        brand_title = QLabel("转向架生产线车间")
        brand_title.setObjectName("BrandTitle")
        brand_subtitle = QLabel("AGV 调度系统")
        brand_subtitle.setObjectName("BrandSubtitle")

        brand_layout.addWidget(brand_title)
        brand_layout.addWidget(brand_subtitle)
        brand_layout.addStretch()

        form_panel = QFrame()
        form_panel.setObjectName("FormPanel")
        form_panel.setMinimumWidth(400)
        form_layout = QVBoxLayout(form_panel)
        form_layout.setContentsMargins(42, 38, 42, 38)
        form_layout.setSpacing(18)

        form_title = QLabel("系统登录")
        form_title.setObjectName("WindowTitle")

        field_grid = QGridLayout()
        field_grid.setHorizontalSpacing(14)
        field_grid.setVerticalSpacing(16)

        acc_label = QLabel("姓名")
        acc_label.setObjectName("SectionTitle")
        acc_label.setStyleSheet("font-size: 10pt;")
        self.acc_input = QLineEdit()
        self.acc_input.setPlaceholderText("姓名")

        pwd_label = QLabel("工号")
        pwd_label.setObjectName("SectionTitle")
        pwd_label.setStyleSheet("font-size: 10pt;")
        self.pwd_input = QLineEdit()
        self.pwd_input.setPlaceholderText("工号")
        self.pwd_input.setEchoMode(QLineEdit.Password)

        field_grid.addWidget(acc_label, 0, 0)
        field_grid.addWidget(self.acc_input, 0, 1)
        field_grid.addWidget(pwd_label, 1, 0)
        field_grid.addWidget(self.pwd_input, 1, 1)
        field_grid.setColumnStretch(1, 1)

        action_layout = QHBoxLayout()
        action_layout.setSpacing(12)
        self.login_btn = QPushButton("登录")
        self.login_btn.setObjectName("PrimaryButton")
        self.exit_btn = QPushButton("退出")
        action_layout.addWidget(self.login_btn)
        action_layout.addWidget(self.exit_btn)

        form_layout.addWidget(form_title)
        form_layout.addSpacing(8)
        form_layout.addLayout(field_grid)
        form_layout.addLayout(action_layout)
        form_layout.addStretch()

        root_layout.addWidget(brand_panel, 4)
        root_layout.addWidget(form_panel, 5)

        self.login_btn.clicked.connect(self.check_login)
        self.exit_btn.clicked.connect(self.close)
        self.acc_input.returnPressed.connect(self.check_login)
        self.pwd_input.returnPressed.connect(self.check_login)

    def setup_status_bar(self):
        self.statusBar = QStatusBar()
        self.setStatusBar(self.statusBar)
        self.status_label = QLabel("就绪")
        self.time_label = QLabel()
        self.statusBar.addWidget(self.status_label)
        self.statusBar.addPermanentWidget(self.time_label)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_time)
        self.timer.start(1000)
        self.update_time()

    def update_time(self):
        self.time_label.setText(QDateTime.currentDateTime().toString("yyyy-MM-dd HH:mm:ss"))

    def check_login(self):
        account = self.acc_input.text().strip()
        password = self.pwd_input.text().strip()

        if not account or not password:
            QMessageBox.warning(self, "提示", "请输入姓名和工号。")
            return

        db = DatabaseManager()
        user_info = db.execute_query("SELECT * FROM sys_users WHERE name=%s AND emp_id=%s", (account, password))

        if user_info:
            current_username = user_info[0]["name"]
            current_role = user_info[0].get("job_type") or "管理员"
            log_msg = f"用户 [{current_username}] ({current_role}) 成功登录系统。"
            db.execute_update("INSERT INTO system_logs (log_type, content) VALUES (%s, %s)", ('INFO', log_msg))
            self.main_window = MainWindow()
            self.main_window.show()
            self.main_window.append_log(log_msg)
            self.close()
            return

        db.execute_update(
            "INSERT INTO system_logs (log_type, content) VALUES (%s, %s)",
            ('WARN', f"未知用户尝试登录失败，输入姓名: {account}")
        )
        QMessageBox.warning(self, "错误", "姓名或工号错误，请重试。")
