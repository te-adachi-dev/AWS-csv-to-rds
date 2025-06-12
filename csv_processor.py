import json
import boto3
import psycopg2
import psycopg2.extras
import csv
import io
import os
from urllib.parse import unquote_plus
from datetime import datetime

def lambda_handler(event, context):
    print("=== CSV処理Lambda関数開始 ===")
    print(f"Event: {json.dumps(event, ensure_ascii=False)}")

    s3_client = boto3.client('s3')

    db_host = os.environ['DB_HOST']
    db_port = os.environ['DB_PORT']
    db_name = os.environ['DB_NAME']
    db_user = os.environ['DB_USER']
    db_password = os.environ['DB_PASSWORD']

    try:
        # S3イベントから情報取得
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        object_key = unquote_plus(event['Records'][0]['s3']['object']['key'])

        print(f"処理対象ファイル: s3://{bucket_name}/{object_key}")

        # CSVファイルを取得
        s3_response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        csv_content = s3_response['Body'].read().decode('utf-8')

        csv_reader = csv.DictReader(io.StringIO(csv_content))
        rows = list(csv_reader)

        if not rows:
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'CSVファイルにデータがありません'}, ensure_ascii=False)
            }

        # ファイル名からテーブル名を決定
        file_name = object_key.split('/')[-1]
        table_name = file_name.replace('.csv', '').lower()
        table_name = ''.join(c for c in table_name if c.isalnum() or c == '_')
        
        # 日付を含むテーブル名の生成
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        table_name = f"{table_name}_{timestamp}"

        print(f"対象テーブル: {table_name}")

        # データベース接続
        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=30
        )

        conn.autocommit = False
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # CSVの列からテーブル定義を動的作成
        columns = list(rows[0].keys())
        column_definitions = []
        safe_columns = []
        
        for col in columns:
            safe_col = ''.join(c for c in col if c.isalnum() or c == '_')
            if not safe_col:
                safe_col = f"column_{len(column_definitions)}"
            safe_columns.append(safe_col)
            column_definitions.append(f'"{safe_col}" TEXT')

        # テーブル作成
        create_table_sql = f"""
            CREATE TABLE IF NOT EXISTS "{table_name}" (
                id SERIAL PRIMARY KEY,
                {', '.join(column_definitions)},
                file_source VARCHAR(500),
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """

        print(f"テーブル作成SQL: {create_table_sql}")
        cursor.execute(create_table_sql)

        # データ挿入
        column_names = ', '.join([f'"{col}"' for col in safe_columns])
        placeholders = ', '.join(['%s'] * (len(safe_columns) + 1))  # +1 for file_source
        insert_sql = f'INSERT INTO "{table_name}" ({column_names}, file_source) VALUES ({placeholders})'

        total_inserted = 0
        failed_rows = 0
        
        for i, row in enumerate(rows):
            try:
                values = []
                for original_col in columns:
                    value = row.get(original_col, '')
                    if value == '':
                        values.append(None)
                    else:
                        values.append(str(value))
                
                # ファイルソース情報を追加
                values.append(f"s3://{bucket_name}/{object_key}")
                
                cursor.execute(insert_sql, values)
                total_inserted += 1
                
                if (i + 1) % 100 == 0:
                    print(f"処理中: {i + 1}/{len(rows)} 行")
                    
            except Exception as e:
                failed_rows += 1
                print(f"行 {i+1} の処理でエラー: {e}")

        conn.commit()
        
        # 処理結果確認
        cursor.execute(f'SELECT COUNT(*) FROM "{table_name}"')
        final_count = cursor.fetchone()[0]
        
        cursor.close()
        conn.close()

        success_message = f"CSV処理完了: {total_inserted}行挿入, {failed_rows}行失敗, テーブル '{table_name}' 最終行数: {final_count}"
        print(success_message)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': success_message,
                'table_name': table_name,
                'source_file': f"s3://{bucket_name}/{object_key}",
                'total_rows': len(rows),
                'inserted_rows': total_inserted,
                'failed_rows': failed_rows,
                'final_table_count': final_count,
                'columns': safe_columns
            }, ensure_ascii=False)
        }

    except Exception as e:
        print(f"CSV処理エラー: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'CSV処理エラー: {str(e)}',
                'source_file': f"s3://{bucket_name}/{object_key}" if 'bucket_name' in locals() else 'unknown'
            }, ensure_ascii=False)
        }