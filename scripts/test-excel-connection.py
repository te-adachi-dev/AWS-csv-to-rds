#!/usr/bin/env python3
"""
ExcelからRDSへの接続テスト（IAM認証）
"""

import boto3
import psycopg2
import pandas as pd
import json
import subprocess
import sys

def get_terraform_output(key):
    """Terraformのアウトプットから値を取得"""
    result = subprocess.run(
        ["terraform", "output", "-raw", key],
        cwd="terraform",
        capture_output=True,
        text=True
    )
    return result.stdout.strip()

def generate_auth_token(hostname, port, username, region):
    """IAM認証トークンを生成"""
    client = boto3.client('rds', region_name=region)
    token = client.generate_db_auth_token(
        DBHostname=hostname,
        Port=port,
        DBUsername=username
    )
    return token

def test_connection(username, query="SELECT * FROM accounts LIMIT 5"):
    """指定されたユーザーで接続テスト"""
    # Terraform outputから情報取得
    hostname = get_terraform_output("rds_endpoint")
    port = int(get_terraform_output("rds_port"))
    
    # リージョンを取得
    vpc_id = get_terraform_output("vpc_id")
    region = vpc_id.split(":")[3]
    
    # 認証トークンを生成
    token = generate_auth_token(hostname, port, username, region)
    
    # 接続
    conn = None
    try:
        conn = psycopg2.connect(
            host=hostname,
            port=port,
            database="postgres",
            user=username,
            password=token,
            sslmode='require'
        )
        
        # クエリ実行
        df = pd.read_sql_query(query, conn)
        print(f"ユーザー {username} で接続成功！")
        print(f"取得したデータ:\n{df}")
        
        return df
        
    except Exception as e:
        print(f"エラー: {e}")
        return None
        
    finally:
        if conn:
            conn.close()

def export_to_excel(dataframes, filename="rds_test_results.xlsx"):
    """結果をExcelファイルに出力"""
    with pd.ExcelWriter(filename) as writer:
        for sheet_name, df in dataframes.items():
            if df is not None:
                df.to_excel(writer, sheet_name=sheet_name, index=False)
    print(f"結果を {filename} に保存しました")

if __name__ == "__main__":
    print("=== Excel連携テスト ===")
    
    # 各ユーザーでテスト
    results = {}
    
    # 読み取り専用ユーザー
    results["ReadOnly_User"] = test_connection("test_readonly")
    
    # フルアクセスユーザー
    results["FullAccess_User"] = test_connection("test_fullaccess")
    
    # 制限付きユーザー（accountsテーブルのみ）
    results["Limited_User"] = test_connection("test_limited")
    
    # Excelに出力
    export_to_excel(results)
