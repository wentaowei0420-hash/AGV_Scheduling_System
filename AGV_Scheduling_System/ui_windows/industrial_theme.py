GLOBAL_STYLESHEET = """
QWidget {
    background-color: #E7EDF3;
    color: #17212B;
    font-family: 'Microsoft YaHei';
    font-size: 10.5pt;
}

QMainWindow, QDialog {
    background-color: #E7EDF3;
}

QFrame#Panel,
QFrame#Card,
QFrame#NavPanel,
QFrame#BrandPanel,
QFrame#FormPanel,
QFrame#StatusCard {
    background-color: #FDFEFF;
    border: 1px solid #CAD5E2;
    border-radius: 6px;
}

QFrame#BrandPanel {
    background-color: #16232F;
    border: 1px solid #223547;
}

QFrame#HeaderStrip {
    background-color: #0F1B26;
    border: 1px solid #243647;
    border-radius: 6px;
}

QLabel#WindowTitle {
    color: #11283A;
    font-size: 16pt;
    font-weight: 700;
}

QLabel#SectionTitle {
    color: #20384D;
    font-size: 11.5pt;
    font-weight: 700;
}

QLabel#MutedText {
    color: #5D7286;
}

QLabel#BrandTitle {
    color: #F4F7FA;
    font-size: 18pt;
    font-weight: 700;
    background: transparent;
}

QLabel#BrandSubtitle {
    color: #AABBCB;
    font-size: 10pt;
    background: transparent;
}

QLabel#MetricTitle {
    color: #5B6D7E;
    font-size: 9pt;
    font-weight: 600;
    background: transparent;
}

QLabel#MetricValue {
    color: #13212E;
    font-size: 16pt;
    font-weight: 700;
    background: transparent;
}

QLabel#BadgeNeutral,
QLabel#BadgeInfo,
QLabel#BadgeSuccess,
QLabel#BadgeWarning,
QLabel#BadgeDanger {
    padding: 5px 10px;
    border-radius: 10px;
    font-size: 9pt;
    font-weight: 700;
}

QLabel#BadgeNeutral {
    background-color: #DCE5EE;
    color: #334E68;
}

QLabel#BadgeInfo {
    background-color: #D7E8F6;
    color: #1F5F8B;
}

QLabel#BadgeSuccess {
    background-color: #DDEEE5;
    color: #2D6A4F;
}

QLabel#BadgeWarning {
    background-color: #F8E9C9;
    color: #9A6700;
}

QLabel#BadgeDanger {
    background-color: #F6D6D6;
    color: #B42318;
}

QPushButton {
    background-color: #F7FAFC;
    border: 1px solid #BBC9D8;
    border-radius: 4px;
    color: #17212B;
    padding: 8px 14px;
    font-weight: 600;
}

QPushButton:hover {
    background-color: #ECF2F7;
    border-color: #9CB1C6;
}

QPushButton:pressed {
    background-color: #DDE6EF;
}

QPushButton#PrimaryButton {
    background-color: #1F5F8B;
    border: 1px solid #1F5F8B;
    color: #FFFFFF;
}

QPushButton#PrimaryButton:hover {
    background-color: #174D72;
}

QPushButton#DangerButton {
    background-color: #FFF4F2;
    border: 1px solid #E7B4AE;
    color: #B42318;
}

QPushButton#DangerButton:hover {
    background-color: #FCE8E6;
}

QPushButton#NavButton {
    text-align: left;
    padding: 11px 14px;
    border-radius: 4px;
}

QPushButton#PrimaryNavButton {
    text-align: left;
    padding: 11px 14px;
    border-radius: 4px;
    background-color: #1F5F8B;
    border: 1px solid #1F5F8B;
    color: #FFFFFF;
}

QPushButton#PrimaryNavButton:hover {
    background-color: #174D72;
}

QLineEdit,
QComboBox,
QSpinBox,
QTextEdit,
QPlainTextEdit {
    background-color: #FFFFFF;
    border: 1px solid #B9C6D3;
    border-radius: 4px;
    padding: 8px 10px;
    selection-background-color: #1F5F8B;
}

QLineEdit:focus,
QComboBox:focus,
QSpinBox:focus,
QTextEdit:focus,
QPlainTextEdit:focus {
    border: 1px solid #1F5F8B;
}

QTableWidget,
QListWidget {
    background-color: #FFFFFF;
    alternate-background-color: #F6F9FC;
    border: 1px solid #C9D5E1;
    border-radius: 4px;
    gridline-color: #D8E0E8;
}

QHeaderView::section {
    background-color: #DDE6EF;
    color: #20384D;
    padding: 8px;
    border: none;
    border-right: 1px solid #C3CFDA;
    border-bottom: 1px solid #C3CFDA;
    font-weight: 700;
}

QTabWidget::pane {
    border: 1px solid #CAD5E2;
    background: #FDFEFF;
    border-radius: 6px;
}

QTabBar::tab {
    background: #DDE6EF;
    color: #334E68;
    padding: 9px 16px;
    margin-right: 2px;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
}

QTabBar::tab:selected {
    background: #FDFEFF;
    color: #1F5F8B;
    font-weight: 700;
}

QStatusBar {
    background-color: #11212F;
    color: #D7E3EE;
    border-top: 1px solid #294255;
}

QStatusBar QLabel {
    background: transparent;
    color: #D7E3EE;
}

QScrollBar:vertical {
    background: #E1E8EF;
    width: 10px;
    margin: 0px;
}

QScrollBar::handle:vertical {
    background: #A3B4C5;
    border-radius: 5px;
    min-height: 20px;
}

QScrollBar::add-line:vertical,
QScrollBar::sub-line:vertical {
    background: none;
    border: none;
}
"""
