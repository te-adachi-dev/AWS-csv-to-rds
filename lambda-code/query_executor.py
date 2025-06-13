import json
import boto3
import psycopg2
import psycopg2.extras
import csv
import io
import os
from datetime import datetime

def lambda_handler(event, context):
    print("=== 運用SQL実行Lambda関数開始 ===")
    print(f"Event: {json.dumps(event, ensure_ascii=False)}")

    s3_client = boto3.client('s3')

    db_host = os.environ['DB_HOST']
    db_port = os.environ['DB_PORT']
    db_name = os.environ['DB_NAME']
    db_user = os.environ['DB_USER']
    db_password = os.environ['DB_PASSWORD']
    s3_bucket = os.environ['S3_BUCKET']
    output_prefix = os.environ.get('OUTPUT_PREFIX', 'query-results/')

    try:
        # イベントからSQLクエリを取得
        if 'sql' not in event:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'SQLクエリが指定されていません',
                    'usage': {
                        'description': 'eventパラメータに"sql"キーでSQLクエリを指定してください',
                        'example': {
                            'sql': 'SELECT * FROM test20250611 LIMIT 10;',
                            'output_format': 'csv',  # csv または json
                            'output_name': 'test_result'  # 省略可能
                        }
                    }
                }, ensure_ascii=False)
            }

        sql_query = event['sql'].strip()
        output_format = event.get('output_format', 'csv').lower()
        output_name = event.get('output_name', f'query_result_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

        print(f"実行SQL: {sql_query[:200]}...")
        print(f"出力形式: {output_format}")
        print(f"出力名: {output_name}")

        # データベース接続
        print(f"データベース接続中: {db_host}:{db_port}")
        
        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=30
        )

        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        print("データベース接続成功")

        # SQLクエリ実行
        start_time = datetime.now()
        cursor.execute(sql_query)
        
        # SELECT文の場合は結果を取得
        if sql_query.strip().upper().startswith('SELECT'):
            results = cursor.fetchall()
            column_names = [desc[0] for desc in cursor.description] if cursor.description else []
            rows_count = len(results)
            
            print(f"クエリ実行完了: {rows_count}行取得")
            
            if rows_count == 0:
                print("結果が0行のため、S3出力をスキップします")
                cursor.close()
                conn.close()
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'クエリ実行完了（結果0行）',
                        'rows_count': 0,
                        'columns': column_names,
                        'execution_time_ms': int((datetime.now() - start_time).total_seconds() * 1000)
                    }, ensure_ascii=False)
                }
            
            # 結果をS3に出力
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            
            if output_format == 'csv':
                # CSV形式で出力
                output_key = f"{output_prefix}{output_name}_{timestamp}.csv"
                csv_buffer = io.StringIO()
                csv_writer = csv.writer(csv_buffer)
                
                # ヘッダー書き込み
                csv_writer.writerow(column_names)
                
                # データ書き込み
                for row in results:
                    csv_writer.writerow([
                        str(value) if value is not None else '' 
                        for value in row
                    ])
                
                csv_content = csv_buffer.getvalue()
                s3_client.put_object(
                    Bucket=s3_bucket,
                    Key=output_key,
                    Body=csv_content.encode('utf-8'),
                    ContentType='text/csv'
                )
                
            elif output_format == 'json':
                # JSON形式で出力
                output_key = f"{output_prefix}{output_name}_{timestamp}.json"
                
                # RealDictCursorの結果をJSONシリアライズ可能な形式に変換
                json_results = []
                for row in results:
                    json_row = {}
                    for key, value in row.items():
                        # datetime等の特殊型をstr変換
                        if value is not None and hasattr(value, 'isoformat'):
                            json_row[key] = value.isoformat()
                        else:
                            json_row[key] = value
                    json_results.append(json_row)
                
                json_content = json.dumps({
                    'query': sql_query,
                    'execution_time': datetime.now().isoformat(),
                    'rows_count': rows_count,
                    'columns': column_names,
                    'data': json_results
                }, ensure_ascii=False, indent=2)
                
                s3_client.put_object(
                    Bucket=s3_bucket,
                    Key=output_key,
                    Body=json_content.encode('utf-8'),
                    ContentType='application/json'
                )
            
            else:
                cursor.close()
                conn.close()
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': f'サポートされていない出力形式: {output_format}',
                        'supported_formats': ['csv', 'json']
                    }, ensure_ascii=False)
                }
            
            cursor.close()
            conn.close()
            
            execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'クエリ実行・出力完了',
                    'query': sql_query[:100] + '...' if len(sql_query) > 100 else sql_query,
                    'rows_count': rows_count,
                    'columns': column_names,
                    'output_location': f"s3://{s3_bucket}/{output_key}",
                    'output_format': output_format,
                    'execution_time_ms': execution_time_ms
                }, ensure_ascii=False)
            }
        
        else:
            # INSERT/UPDATE/DELETE等の場合
            affected_rows = cursor.rowcount
            conn.commit()
            cursor.close()
            conn.close()
            
            execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'クエリ実行完了',
                    'query': sql_query[:100] + '...' if len(sql_query) > 100 else sql_query,
                    'affected_rows': affected_rows,
                    'execution_time_ms': execution_time_ms
                }, ensure_ascii=False)
            }

    except psycopg2.Error as e:
        print(f"データベースエラー: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'データベースエラー: {str(e)}',
                'query': sql_query[:100] + '...' if 'sql_query' in locals() and len(sql_query) > 100 else sql_query if 'sql_query' in locals() else 'unknown'
            }, ensure_ascii=False)
        }
    
    except Exception as e:
        print(f"SQL実行エラー: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'SQL実行エラー: {str(e)}',
                'query': sql_query[:100] + '...' if 'sql_query' in locals() and len(sql_query) > 100 else sql_query if 'sql_query' in locals() else 'unknown'
            }, ensure_ascii=False)
        }