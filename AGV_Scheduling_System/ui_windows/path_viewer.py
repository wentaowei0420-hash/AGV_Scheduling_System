import json
import os
from PyQt5.QtWidgets import QDialog, QVBoxLayout, QLabel, QHBoxLayout, QComboBox, QPushButton
from PyQt5.QtGui import QPainter, QColor, QPen
from PyQt5.QtCore import Qt


class PathViewerWindow(QDialog):
    def __init__(self, order_id=None, parent=None):
        super().__init__(parent)
        # 设置窗口标题，区分全局浏览和特定订单浏览
        self.setWindowTitle(f"AGV 历史路径浏览" + (f" - 订单 #{order_id}" if order_id else ""))
        self.resize(700, 850)
        self.order_id = order_id
        self.path_coords = []
        self.initUI()

        # 如果初始化时传入了 ID（从任务管理跳转），则直接加载数据
        if self.order_id:
            self.load_path_data()

    def initUI(self):
        # 使用垂直布局管理顶部工具栏
        self.layout = QVBoxLayout(self)

        # 顶部工具栏：如果没有传入特定 ID，允许用户下拉选择
        if not self.order_id:
            top_bar = QHBoxLayout()
            top_bar.addWidget(QLabel("选择已完成订单:"))
            self.combo = QComboBox()
            self.load_completed_orders_to_combo()

            btn = QPushButton("刷新路径")
            btn.clicked.connect(self.load_path_from_combo)

            top_bar.addWidget(self.combo)
            top_bar.addWidget(btn)
            self.layout.addLayout(top_bar)

        # 【核心修改】：删除了原本遮挡绘图区域的 self.canvas QLabel
        # 添加一个伸缩量，将顶部的控制栏固定在上方，下方全部留给 paintEvent 绘图
        self.layout.addStretch()

    def load_completed_orders_to_combo(self):
        """从数据库 MES_ORDERS 获取已完成(status=2)的任务"""
        from db_manager import DatabaseManager
        db = DatabaseManager()
        # 仅查询状态为 2 的已完成订单
        res = db.execute_query("SELECT order_id FROM MES_ORDERS WHERE status = 2 ORDER BY order_id DESC")
        if res:
            for r in res:
                self.combo.addItem(f"订单 #{r['order_id']}", r['order_id'])

    def load_path_from_combo(self):
        """下拉框选择后的回调逻辑"""
        self.order_id = self.combo.currentData()
        self.load_path_data()

    def load_path_data(self):
        """加载 MATLAB 生成的 JSON 轨迹"""
        try:
            # 【路径要求】：严格执行你指定的路径逻辑
            current_dir = os.path.dirname(os.path.abspath(__file__))
            json_path = os.path.join(current_dir, "matlab_code", "task_paths.json")

            if os.path.exists(json_path):
                with open(json_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    # 匹配 MATLAB 导出的 task_N 键名格式
                    self.path_coords = data.get(f"task_{self.order_id}", [])

                # 触发窗口重绘，调用 paintEvent
                self.update()
            else:
                print(f"系统警告：未找到路径文件 -> {json_path}")
        except Exception as e:
            print(f"加载路径失败: {e}")

    def paintEvent(self, event):
        """绘制栅格背景和轨迹实线"""
        painter = QPainter(self)
        # 开启抗锯齿，使路径线条更平滑
        painter.setRenderHint(QPainter.Antialiasing)

        # 绘图参数：格点大小、起始偏移
        grid_size, offset_x, offset_y = 13, 45, 120

        # 1. 绘制背景栅格 (使用浅灰色)
        painter.setPen(QPen(QColor(220, 220, 220), 1))
        for r in range(51):  # 对应地图行数
            for c in range(46):  # 对应地图列数
                painter.drawRect(offset_x + c * grid_size, offset_y + r * grid_size, grid_size, grid_size)

        # 2. 绘制蓝色轨迹 (仅当有坐标数据时绘制)
        if self.path_coords:
            # 设置深蓝色画笔，宽度为 3
            path_pen = QPen(QColor(0, 114, 198), 3, Qt.SolidLine)
            path_pen.setJoinStyle(Qt.RoundJoin)  # 圆润转角
            painter.setPen(path_pen)

            for i in range(len(self.path_coords) - 1):
                # MATLAB [row, col] -> 映射到 Qt [y, x]
                r1, c1 = self.path_coords[i]
                r2, c2 = self.path_coords[i + 1]

                # 计算像素位置：(列-1)*尺寸 为横向偏移，(行-1)*尺寸 为纵向偏移
                # 增加 6 像素补偿，使线条处于格子中心
                painter.drawLine(
                    offset_x + (c1 - 1) * grid_size + 6, offset_y + (r1 - 1) * grid_size + 6,
                    offset_x + (c2 - 1) * grid_size + 6, offset_y + (r2 - 1) * grid_size + 6
                )

            # 3. 额外绘制起点(绿)和终点(红)的小圆点，增加辨识度
            painter.setBrush(QColor(40, 167, 69))  # 起点绿
            sr, sc = self.path_coords[0]
            painter.drawEllipse(offset_x + (sc - 1) * grid_size + 2, offset_y + (sr - 1) * grid_size + 2, 9, 9)

            painter.setBrush(QColor(220, 53, 69))  # 终点红
            er, ec = self.path_coords[-1]
            painter.drawEllipse(offset_x + (ec - 1) * grid_size + 2, offset_y + (er - 1) * grid_size + 2, 9, 9)