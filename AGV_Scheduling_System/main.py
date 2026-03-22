import sys
import traceback

from PyQt5.QtGui import QFont
from PyQt5.QtWidgets import QApplication

from ui_windows.industrial_theme import GLOBAL_STYLESHEET
from ui_windows.login_window_mes import LoginWindow


def my_excepthook(exc_type, exc_value, exc_traceback):
    print("===== 拦截到导致崩溃的致命异常 =====")
    traceback.print_exception(exc_type, exc_value, exc_traceback)
    print("====================================")


sys.excepthook = my_excepthook


def main():
    app = QApplication(sys.argv)
    app.setFont(QFont("Microsoft YaHei", 10))
    app.setStyleSheet(GLOBAL_STYLESHEET)

    login_win = LoginWindow()
    login_win.show()

    sys.exit(app.exec_())


if __name__ == '__main__':
    main()
