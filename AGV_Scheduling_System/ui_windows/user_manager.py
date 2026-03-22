import os
import requests
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QLabel, QTabWidget, QGroupBox, QFileDialog,
                             QLineEdit, QPushButton, QVBoxLayout, QHBoxLayout, QFormLayout,
                             QGridLayout, QFrame, QMessageBox, QTextEdit, QStatusBar,
                             QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QSpinBox, QComboBox)
from PyQt5.QtGui import QPixmap, QFont, QIcon, QColor, QPalette
from PyQt5.QtCore import Qt


class AddUserDialog(QDialog):
    """独立的弹窗：用于新增用户录入"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("➕ 新增录入用户信息")
        self.resize(400, 500)
        self.setStyleSheet("QDialog { background-color: #FFFFFF; }")
        self.initUI()

    def initUI(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(30, 30, 30, 30)

        form_layout = QFormLayout()
        form_layout.setSpacing(15)

        self.inputs = {}
        fields = [
            ("工号 (必填):", "emp_id"), ("姓名 (必填):", "name"),
            ("性别:", "gender"), ("民族:", "ethnicity"),
            ("工种:", "job_type"), ("工龄:", "seniority"),
            ("电话:", "phone"), ("邮箱:", "email")
        ]

        for label, key in fields:
            if key == "gender":
                inp = QComboBox()
                inp.addItems(["男", "女"])
            else:
                inp = QLineEdit()
                inp.setPlaceholderText(f"请输入{label.split(' ')[0]}")
            inp.setStyleSheet("padding: 8px; border: 1px solid #ccc; border-radius: 4px;")
            self.inputs[key] = inp
            form_layout.addRow(QLabel(label), inp)

        layout.addLayout(form_layout)

        btn_layout = QHBoxLayout()
        self.btn_save = QPushButton("💾 保存提交")
        self.btn_cancel = QPushButton("取消")

        self.btn_save.setStyleSheet(
            "background-color: #28A745; color: white; padding: 10px; border-radius: 4px; font-weight: bold;")
        self.btn_cancel.setStyleSheet(
            "background-color: #6C757D; color: white; padding: 10px; border-radius: 4px; font-weight: bold;")

        self.btn_save.clicked.connect(self.accept)
        self.btn_cancel.clicked.connect(self.reject)

        btn_layout.addWidget(self.btn_save)
        btn_layout.addWidget(self.btn_cancel)
        layout.addLayout(btn_layout)

    def get_data(self):
        """获取表单输入的数据字典"""
        return {key: inp.text().strip() if isinstance(inp, QLineEdit) else inp.currentText()
                for key, inp in self.inputs.items()}


class UserManagerWindow(QDialog):
    """纯 API 驱动的用户信息管理窗口"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("用户管理子系统")
        self.resize(950, 650)
        self.api_base_url = "http://127.0.0.1:5000/api/users"  # 后端 API 基础地址
        self.current_photo_path = ""
        self.initUI()

    def initUI(self):
        self.setStyleSheet("QDialog { background-color: #F4F6F9; }")
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(20, 20, 20, 20)

        header_label = QLabel("👥 用户信息管理")
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

        self.tab_query_modify = QWidget()
        self.tab_add_delete = QWidget()

        self.tabs.addTab(self.tab_query_modify, "🔍 用户信息查询 / 更改")
        self.tabs.addTab(self.tab_add_delete, "➕ 新增 / 删除用户信息")

        self.setup_query_modify_tab()
        self.setup_add_delete_tab()

        main_layout.addWidget(self.tabs)

        bottom_layout = QHBoxLayout()
        bottom_layout.addStretch()
        self.btn_return = QPushButton("返回主菜单")
        self.btn_return.setStyleSheet("""
            QPushButton { background-color: #6C757D; color: white; padding: 10px 30px; border-radius: 6px; font-weight: bold; font-size: 14px;}
            QPushButton:hover { background-color: #5A6268; }
        """)
        self.btn_return.clicked.connect(self.close)
        bottom_layout.addWidget(self.btn_return)
        main_layout.addLayout(bottom_layout)

    def setup_query_modify_tab(self):
        """设置第一个标签页：查询与修改"""
        layout = QVBoxLayout(self.tab_query_modify)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(20)

        search_layout = QHBoxLayout()
        search_layout.addWidget(QLabel("管理员姓名/工号:"))
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("请输入确切的姓名或工号进行查询...")
        self.search_input.setStyleSheet("padding: 8px; border: 1px solid #ccc; border-radius: 4px;")
        search_layout.addWidget(self.search_input)

        self.btn_search = QPushButton("🔍 查询")
        self.btn_modify = QPushButton("💾 确认修改")

        btn_style = "padding: 8px 15px; border-radius: 4px; font-weight: bold; color: white;"
        self.btn_search.setStyleSheet(f"background-color: #007BFF; {btn_style}")
        self.btn_modify.setStyleSheet(f"background-color: #28A745; {btn_style}")

        search_layout.addWidget(self.btn_search)
        search_layout.addWidget(self.btn_modify)
        layout.addLayout(search_layout)

        info_group = QGroupBox("管理员基本信息")
        info_group.setStyleSheet("""
            QGroupBox { border: 1px solid #ccc; border-radius: 8px; margin-top: 20px; font-weight: bold; color: #495057;}
            QGroupBox::title { subcontrol-origin: margin; subcontrol-position: top left; padding: 0 5px; left: 15px; }
        """)
        info_layout = QHBoxLayout(info_group)
        info_layout.setContentsMargins(20, 30, 20, 20)
        info_layout.setSpacing(30)

        photo_layout = QVBoxLayout()
        self.photo_label = QLabel("管理员照片\n(点击上传)")
        self.photo_label.setFixedSize(150, 200)
        self.photo_label.setAlignment(Qt.AlignCenter)
        self.photo_label.setStyleSheet(
            "border: 2px dashed #A0A0A0; background-color: #F8F9FA; color: #888; border-radius: 8px;")
        self.photo_label.mousePressEvent = self.upload_photo
        photo_layout.addWidget(self.photo_label)
        photo_layout.addStretch()
        info_layout.addLayout(photo_layout)

        form_layout = QGridLayout()
        form_layout.setSpacing(15)

        self.fields_query = {}
        labels = [
            ("工        号:", "emp_id"), ("姓        名:", "name"),
            ("性        别:", "gender"), ("民        族:", "ethnicity"),
            ("工        种:", "job_type"), ("工        龄:", "seniority"),
            ("电        话:", "phone"), ("邮        箱:", "email")
        ]

        for i, (label_text, key) in enumerate(labels):
            row = i // 2
            col = (i % 2) * 2
            lbl = QLabel(label_text)
            lbl.setAlignment(Qt.AlignRight | Qt.AlignVCenter)

            if key == "gender":
                inp = QComboBox()
                inp.addItems(["男", "女"])
            else:
                inp = QLineEdit()
                if key == "emp_id":
                    inp.setReadOnly(True)
                    inp.setStyleSheet(
                        "padding: 6px; border: 1px solid #ccc; border-radius: 4px; background-color: #E9ECEF;")
                else:
                    inp.setStyleSheet("padding: 6px; border: 1px solid #ccc; border-radius: 4px;")

            self.fields_query[key] = inp
            form_layout.addWidget(lbl, row, col)
            form_layout.addWidget(inp, row, col + 1)

        info_layout.addLayout(form_layout)
        layout.addWidget(info_group)
        layout.addStretch()

        self.btn_search.clicked.connect(self.execute_query)
        self.btn_modify.clicked.connect(self.execute_modify)

    def setup_add_delete_tab(self):
        """设置第二个标签页：新增与删除"""
        layout = QVBoxLayout(self.tab_add_delete)
        layout.setContentsMargins(20, 20, 20, 20)

        self.user_table = QTableWidget()
        self.user_table.setColumnCount(6)
        self.user_table.setHorizontalHeaderLabels(["工号", "姓名", "性别", "工种", "电话", "邮箱"])
        self.user_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.user_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.user_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.user_table.setStyleSheet(
            "QTableWidget { background-color: white; border: 1px solid #ccc; border-radius: 5px; }")
        layout.addWidget(self.user_table)

        btn_layout = QHBoxLayout()
        self.btn_refresh = QPushButton("🔄 刷新表格")
        self.btn_add_user = QPushButton("➕ 新增录入界面")
        self.btn_delete_user = QPushButton("🗑️ 删除选中用户")

        self.btn_refresh.setStyleSheet(
            "background-color: #17A2B8; color: white; padding: 8px 15px; border-radius: 4px; font-weight: bold;")
        self.btn_add_user.setStyleSheet(
            "background-color: #007BFF; color: white; padding: 8px 15px; border-radius: 4px; font-weight: bold;")
        self.btn_delete_user.setStyleSheet(
            "background-color: #DC3545; color: white; padding: 8px 15px; border-radius: 4px; font-weight: bold;")

        self.btn_refresh.clicked.connect(self.load_table_data)
        self.btn_add_user.clicked.connect(self.execute_add)
        self.btn_delete_user.clicked.connect(self.execute_delete)

        btn_layout.addWidget(self.btn_refresh)
        btn_layout.addStretch()
        btn_layout.addWidget(self.btn_add_user)
        btn_layout.addWidget(self.btn_delete_user)
        layout.addLayout(btn_layout)

        self.load_table_data()

    # ============================================================================
    # 核心改造：纯 API 网络请求方法
    # ============================================================================

    def safe_request(self, method, endpoint, **kwargs):
        """统一的网络请求异常拦截器"""
        try:
            url = f"{self.api_base_url}{endpoint}"
            res = requests.request(method, url, timeout=3, **kwargs)
            return res.json()
        except Exception as e:
            QMessageBox.critical(self, "网络异常", f"无法连接到后端服务器，请检查 API 是否开启！\n{e}")
            return None

    def upload_photo(self, event):
        """本地文件选择器：目前直接将本地绝对路径发给后台保存"""
        fname, _ = QFileDialog.getOpenFileName(self, '选择照片', '', 'Image files (*.jpg *.png)')
        if fname:
            self.current_photo_path = fname
            pixmap = QPixmap(fname)
            self.photo_label.setPixmap(
                pixmap.scaled(self.photo_label.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation))
            self.photo_label.setText("")

    def clear_query_form(self):
        for key, inp in self.fields_query.items():
            if isinstance(inp, QLineEdit):
                inp.clear()
        self.photo_label.clear()
        self.photo_label.setText("管理员照片\n(点击上传)")
        self.current_photo_path = ""

    def load_table_data(self):
        """[GET] 从后台加载用户表格数据"""
        data = self.safe_request("GET", "/list")
        if not data: return

        users = data.get("data", [])
        self.user_table.setRowCount(len(users))
        for row_idx, user in enumerate(users):
            self.user_table.setItem(row_idx, 0, QTableWidgetItem(str(user.get("emp_id", ""))))
            self.user_table.setItem(row_idx, 1, QTableWidgetItem(str(user.get("name", ""))))
            self.user_table.setItem(row_idx, 2, QTableWidgetItem(str(user.get("gender", ""))))
            self.user_table.setItem(row_idx, 3, QTableWidgetItem(str(user.get("job_type", ""))))
            self.user_table.setItem(row_idx, 4, QTableWidgetItem(str(user.get("phone", ""))))
            self.user_table.setItem(row_idx, 5, QTableWidgetItem(str(user.get("email", ""))))

    def execute_query(self):
        """[GET] 发起请求查询用户信息"""
        search_val = self.search_input.text().strip()
        if not search_val: return QMessageBox.warning(self, "提示", "请输入姓名或工号进行查询！")

        res = self.safe_request("GET", f"/query?keyword={search_val}")

        if res and res.get("status") == "success":
            user = res.get("data", {})
            for key in self.fields_query:
                if key == "gender":
                    self.fields_query[key].setCurrentText(user.get(key) or "男")
                else:
                    self.fields_query[key].setText(str(user.get(key) or ""))

            photo_path = user.get("photo_path")
            if photo_path and os.path.exists(photo_path):
                self.current_photo_path = photo_path
                pixmap = QPixmap(photo_path)
                self.photo_label.setPixmap(
                    pixmap.scaled(self.photo_label.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation))
            else:
                self.photo_label.setText("暂无照片\n(点击上传)")
                self.current_photo_path = ""
            QMessageBox.information(self, "查询成功", f"成功找到用户：{user.get('name')}")
        else:
            self.clear_query_form()
            QMessageBox.warning(self, "未找到", res.get("msg", "数据库中没有匹配的用户记录！") if res else "请求异常")

    def execute_modify(self):
        """[PUT] 发送修改用户信息请求"""
        emp_id = self.fields_query["emp_id"].text().strip()
        if not emp_id: return QMessageBox.warning(self, "操作失败", "没有正在编辑的用户。请先查询出一位用户！")

        payload = {key: inp.text().strip() if isinstance(inp, QLineEdit) else inp.currentText()
                   for key, inp in self.fields_query.items()}
        payload["photo_path"] = self.current_photo_path

        res = self.safe_request("PUT", "/update", json=payload)
        if res and res.get("status") == "success":
            QMessageBox.information(self, "成功", "用户信息修改已成功保存到数据库！")
            self.load_table_data()
        else:
            QMessageBox.warning(self, "失败", res.get("msg", "修改保存失败") if res else "无响应")

    def execute_add(self):
        """[POST] 发送新增用户请求"""
        dialog = AddUserDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            new_user = dialog.get_data()
            if not new_user['emp_id'] or not new_user['name']:
                return QMessageBox.warning(self, "警告", "工号和姓名不能为空！")

            res = self.safe_request("POST", "/add", json=new_user)
            if res:
                if res.get("status") == "success":
                    QMessageBox.information(self, "成功", f"用户 {new_user['name']} 已成功录入！")
                    self.load_table_data()
                else:
                    QMessageBox.warning(self, "失败", res.get("msg", "录入失败"))

    def execute_delete(self):
        """[DELETE] 发送删除用户请求"""
        selected = self.user_table.selectedItems()
        if not selected: return QMessageBox.warning(self, "提示", "请先在表格中选中要删除的用户！")

        row = selected[0].row()
        emp_id = self.user_table.item(row, 0).text()
        user_name = self.user_table.item(row, 1).text()

        reply = QMessageBox.question(self, '危险操作确认',
                                     f"确定要彻底删除工号为 [{emp_id}] 的用户 {user_name} 吗？\n此操作不可逆！",
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)

        if reply == QMessageBox.Yes:
            res = self.safe_request("DELETE", f"/delete/{emp_id}")
            if res and res.get("status") == "success":
                self.user_table.removeRow(row)
                QMessageBox.information(self, "成功", "用户已彻底删除。")
                if self.fields_query["emp_id"].text() == emp_id:
                    self.clear_query_form()