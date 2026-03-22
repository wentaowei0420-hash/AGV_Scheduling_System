from PyQt5.QtWidgets import (QLabel, QStatusBar)
from PyQt5.QtCore import QTimer, QDateTime

class StatusBarMixin:
    """底部状态栏的通用设置"""

    def setup_status_bar(self):
        # 创建一个 QStatusBar 对象作为状态栏
        self.statusBar = QStatusBar()
        # 将创建的状态栏设置为主窗口的状态栏
        self.setStatusBar(self.statusBar)

        # 创建一个 QLabel 用于显示静态信息（主题、作者、版本）
        info_label = QLabel(" 主题：基于AGV的转向架组装生产线配件输送系统 | 制作者：wentao_wei | 版本：1.0.0 | ")
        # 将静态信息标签添加到状态栏的左侧（普通部件）
        self.statusBar.addWidget(info_label)

        # 创建一个 QLabel 用于动态显示当前时间，保存为实例变量以便后续更新
        self.time_label = QLabel()
        # 将时间标签添加到状态栏的最右侧（永久部件），不会被临时消息覆盖
        self.statusBar.addPermanentWidget(self.time_label)

        # 创建一个定时器，每隔1秒触发一次，用于更新时间显示
        self.timer = QTimer(self)
        # 连接定时器的 timeout 信号到更新时间的方法
        self.timer.timeout.connect(self.update_time)
        # 启动定时器，间隔为1000毫秒（1秒）
        self.timer.start(1000)
        # 立即调用一次更新时间方法，避免启动后等待1秒才显示时间
        self.update_time()

    def update_time(self):
        # 获取当前日期时间，并格式化为包含星期、年月日时分秒的字符串
        current_time = QDateTime.currentDateTime().toString("时间：dddd - yyyy-MM-dd HH:mm:ss")
        # 将格式化后的时间字符串设置到时间标签上
        self.time_label.setText(current_time)