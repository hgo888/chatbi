# -*- coding: utf-8 -*-
"""
一次性完成：建表 + 导入 Excel 数据 + 添加表和字段的中文注释
运行前提：PostgreSQL 已启动，sales_chat 库已存在
"""
import os
import pandas as pd
import psycopg2

DB = {
    "host": "localhost",
    "port": 5432,
    "user": "postgres",
    "password": "postgres",
    "dbname": "sales_chat",
}

# Excel 数据文件位于项目根目录的 project_data/ 下，用脚本自身位置推算，避免写死本机路径
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "project_data")

# 表定义：表名 -> (excel文件, sheet名, 表注释, {字段名: 字段注释})
TABLES = {
    "food_price_list": {
        "file": "商品表.xlsx", "sheet": "food_price_list",
        "comment": "食品类商品价格表",
        "columns": {"product_no": "商品编号", "product_name": "商品名称", "product_price": "商品单价(元)"},
    },
    "handicraft_price_list": {
        "file": "商品表.xlsx", "sheet": "handicraft_price_list",
        "comment": "手工艺品商品价格表",
        "columns": {"product_no": "商品编号", "product_name": "商品名称", "product_price": "商品单价(元)"},
    },
    "sports_goods_price_list": {
        "file": "商品表.xlsx", "sheet": "sports_goods_price_list",
        "comment": "运动用品商品价格表",
        "columns": {"product_no": "商品编号", "product_name": "商品名称", "product_price": "商品单价(元)"},
    },
    "home_goods_price_list": {
        "file": "商品表.xlsx", "sheet": "home_goods_price_list",
        "comment": "家居用品商品价格表",
        "columns": {"product_no": "商品编号", "product_name": "商品名称", "product_price": "商品单价(元)"},
    },
    "product_monthly_sales_statistic": {
        "file": "销量表.xlsx", "sheet": "product_monthly_sales_statistic",
        "comment": "商品月度销量统计表",
        "columns": {
            "product_name": "商品名称",
            "1月销量": "1月销量", "2月销量": "2月销量", "3月销量": "3月销量",
            "4月销量": "4月销量", "5月销量": "5月销量", "6月销量": "6月销量",
            "7月销量": "7月销量", "8月销量": "8月销量", "9月销量": "9月销量",
            "10月销量": "10月销量", "11月销量": "11月销量", "12月销量": "12月销量",
        },
    },
    "product_reviews": {
        "file": "销量表.xlsx", "sheet": "product_reviews",
        "comment": "商品用户评论表",
        "columns": {"date": "评论日期", "reviews": "评论内容", "stars": "星级评分(1-5)", "product_name": "商品名称"},
    },
    "sales_detail_records_table": {
        "file": "销量表.xlsx", "sheet": "sales_detail_records_table",
        "comment": "销售明细记录表",
        "columns": {"purchase_date": "购买日期", "userid": "用户ID", "product_name": "商品名称", "username": "用户名"},
    },
    "user_information_table": {
        "file": "用户表.xlsx", "sheet": "user_information_table",
        "comment": "用户信息表",
        "columns": {"userid": "用户ID", "username": "用户名", "register_date": "注册日期", "self_description": "个人描述", "occupation": "职业"},
    },
    "user_online_record": {
        "file": "用户表.xlsx", "sheet": "user_online_record",
        "comment": "用户在线时长记录表",
        "columns": {"userid": "用户ID", "load_time": "登录时间", "online_time": "在线时长(分钟)", "username": "用户名"},
    },
}


def infer_sql_type(series):
    """根据 pandas 列推断 PostgreSQL 类型"""
    if series.dtype == "int64":
        return "INTEGER"
    if series.dtype == "float64":
        return "NUMERIC"
    # 日期/时间列统一用 TEXT，简单可靠（本项目 SQL 主要做聚合/过滤）
    return "TEXT"


def main():
    conn = psycopg2.connect(**DB)
    conn.autocommit = True
    cur = conn.cursor()

    for table, meta in TABLES.items():
        df = pd.read_excel(os.path.join(BASE, meta["file"]), sheet_name=meta["sheet"])
        # 统一列名为字符串
        df.columns = [str(c) for c in df.columns]

        # 1) 建表
        col_defs = []
        for col in df.columns:
            col_defs.append(f'"{col}" {infer_sql_type(df[col])}')
        create_sql = f'DROP TABLE IF EXISTS "{table}" CASCADE;\nCREATE TABLE "{table}" ({", ".join(col_defs)});'
        cur.execute(create_sql)

        # 2) 表注释
        cur.execute(f'COMMENT ON TABLE "{table}" IS %s;', (meta["comment"],))

        # 3) 字段注释
        for col, comment in meta["columns"].items():
            if col in df.columns:
                cur.execute(f'COMMENT ON COLUMN "{table}"."{col}" IS %s;', (comment,))

        # 4) 导入数据
        for _, row in df.iterrows():
            cols = '", "'.join(df.columns)
            placeholders = ", ".join(["%s"] * len(df.columns))
            values = [None if pd.isna(v) else v for v in row]
            # float 转 str 避免 NUMERIC 精度问题
            values = [str(v) if isinstance(v, float) else v for v in values]
            insert_sql = f'INSERT INTO "{table}" ("{cols}") VALUES ({placeholders});'
            cur.execute(insert_sql, values)

        print(f"✓ {table}: 建表 + 注释 + 导入 {len(df)} 行完成")

    cur.close()
    conn.close()
    print("\n全部完成！")


if __name__ == "__main__":
    main()
