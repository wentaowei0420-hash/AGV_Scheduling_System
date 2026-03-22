import sys
import os
import win32gui
import win32con
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QLabel, QTabWidget, QGroupBox, QFileDialog,
                             QLineEdit, QPushButton, QVBoxLayout, QHBoxLayout,
                             QGridLayout, QFrame, QMessageBox, QTextEdit, QStatusBar,
                             QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QSpinBox, QComboBox)
from PyQt5.QtGui import QPixmap, QFont, QIcon, QColor, QPalette
from PyQt5.QtCore import Qt, QTimer, QDateTime,QThread, pyqtSignal
from db_manager import DatabaseManager
from ui_windows.map_display_thread import MapFetchThread

class MapInfoWindow(QMainWindow):
    """地图信息管理窗口类，继承自QMainWindow，用于显示和管理MATLAB绘制的工厂静态拓扑图"""

    def __init__(self, parent=None):
        """构造函数：初始化窗口属性、界面、线程和定时器"""
        super().__init__(parent)                     # 调用父类构造函数，传入父窗口参数
        self.setWindowTitle("地图信息管理 - 静态拓扑图")  # 设置窗口标题
        self.resize(1000, 750)                        # 设置窗口初始尺寸（宽1000，高750）

        self.matlab_hwnd = None                        # 存储MATLAB窗口的句柄（HWND），初始为空
        self.initUI()                                  # 调用初始化界面的方法

        # 启动后台线程加载地图
        self.map_thread = MapDisplayThread()           # 创建地图显示线程对象（自定义线程类）
        # 连接线程的日志信号到append_log方法，用于在线程中输出日志信息到界面
        self.map_thread.log_signal.connect(self.append_log)
        self.map_thread.start()                         # 启动线程（执行线程的run方法）

        # 启动定时器，用于捕获 MATLAB 弹出的名为 'FactoryMapDisplayWindow' 的窗口
        self.capture_timer = QTimer()                   # 创建定时器对象
        self.capture_timer.timeout.connect(self.capture_matlab_window)  # 定时器超时连接捕获方法
        self.capture_timer.start(500)                    # 启动定时器，每500毫秒触发一次

    def initUI(self):
        """初始化用户界面：创建主布局、地图容器和底部操作区域"""
        central_widget = QWidget()                       # 创建一个中心部件
        self.setCentralWidget(central_widget)            # 将中心部件设置为主窗口的中心区域
        main_layout = QVBoxLayout(central_widget)         # 为中心部件创建垂直布局

        # 上半部分：用来内嵌 MATLAB 地图的容器
        self.map_container = QFrame()                     # 创建一个QFrame作为地图容器
        # 设置容器样式：深色背景（#2b2b2b），灰色边框
        self.map_container.setStyleSheet("background-color: #2b2b2b; border: 2px solid #555;")
        main_layout.addWidget(self.map_container, 5)       # 将容器加入主布局，拉伸因子为5（占据主要空间）

        # 下半部分：操作与日志输出（水平布局）
        bottom_layout = QHBoxLayout()                      # 创建水平布局

        self.log_output = QTextEdit()                       # 创建文本编辑框用于显示日志
        self.log_output.setReadOnly(True)                   # 设置为只读模式
        self.log_output.setMaximumHeight(100)                # 设置最大高度为100像素
        # 设置日志框样式：浅紫色背景，微软雅黑字体
        self.log_output.setStyleSheet("background-color: #F8F8FF; font-family: Microsoft YaHei;")
        bottom_layout.addWidget(self.log_output)             # 将日志框加入底部水平布局

        self.close_btn = QPushButton("关闭地图")              # 创建关闭按钮
        self.close_btn.setFixedSize(120, 100)                 # 设置按钮固定大小为120x100像素
        # 设置按钮样式：红色背景，白色加粗文字，字号14px
        self.close_btn.setStyleSheet("background-color: #ff6666; color: white; font-weight: bold; font-size: 14px;")
        self.close_btn.clicked.connect(self.close)            # 点击按钮时关闭窗口（调用close方法）
        bottom_layout.addWidget(self.close_btn)                # 将按钮加入底部水平布局

        main_layout.addLayout(bottom_layout, 1)                # 将底部布局加入主垂直布局，拉伸因子为1

    def append_log(self, text):
        """向日志输出区域追加文本，并自动滚动到底部"""
        self.log_output.append(text)                           # 在文本编辑框末尾添加文本
        # 获取垂直滚动条，并将滑块位置设置到最大值，实现自动滚动到底部
        self.log_output.verticalScrollBar().setValue(self.log_output.verticalScrollBar().maximum())

    def capture_matlab_window(self):
        """寻找MATLAB地图窗口并嵌入到map_container中"""
        hwnds = []                                             # 用于存储找到的符合条件窗口句柄的列表

        def enum_windows_callback(hwnd, extra):
            """EnumWindows的回调函数，枚举所有顶级窗口，检查窗口标题"""
            title = win32gui.GetWindowText(hwnd)               # 获取窗口标题
            # 如果标题包含 "FactoryMapDisplayWindow"（线程中强制重命名的窗口），则加入列表
            if "FactoryMapDisplayWindow" in title:
                hwnds.append(hwnd)
            return True                                         # 返回True继续枚举

        win32gui.EnumWindows(enum_windows_callback, None)      # 枚举所有顶级窗口

        if hwnds:                                               # 如果找到了符合条件的窗口
            self.matlab_hwnd = hwnds[0]                         # 取第一个句柄
            self.capture_timer.stop()                            # 停止定时器（已经找到窗口）
            self.append_log("系统提示：成功捕获 MATLAB 地图，正在嵌入...")

            # 设置父窗口，实现内嵌
            container_hwnd = int(self.map_container.winId())    # 获取map_container的窗口句柄（HWND）
            win32gui.SetParent(self.matlab_hwnd, container_hwnd)  # 将MATLAB窗口的父窗口设为容器

            # 去除 MATLAB 窗口的标题栏和边框
            style = win32gui.GetWindowLong(self.matlab_hwnd, win32con.GWL_STYLE)  # 获取当前窗口样式
            style = style & ~win32con.WS_OVERLAPPEDWINDOW       # 移除WS_OVERLAPPEDWINDOW风格（去掉标题栏、边框等）
            win32gui.SetWindowLong(self.matlab_hwnd, win32con.GWL_STYLE, style)  # 设置新样式

            # 调用resizeEvent手动触发一次大小调整，使MATLAB窗口适应容器当前大小
            self.resizeEvent(None)

    def resizeEvent(self, event):
        """重写窗口大小改变事件，当窗口调整大小时，同步调整嵌入的MATLAB窗口大小"""
        super().resizeEvent(event)                              # 调用父类的resizeEvent（可选）
        if self.matlab_hwnd:                                    # 如果MATLAB窗口句柄存在
            rect = self.map_container.rect()                    # 获取容器的矩形区域（相对于父窗口）
            # 移动并调整MATLAB窗口：移动到(0,0)相对于容器，宽度和高度设置为容器的宽度和高度
            win32gui.MoveWindow(self.matlab_hwnd, 0, 0, rect.width(), rect.height(), True)

    def closeEvent(self, event):
        """重写窗口关闭事件，关闭时退出MATLAB引擎，释放资源"""
        if self.map_thread.engine:                               # 如果线程中存在MATLAB引擎对象
            self.append_log("正在关闭 MATLAB 引擎...")
            try:
                self.map_thread.engine.quit()                    # 尝试退出MATLAB引擎
            except:
                pass                                             # 忽略可能出现的异常
        event.accept()                                            # 接受关闭事件，允许窗口关闭