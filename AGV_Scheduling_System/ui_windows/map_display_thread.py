import requests
from PyQt5.QtCore import QThread, pyqtSignal


class MapFetchThread(QThread):
    """后台网络请求线程：向 Flask API 获取渲染好的地图图片"""
    log_signal = pyqtSignal(str)  # 发送文本日志
    finished_signal = pyqtSignal(bytes)  # 发送下载好的图片二进制数据

    def run(self):
        self.log_signal.emit("正在向后台服务器请求工厂拓扑地图 (请稍候)...")
        try:
            # 发起 GET 请求（设置超时时间稍微长一点，因为 MATLAB 启动和画图需要时间）
            # 注意：如果后端部署在其他机器，请替换 127.0.0.1
            response = requests.get("http://127.0.0.1:5000/api/map/generate", timeout=120)

            if response.status_code == 200:
                self.log_signal.emit("地图数据下载成功，正在渲染至界面...")
                # 将图片的二进制数据通过信号发给主界面
                self.finished_signal.emit(response.content)
            else:
                self.log_signal.emit(f"【地图请求失败】: HTTP 状态码 {response.status_code}")

        except Exception as e:
            self.log_signal.emit(f"【网络通信异常】: {str(e)}")