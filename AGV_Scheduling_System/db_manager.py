import pymysql


class DatabaseManager:
    def __init__(self):
        # 请根据您本地的 MySQL 实际情况修改以下参数
        self.host = '127.0.0.1'
        self.port = 3306
        self.user = 'root'  # 您的 MySQL 账号
        self.password = '123456'  # 您的 MySQL 密码
        self.database = 'agv_system_db'

    def get_connection(self):
        """获取数据库连接"""
        try:
            conn = pymysql.connect(
                host=self.host,
                port=self.port,
                user=self.user,
                password=self.password,
                database=self.database,
                charset='utf8mb4',
                cursorclass=pymysql.cursors.DictCursor  # 返回字典格式，方便按列名提取数据
            )
            return conn
        except Exception as e:
            print(f"数据库连接失败: {e}")
            return None

    def execute_query(self, sql, params=None):
        """
        执行查询语句 (SELECT)
        返回查询结果的列表，例如: [{'user_id': 1, 'username': 'admin'}]
        """
        conn = self.get_connection()
        if not conn:
            return []

        try:
            with conn.cursor() as cursor:
                cursor.execute(sql, params)
                result = cursor.fetchall()
                return result
        except Exception as e:
            print(f"查询执行失败: {e}\nSQL: {sql}")
            return []
        finally:
            conn.close()

    def execute_update(self, sql, params=None):
        """
        执行更新语句 (INSERT, UPDATE, DELETE)
        返回受影响的行数
        """
        conn = self.get_connection()
        if not conn:
            return 0

        try:
            with conn.cursor() as cursor:
                affected_rows = cursor.execute(sql, params)
                conn.commit()  # 必须 commit 才能生效
                return affected_rows
        except Exception as e:
            print(f"更新执行失败: {e}\nSQL: {sql}")
            conn.rollback()  # 发生错误时回滚
            return 0
        finally:
            conn.close()
