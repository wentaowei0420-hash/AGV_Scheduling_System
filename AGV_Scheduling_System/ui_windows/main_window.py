# ui_windows/main_window.py
import csv
import os
import requests
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QLabel, QTabWidget, QGroupBox, QFileDialog,
                             QLineEdit, QPushButton, QVBoxLayout, QHBoxLayout,
                             QGridLayout, QFrame, QMessageBox, QTextEdit, QStatusBar, QSizePolicy,
                             QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QSpinBox, QComboBox)
from PyQt5.QtGui import QPixmap, QFont, QIcon, QColor, QPalette,QTextOption
from PyQt5.QtCore import Qt, QTimer, QDateTime, QThread, pyqtSignal
from db_manager import DatabaseManager

from ui_windows.task_manager import TaskManagerWindow
from ui_windows.agv_manager import AGVManagerWindow
from ui_windows.user_manager import UserManagerWindow
from ui_windows.system_log import SystemLogWindow
from ui_windows.map_info_window import MapInfoWindow
from ui_windows.status_bar_mixin import StatusBarMixin
from ui_windows.path_viewer import PathViewerWindow
from ui_windows.status_dashboard import StatusDashboardWindow

class AspectRatioLabel(QLabel):
    """自定义的高级 QLabel，能够等比例、平滑地自适应缩放图片"""
    def __init__(self, text=""):
        super().__init__(text)
        self.original_pixmap = None
        self.setMinimumSize(1, 1)
        self.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)

    def setPixmap(self, pixmap):
        # 保存原始的高清大图
        self.original_pixmap = pixmap
        self.update_pixmap()

    def resizeEvent(self, event):
        # 当主窗口大小发生改变时，自动触发重绘
        if self.original_pixmap is not None:
            self.update_pixmap()
        super().resizeEvent(event)

    def update_pixmap(self):
        # 按照当前 Label 的真实尺寸，进行等比例 (KeepAspectRatio) 和平滑 (SmoothTransformation) 缩放
        if self.original_pixmap and not self.original_pixmap.isNull():
            scaled_pixmap = self.original_pixmap.scaled(
                self.size(),
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation
            )
            super().setPixmap(scaled_pixmap)

class MapFetchThread(QThread):
    """后台网络请求线程：向 Flask API 获取渲染好的地图图片"""
    log_signal = pyqtSignal(str)  # 发送文本日志
    finished_signal = pyqtSignal(bytes)  # 发送下载好的图片二进制数据

    def run(self):
        self.log_signal.emit("系统提示：正在向后台服务器请求工厂拓扑地图 (大概需要几秒钟启动引擎，请稍候)...")
        try:
            # 发起 GET 请求获取地图，超时时间设为 60 秒（MATLAB启动和画图需要时间）
            response = requests.get("http://127.0.0.1:5000/api/map/generate", timeout=60)

            if response.status_code == 200:
                self.log_signal.emit("系统提示：地图数据下载成功，正在渲染至界面...")
                # 将图片的二进制数据通过信号发给主界面
                self.finished_signal.emit(response.content)
            else:
                self.log_signal.emit(f"系统错误：【地图请求失败】 HTTP 状态码 {response.status_code}")

        except Exception as e:
            self.log_signal.emit(f"系统警告：【网络通信异常】无法获取地图，请检查后端是否开启 ({str(e)})")

class MainWindow(QMainWindow, StatusBarMixin):
    """主窗口类，继承自QMainWindow和状态栏混入类"""

    def __init__(self):
        """构造函数：初始化窗口属性、UI和状态栏"""
        # 调用父类 QMainWindow 的构造函数，完成基础初始化
        super().__init__()
        # 设置窗口标题，显示在标题栏
        self.setWindowTitle("基于AGV的转向架组装生产线配件输送系统 - 控制中心")
        # 设置窗口初始宽度为1100像素，高度为700像素
        self.resize(1100, 700)
        # 调用自定义的 initUI 方法，创建和布局界面控件
        self.initUI()
        # 调用从 StatusBarMixin 继承的方法，设置窗口底部的状态栏
        self.setup_status_bar()
        # 定义后端 API 的基础 URL，假设 Flask 服务运行在本地 5000 端口
        self.api_url = "http://127.0.0.1:5000/api"
        # 记录上一次获取日志时的日志条目数量，用于增量拉取新日志
        self.last_log_count = 0
        # 创建一个 QTimer 定时器，用于定期轮询后端状态
        self.api_poll_timer = QTimer(self)
        # 将定时器的超时信号连接到 poll_backend_status 方法
        self.api_poll_timer.timeout.connect(self.poll_backend_status)

        # 启动时检测后端是否已有正在运行的任务（断线重连逻辑）
        self.check_backend_status()

        # MATLAB 引擎实例占位符，目前未实际使用，可能是预留用于直接调用 MATLAB
        self.matlab_engine = None

    def initUI(self):
        """初始化用户界面：左侧垂直按钮操作区，右侧全屏日志区"""
        # --- 全局主背景色设置 ---
        # 创建中心部件，所有其他控件都放在这个部件上
        central_widget = QWidget()
        # 设置中心部件的背景色为浅灰色（#F4F6F9）
        central_widget.setStyleSheet("background-color: #F4F6F9;")
        # 将中心部件设为主窗口的中心区域
        self.setCentralWidget(central_widget)

        # 创建主布局为水平布局，包含左侧面板和右侧面板
        main_layout = QHBoxLayout(central_widget)
        # 设置布局的外边距：左15、上15、右15、下15像素
        main_layout.setContentsMargins(15, 15, 15, 15)
        # 设置布局内控件之间的间距为20像素
        main_layout.setSpacing(20)

        # ==========================================
        # 左侧：系统控制面板 (垂直布局，一行一个按钮)
        # ==========================================
        # 创建一个 QFrame 作为左侧面板的容器
        left_panel = QFrame()
        # 设置面板样式：白色背景、圆角12像素、浅灰色边框
        left_panel.setStyleSheet("""
            QFrame {
                background-color: #FFFFFF;
                border-radius: 12px;
                border: 1px solid #E0E4E8;
            }
        """)
        # 为左侧面板创建垂直布局管理器
        left_layout = QVBoxLayout(left_panel)
        # 设置布局边距：左20、上20、右20、下20像素
        left_layout.setContentsMargins(20, 20, 20, 20)
        # 设置垂直布局内控件之间的间距为15像素
        left_layout.setSpacing(15)

        # --- 1. 面板标题 ---
        # 创建标题标签，显示“🛠️ 系统控制面板”，带表情符号
        panel_title = QLabel("🛠️ 系统控制面板")
        # 设置标题字体：微软雅黑、14号、加粗
        panel_title.setFont(QFont("Microsoft YaHei", 14, QFont.Bold))
        # 设置标题样式：深灰色文字，无边框，背景透明
        panel_title.setStyleSheet("color: #2C3E50; border: none; background: transparent;")
        # 设置标题文字居中对齐
        panel_title.setAlignment(Qt.AlignCenter)
        # 将标题添加到左侧面板的垂直布局中
        left_layout.addWidget(panel_title)

        # --- 2. 垂直按钮列表 ---
        # 定义按钮信息列表，每个元素为 (按钮文本, 点击时调用的函数, 按钮类型)
        buttons_info = [
            ("任务管理", self.open_task_manager, "normal"),
            # ("AGV路径浏览", self.open_global_path_viewer, "normal"),  # 这一行被注释掉了，可能暂时隐藏
            ("AGV设备管理", self.open_agv_manager, "normal"),
            ("开始路径规划", self.run_matlab_planning, "primary"),
            ("用户信息管理", self.open_user_manager, "normal"),
            ("显示工厂地图", self.open_map_info_window, "normal"),
            ("系统事件与日志", self.open_system_log, "normal"),
            ("状态自检监控", self.open_status_dashboard, "normal"),
            ("系统复位", self.dummy_action, "danger")
        ]

        # 定义按钮的通用样式模板，使用占位符 {} 填充具体颜色值
        btn_style_base = """
            QPushButton {{
                background-color: {bg}; border: 1px solid {border}; color: {text};
                padding: 15px; /* 增加内边距以增加高度 */
                border-radius: 8px; font-family: Microsoft YaHei; font-size: 14px; font-weight: bold;
            }}
            QPushButton:hover {{ background-color: {hover_bg}; }}
            QPushButton:pressed {{ background-color: {press_bg}; }}
        """

        # 定义不同类型按钮的颜色方案
        styles = {
            "normal": {"bg": "#F8F9FA", "border": "#DEE2E6", "text": "#495057", "hover_bg": "#E2E6EA",
                       "press_bg": "#DAE0E5"},
            "primary": {"bg": "#007BFF", "border": "#007BFF", "text": "#FFFFFF", "hover_bg": "#0069D9",
                        "press_bg": "#0062CC"},
            "danger": {"bg": "#FFF5F5", "border": "#FFC9C9", "text": "#E03131", "hover_bg": "#FFE3E3",
                       "press_bg": "#FFC9C9"},
        }

        # 遍历按钮信息列表，逐个创建按钮
        for text, func, b_type in buttons_info:
            btn = QPushButton(text)  # 创建按钮，文本为 text
            # 根据按钮类型从 styles 字典中获取对应的颜色方案
            s = styles[b_type]
            # 将颜色方案填入样式模板，并设置为按钮的样式
            btn.setStyleSheet(btn_style_base.format(**s))

            # 【关键】设置按钮的尺寸策略：水平方向尽可能伸展（Expanding），垂直方向保持首选尺寸（Preferred）
            # 这确保了按钮会占满左侧面板的宽度
            btn.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)

            # 如果按钮类型为 primary，将鼠标光标设置为手型（表示可点击）
            if b_type == "primary":
                btn.setCursor(Qt.PointingHandCursor)

            # 将按钮的点击信号连接到对应的函数 func
            btn.clicked.connect(func)
            # 将按钮添加到左侧面板的垂直布局中
            left_layout.addWidget(btn)

        # 在垂直布局末尾添加一个弹簧，将按钮组推到顶部（如果希望按钮居中，可以注释掉这一行）
        left_layout.addStretch()

        # 将左侧面板添加到主布局，拉伸因子为1（表示左侧面板占用较少的空间）
        main_layout.addWidget(left_panel, 1)

        # ==========================================
        # 右侧：运行日志终端 (占满剩余空间)
        # ==========================================
        # 创建右侧面板的 QFrame 容器
        right_panel = QFrame()
        # 设置样式：白色背景、圆角12像素、浅灰色边框，与左侧面板一致
        right_panel.setStyleSheet("""
            QFrame {
                background-color: #FFFFFF;
                border-radius: 12px;
                border: 1px solid #E0E4E8;
            }
        """)
        # 为右侧面板创建垂直布局
        right_layout = QVBoxLayout(right_panel)
        # 设置布局边距：左20、上20、右20、下20像素
        right_layout.setContentsMargins(20, 20, 20, 20)
        # 设置垂直布局内控件间距为10像素
        right_layout.setSpacing(10)

        # ================== 新增：工厂地图展示区 ==================
        map_title = QLabel("🗺️ 工厂数字化栅格地图")
        map_title.setFont(QFont("Microsoft YaHei", 12, QFont.Bold))
        map_title.setStyleSheet("color: #2C3E50; border: none; background: transparent;")
        right_layout.addWidget(map_title)

        # 创建一个 QLabel 用于承载图片
        self.map_label = AspectRatioLabel("地图未加载，请点击获取...")
        self.map_label.setAlignment(Qt.AlignCenter)
        self.map_label.setStyleSheet("""
                    QLabel {
                        background-color: #FFFFFF;
                        border: 1px solid #D0D7DE;
                        border-radius: 8px;
                        color: #8C959F;
                        font-weight: bold;
                    }
                """)

        # 将地图区域加入右侧布局，分配比例为 5（地图区域更大）
        right_layout.addWidget(self.map_label, 5)

        # =========================================================

        # --- 日志标题 ---
        # 创建日志标题标签，带表情符号
        log_title = QLabel("📝 运行日志终端")
        log_title.setFont(QFont("Microsoft YaHei", 12, QFont.Bold))
        log_title.setStyleSheet("color: #2C3E50; border: none; background: transparent; margin-top: 10px;")
        right_layout.addWidget(log_title)

        # --- 日志输出区 ---
        # 创建 QTextEdit 用于显示日志，设置为只读
        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setLineWrapMode(QTextEdit.WidgetWidth)
        self.log_output.setWordWrapMode(QTextOption.WrapAnywhere)  # 强制在边界处折行，防止出现水平滚动条
        # 设置日志框样式：深色背景、浅灰色文字、圆角边框、等宽字体
        self.log_output.setStyleSheet("""
            QTextEdit {
                background-color: #1E1E1E; 
                color: #A9B7C6; 
                border: 1px solid #3C3F41; 
                border-radius: 8px; 
                font-family: Consolas, "Microsoft YaHei"; 
                font-size: 13px;
                padding: 10px;
                selection-background-color: #214283;
            }
            /* 滚动条样式定制 */
            QScrollBar:vertical { border: none; background: #2B2B2B; width: 10px; border-radius: 5px; }
            QScrollBar::handle:vertical { background: #555555; min-height: 20px; border-radius: 5px; }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { border: none; background: none; }
        """)
        # 添加两条初始化日志示例
        self.log_output.append("<span style='color: #629755;'>[系统初始化]</span> 本机操作：界面 UI 布局重构完成。")
        self.log_output.append("<span style='color: #629755;'>[系统监测]</span> 设备故障：无故障，通信链路正常...")

        # 将日志框添加到右侧布局
        right_layout.addWidget(self.log_output,3)

        # 将右侧面板添加到主布局，拉伸因子为3（表示右侧面板占用更多空间，日志区更宽）
        main_layout.addWidget(right_panel, 3)

    def append_log(self, text):
        """向右下角文本框追加日志 (带时间戳和颜色区分)"""
        # 获取当前系统时间，格式化为 HH:mm:ss（时:分:秒）
        time_str = QDateTime.currentDateTime().toString("HH:mm:ss")
        # 根据文本内容判断日志类型并分配颜色
        if "错误" in text or "异常" in text:
            color = "#CC666E"       # 柔和的红色（错误/异常）
        elif "提示" in text or "成功" in text:
            color = "#629755"       # 柔和的绿色（提示/成功）
        elif "警告" in text:
            color = "#E6A252"       # 柔和的橙黄色（警告）
        else:
            color = "#A9B7C6"       # 默认灰白色
        safe_text = text.replace('\n', '<br>').replace('  ', '&nbsp;&nbsp;')
        # 格式化日志字符串：时间戳为灰色，内容使用对应颜色
        formatted_text = f"<span style='color: #808080;'>[{time_str}]</span> <span style='color: {color};'>{safe_text}</span>"
        # 将格式化后的文本追加到日志框
        self.log_output.append(formatted_text)
        # 获取日志框的垂直滚动条，并将其滑动到底部，确保最新日志可见
        self.log_output.verticalScrollBar().setValue(self.log_output.verticalScrollBar().maximum())

    def open_global_path_viewer(self):
        """点击控制中心按钮打开全局浏览模式"""
        # 创建 PathViewerWindow 实例，传入 None 表示允许用户手动选择 AGV ID，并将当前窗口作为父窗口
        viewer = PathViewerWindow(None, self)
        # 以模态对话框方式运行（阻塞主窗口）
        viewer.exec_()

    def dummy_action(self):
        """临时占位函数，用于未实现的功能按钮"""
        # 获取发出信号的按钮对象
        sender = self.sender()
        # 向日志框追加一条警告信息，提示该功能正在开发中
        self.append_log(f"系统警告：点击了 [{sender.text()}] 功能，该模块开发中...")

    def open_system_log(self):
        """打开系统事件与日志中心窗口"""
        # 追加日志提示
        self.append_log("系统提示：正在打开 系统事件与日志中心 页面...")
        # 创建 SystemLogWindow 实例，传入当前窗口作为父窗口
        self.sys_log_win = SystemLogWindow(self)
        # 以模态对话框方式运行
        self.sys_log_win.exec_()

    def open_task_manager(self):
        """打开任务管理窗口（模态对话框）"""
        # 追加日志提示
        self.append_log("系统提示：正在打开任务管理页面...")
        # 创建 TaskManagerWindow 实例，传入当前窗口作为父窗口
        self.task_win = TaskManagerWindow(self)
        # 以模态对话框方式运行
        self.task_win.exec_()

    def open_agv_manager(self):
        """打开AGV设备管理窗口"""
        # 追加日志提示
        self.append_log("系统提示：正在打开 AGV 设备管理页面...")
        # 创建 AGVManagerWindow 实例，传入当前窗口作为父窗口
        self.agv_win = AGVManagerWindow(self)
        # 以模态对话框方式运行
        self.agv_win.exec_()

    def open_map_info_window(self):
        """打开地图信息管理窗口（非模态）"""

        self.fetch_factory_map()
        """
            # 追加日志提示
            self.append_log("系统提示：正在打开地图信息管理页面...")
            # 创建 MapInfoWindow 实例，传入当前窗口作为父窗口
            self.map_win = MapInfoWindow(self)
            # 以非模态方式显示（show 不会阻塞主窗口）
            self.map_win.show()
    
        """

    def open_user_manager(self):
        """打开用户信息管理窗口"""
        # 追加日志提示
        self.append_log("系统提示：正在打开 用户信息管理 页面...")
        # 创建 UserManagerWindow 实例，传入当前窗口作为父窗口
        self.user_win = UserManagerWindow(self)
        # 以模态对话框方式运行
        self.user_win.exec_()

    def open_status_dashboard(self):
        """点击打开状态自检监控大屏"""
        # 追加日志提示
        self.append_log("系统提示：正在初始化状态自检监控中心，拉取底层物理设备数据...")
        # 创建 StatusDashboardWindow 实例，传入当前窗口作为父窗口
        self.dashboard = StatusDashboardWindow(self)
        # 以模态对话框方式运行
        self.dashboard.exec_()

    def on_planning_finished(self):
        """MATLAB 线程结束后的回调函数：负责更新任务指标及归档运行日志"""
        # 实例化数据库管理器对象
        db = DatabaseManager()

        # ================== 核心功能 A：物理执行指标反向入库 ==================
        # 定位 MATLAB 生成的 CSV 文件路径
        current_dir = os.path.dirname(os.path.abspath(__file__))  # 获取当前文件所在目录
        # 假设 matlab_code 文件夹与 main_window.py 同级，构建完整路径
        matlab_dir = os.path.join(current_dir, "matlab_code")
        metrics_path = os.path.join(matlab_dir, "task_metrics.csv")  # CSV 文件完整路径

        # 检查文件是否存在
        if os.path.exists(metrics_path):
            try:
                # 以只读方式打开 CSV 文件，指定编码为 utf-8
                with open(metrics_path, 'r', encoding='utf-8') as f:
                    # 使用 DictReader 将每一行读取为字典，列名作为键
                    reader = csv.DictReader(f)
                    # 遍历每一行记录
                    for row in reader:
                        # 提取 MATLAB 物理仿真结果中的字段
                        tid = row['task_id']          # 任务ID（对应数据库中的 order_id）
                        agv = row['agv_id']            # 执行该任务的 AGV 编号
                        t_sec = float(row['time_sec']) # 实际耗时（秒）
                        dist = int(row['distance'])    # 行驶距离（格数）

                        # 执行 SQL 更新：将任务状态设为已完成（假设状态2代表完成），并记录执行AGV、实际耗时、实际里程
                        sql = """UPDATE MES_ORDERS 
                                 SET status=2, executor_agv=%s, actual_time=%s, actual_distance=%s 
                                 WHERE order_id=%s"""
                        db.execute_update(sql, (agv, t_sec, dist, tid))

                # 追加成功日志
                self.append_log("系统提示：✅ 任务执行指标（AGV/耗时/里程）已同步至 MES_ORDERS 表。")
            except Exception as e:
                # 如果发生异常（如文件格式错误、数据库连接失败等），追加警告日志并输出异常信息
                self.append_log(f"系统警告：任务指标同步失败 ({e})")

        # ================== 核心功能 B：运行日志全量归档 ==================
        # 从 UI 日志控件中获取当前显示的所有文本内容
        full_log = self.log_output.toPlainText()

        # 如果日志内容不为空（去除空白后仍有内容）
        if full_log.strip():
            try:
                # 获取当前系统时间，格式化为 "yyyy-MM-dd HH:mm:ss"（年-月-日 时:分:秒）
                current_time = QDateTime.currentDateTime().toString("yyyy-MM-dd HH:mm:ss")
                # 将全量日志内容插入日志归档表 matlab_run_logs
                log_sql = "INSERT INTO matlab_run_logs (run_time, log_content) VALUES (%s, %s)"
                db.execute_update(log_sql, (current_time, full_log))

                # 追加成功日志
                self.append_log("系统提示：本次运行日志已成功归档至数据库。")
            except Exception as e:
                # 归档失败时追加警告日志，提示检查表是否创建
                self.append_log(f"系统警告：日志归档失败，请检查数据库表 matlab_run_logs 是否创建 ({e})")

        # 解除 UI 监听状态，恢复交互（追加一条提示信息）
        self.append_log("系统提示：后台规划线程已安全结束。")

    def fetch_factory_map(self):
        """触发后台地图拉取任务"""
        # 实例化网络请求线程
        self.map_thread = MapFetchThread()
        # 绑定日志信号到界面底部的黑框
        self.map_thread.log_signal.connect(self.append_log)
        # 绑定完成信号到图片渲染函数
        self.map_thread.finished_signal.connect(self.display_downloaded_map)
        # 启动线程
        self.map_thread.start()

    def display_downloaded_map(self, image_bytes):
        """接收来自线程的图片字节流，显示图片并根据图片比例自动适配主窗口大小"""
        from PyQt5.QtWidgets import QApplication  # 确保引入了 QApplication
        from PyQt5.QtGui import QPixmap

        pixmap = QPixmap()
        pixmap.loadFromData(image_bytes)  # 将二进制流转化为图像对象

        # 1. 更新样式并放入图片
        self.map_label.setStyleSheet("""
            QLabel {
                background-color: #FFFFFF;
                border: 1px solid #D0D7DE;
                border-radius: 8px;
            }
        """)
        self.map_label.setPixmap(pixmap)

        # ==================== 核心：自动适配窗口大小 ====================
        img_w = pixmap.width()
        img_h = pixmap.height()

        if img_h > 0:
            # 1. 计算 MATLAB 高清地图真实的宽高比 (例如 1.25)
            aspect_ratio = img_w / img_h

            # 2. 获取当前主窗口的高度
            current_win_height = self.height()

            # 3. 反向推算地图展示区目前的高度
            # 主窗口高度 - 主布局上下边距(30) - 右侧面板上下边距(40) - 控件间距(10)
            # 因为地图(5)与日志(3)的比例是 5:3，所以地图高度占总剩余高度的 5/8
            map_label_height = (current_win_height - 80) * (5 / 8)

            # 4. 根据地图真实的宽高比，计算出地图“最完美”的显示宽度（不多一丝留白）
            perfect_map_width = map_label_height * aspect_ratio

            # 5. 反推主窗口所需的总宽度
            # 右侧面板宽度 = 完美地图宽度 + 左右内边距(40)
            right_panel_width = perfect_map_width + 40

            # 因为左侧控制面板占 1 份，右侧占 3 份，所以总内部宽度是右侧的 4/3 倍
            # 再加上主布局的左右边距(30)和左右面板间距(20)
            target_win_width = int((right_panel_width * 4 / 3) + 50)

            # 6. 安全机制：防止算出来的宽度比用户的显示器屏幕还要大
            screen_width = QApplication.desktop().availableGeometry().width()
            # 限制最大不超过屏幕宽度的 90%
            target_win_width = min(target_win_width, int(screen_width * 0.9))

            # 7. 魔法时刻：命令主窗口平滑变形！
            self.resize(target_win_width, current_win_height)
        # ==============================================================

    def check_backend_status(self):
        """界面启动时，探活后台 API"""
        try:
            # 向后端 API 的 /status 端点发送 GET 请求，超时时间为1秒
            res = requests.get(f"{self.api_url}/status", timeout=1)
            # 检查响应状态码是否为200，且返回的 JSON 中 status 字段为 "running"
            if res.status_code == 200 and res.json().get("status") == "running":
                # 如果后台正在运行，追加日志提示
                self.append_log("系统提示：检测到后台仿真正在运行，正在接管日志...")
                # 启动定时器，每隔1000毫秒（1秒）轮询一次后台状态
                self.api_poll_timer.start(1000)
        except:
            # 如果请求失败（如连接被拒绝），追加警告日志，提示用户启动 backend_api.py
            self.append_log("系统警告：未检测到后台 API 服务，请确认 backend_api.py 已启动。")

    def run_matlab_planning(self):
        """点击【开始路径规划】按钮"""
        # 追加日志提示
        self.append_log("系统提示：正在向后台 API 发送路径规划指令...")
        try:
            # 向后端 API 的 /start 端点发送 POST 请求，超时时间为2秒
            response = requests.post(f"{self.api_url}/start", timeout=2)
            # 如果请求成功（状态码200）
            if response.status_code == 200:
                # 重置日志计数为0，以便从头开始拉取新日志
                self.last_log_count = 0
                # 启动定时器，每秒轮询一次后台状态和日志
                self.api_poll_timer.start(1000)
            else:
                # 如果请求被拒绝，从响应 JSON 中获取错误信息并追加到日志
                self.append_log(f"请求被拒绝: {response.json().get('msg')}")
        except requests.exceptions.ConnectionError:
            # 捕获连接错误（如后端未启动），追加错误日志
            self.append_log("系统错误：无法连接后台引擎，请运行 backend_api.py。")

    def poll_backend_status(self):
        """定时器：每秒向 API 拉取最新状态和日志"""
        try:
            # 向后端 API 的 /status 端点发送 GET 请求，超时1秒
            res = requests.get(f"{self.api_url}/status", timeout=1)
            # 解析返回的 JSON 数据
            data = res.json()

            # 获取日志列表（假设后端返回格式包含 "logs" 字段）
            logs = data.get("logs", [])
            # 仅获取上次拉取之后的新日志
            new_logs = logs[self.last_log_count:]
            # 遍历新日志，逐条追加到界面日志框
            for log in new_logs:
                self.append_log(log)
            # 更新 last_log_count 为当前日志总数
            self.last_log_count = len(logs)

            # 检查后台任务状态
            status = data.get("status")
            # 如果状态为 "finished" 或 "error"，停止轮询
            if status in ["finished", "error"]:
                self.api_poll_timer.stop()  # 停止定时器
                if status == "finished":
                    # 如果正常结束，调用 on_planning_finished 执行后续处理（数据入库）
                    self.on_planning_finished()

        except requests.exceptions.ConnectionError:
            # 如果轮询时发生连接错误（如网络短暂中断），忽略该次错误，不停止轮询
            pass

