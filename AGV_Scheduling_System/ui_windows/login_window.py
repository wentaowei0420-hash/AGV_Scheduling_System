import os
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QLabel, QTabWidget, QGroupBox, QFileDialog,
                             QLineEdit, QPushButton, QVBoxLayout, QHBoxLayout,
                             QGridLayout, QFrame, QMessageBox, QTextEdit, QStatusBar,
                             QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QSpinBox, QComboBox)
from PyQt5.QtGui import QPixmap, QFont, QIcon, QColor, QPalette
from PyQt5.QtCore import Qt, QTimer, QDateTime,QThread, pyqtSignal
from db_manager import DatabaseManager
from ui_windows.status_bar_mixin import StatusBarMixin
from ui_windows.main_window import MainWindow

class LoginWindow(QMainWindow, StatusBarMixin):
    """登录窗口类，继承自QMainWindow和状态栏混入类"""

    def __init__(self):
        """构造函数：初始化窗口属性、UI和状态栏"""
        super().__init__()                                       # 调用父类（QMainWindow）的构造函数，完成基础初始化
        self.setWindowTitle("基于AGV的转向架组装生产线配件输送系统 - 登录")  # 设置窗口标题，显示在标题栏
        self.resize(800, 600)                                  # 设置窗口的初始宽度为1600像素，高度为1200像素
        self.initUI()                                            # 调用自定义的initUI方法，创建和布局界面控件
        self.setup_status_bar()                                  # 调用从StatusBarMixin继承的方法，设置窗口底部的状态栏

    def initUI(self):
        """初始化用户界面：背景、登录框及控件布局"""
        # 1. 设置主窗口的中心部件
        central_widget = QWidget()                               # 创建一个QWidget对象，作为主窗口的中心区域容器
        self.setCentralWidget(central_widget)                    # 将central_widget设置为主窗口的中心部件

        # 2. 设置背景图片（使用绝对路径）
        # 获取当前文件（login_window.py）所在目录的上一级目录，即项目根目录
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # 拼接出背景图片的完整路径（假设图片放在项目根目录下的assets文件夹中，名为pg.png）
        image_path = os.path.join(base_dir, "assets", 'pg.png')
        # 将路径中的反斜杠替换为正斜杠，避免QSS中路径解析出错（尤其在Windows系统上）
        image_path = image_path.replace('\\', '/')

        # 使用f-string将图片路径动态嵌入到样式表中，设置中心部件的背景图片、居中显示、不重复，
        # 并指定一个深色背景色（#2C3E50）作为备选，防止图片加载延迟时文字看不清
        central_widget.setStyleSheet(f"""
                    background-image: url({image_path}); 
                    background-position: center; 
                    background-repeat: no-repeat;
                    background-color: #2C3E50;
                """)

        # 3. 创建半透明的登录框（玻璃态效果）
        # 在中心部件上创建一个QFrame，作为登录框的容器
        login_frame = QFrame(central_widget)
        # 固定登录框的宽度为400像素，高度为250像素
        login_frame.setFixedSize(400, 250)
        # 设置登录框样式：白色背景、透明度200（接近不透明）、圆角10像素
        login_frame.setStyleSheet("""
            QFrame {
                background-color: rgba(255, 255, 255, 200);
                border-radius: 10px;
            }
        """)

        # 4. 登录框内部布局和控件
        # 为登录框创建垂直布局管理器，所有子控件将垂直排列
        layout = QVBoxLayout(login_frame)
        # 设置布局内容与边框的距离：左40、上30、右40、下30像素
        layout.setContentsMargins(40, 30, 40, 30)

        # 标题标签
        title = QLabel("请登录管理员账号")                         # 创建一个QLabel，显示提示文字
        title.setFont(QFont("Microsoft YaHei", 14, QFont.Bold))   # 设置字体为微软雅黑、14号、加粗
        title.setAlignment(Qt.AlignCenter)                        # 设置文字居中对齐
        title.setStyleSheet("background: transparent; color: #FFFFFF;")  # 背景透明，文字白色

        # 账号行（使用水平布局）
        acc_layout = QHBoxLayout()                                # 创建水平布局，用于放置账号标签和输入框
        acc_label = QLabel("管理账号:")                            # 创建账号标签
        acc_label.setStyleSheet("background: transparent; font-family: Microsoft YaHei; color: #FFFFFF;")  # 透明背景，白色文字
        self.acc_input = QLineEdit()                              # 创建账号输入框，并保存为实例变量，以便在其他方法中访问
        self.acc_input.setStyleSheet("background: white; border: 1px solid gray;")  # 输入框样式：白色背景、灰色边框
        acc_layout.addWidget(acc_label)                           # 将标签添加到水平布局
        acc_layout.addWidget(self.acc_input)                      # 将输入框添加到水平布局

        # 密码行（水平布局）
        pwd_layout = QHBoxLayout()                                # 创建水平布局，用于放置密码标签和输入框
        pwd_label = QLabel("密      码:")                          # 创建密码标签（文字中间有多个空格，用于对齐）
        pwd_label.setStyleSheet("background: transparent; font-family: Microsoft YaHei; color: #FFFFFF;")
        self.pwd_input = QLineEdit()                              # 创建密码输入框，保存为实例变量
        self.pwd_input.setEchoMode(QLineEdit.Password)            # 设置为密码模式，输入时显示掩码（如圆点）
        self.pwd_input.setStyleSheet("background: white; border: 1px solid gray;")
        pwd_layout.addWidget(pwd_label)                           # 添加标签
        pwd_layout.addWidget(self.pwd_input)                      # 添加输入框

        # 按钮行（水平布局）
        btn_layout = QHBoxLayout()                                # 创建水平布局，用于放置登录和退出按钮
        self.login_btn = QPushButton("登录")                       # 创建登录按钮，保存为实例变量
        self.exit_btn = QPushButton("退出")                        # 创建退出按钮，保存为实例变量
        # 定义按钮通用样式：背景色浅灰、边框深灰、内边距5像素、圆角3像素、微软雅黑字体、文字白色
        btn_style = """
            QPushButton {
                background-color: #E0E0E0; border: 1px solid #A0A0A0; 
                padding: 5px; border-radius: 3px; font-family: Microsoft YaHei; color: #FFFFFF;  
            }
            QPushButton:hover { background-color: #D0D0D0; color: #FF0000;}
        """
        self.login_btn.setStyleSheet(btn_style)                   # 将样式应用到登录按钮
        self.exit_btn.setStyleSheet(btn_style)                    # 应用到退出按钮
        btn_layout.addWidget(self.login_btn)                      # 登录按钮加入水平布局
        btn_layout.addWidget(self.exit_btn)                       # 退出按钮加入水平布局

        # 将所有布局组件添加到登录框的垂直布局中
        layout.addWidget(title)                                   # 添加标题标签
        layout.addSpacing(20)                                     # 添加20像素的垂直空白间距，使标题与账号行分开
        layout.addLayout(acc_layout)                              # 添加账号行的水平布局
        layout.addLayout(pwd_layout)                              # 添加密码行的水平布局
        layout.addSpacing(20)                                     # 添加20像素空白间距，使密码行与按钮行分开
        layout.addLayout(btn_layout)                              # 添加按钮行的水平布局

        # 5. 将登录框居中显示在主窗口内
        # 为中心部件创建一个水平布局，只包含登录框，并设置居中对齐
        main_layout = QHBoxLayout(central_widget)
        main_layout.addWidget(login_frame, alignment=Qt.AlignCenter)  # 将登录框添加到布局，并指定居中对齐

        # 6. 绑定按钮事件
        self.exit_btn.clicked.connect(self.close)                 # 当退出按钮被点击时，调用窗口的close方法关闭窗口
        self.login_btn.clicked.connect(self.check_login)          # 当登录按钮被点击时，调用check_login方法验证身份

    def check_login(self):
        """验证登录信息，处理登录成功/失败逻辑"""
        account = self.acc_input.text().strip()  # 获取输入的姓名
        password = self.pwd_input.text().strip()  # 获取输入的工号

        # 1. 前端基础校验：检查账号和密码是否为空
        if not account or not password:
            QMessageBox.warning(self, "提示", "请输入姓名和工号！")
            return

            # 2. 实例化数据库管理器对象
        db = DatabaseManager()

        # 3. 执行SQL查询，验证姓名和工号是否匹配
        # 修改点：将 username 和 password 替换为 name 和 emp_id
        sql_login = "SELECT * FROM sys_users WHERE name=%s AND emp_id=%s"
        user_info = db.execute_query(sql_login, (account, password))

        # 4. 判断查询结果
        if user_info:
            # 修改点：根据新的表结构提取字段内容
            current_username = user_info[0]['name']  # 获取姓名
            # 兼容处理：如果 job_type 为空，给一个默认的'管理员'称呼
            current_role = user_info[0].get('job_type') or '管理员'

            # --- 额外功能：记录登录操作日志到数据库 ---
            sql_log = "INSERT INTO system_logs (log_type, content) VALUES (%s, %s)"
            log_msg = f"用户 [{current_username}] ({current_role}) 成功登录系统。"
            # 注意：需确保您的数据库中依然保留了 system_logs 这张表
            db.execute_update(sql_log, ('INFO', log_msg))

            # 5. 登录成功，跳转至主界面
            self.main_window = MainWindow()
            self.main_window.show()

            # 可选：在主窗口的日志输出控件中追加一条登录成功信息
            self.main_window.append_log(f"系统提示：{log_msg}")  # 使用 main_window 中封装好的 append_log 方法更安全

            self.close()
        else:
            # 登录失败
            QMessageBox.warning(self, "错误", "姓名或工号错误，请重试！")

            # 可选：记录失败的登录尝试
            sql_log = "INSERT INTO system_logs (log_type, content) VALUES (%s, %s)"
            db.execute_update(sql_log, ('WARN', f"未知用户尝试登录失败，输入姓名: {account}"))