import json
import boto3
import psycopg2
import psycopg2.extras
import os
from datetime import datetime
import decimal

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    print("=== API Query Executor Lambda ===")
    print(f"Event: {json.dumps(event, ensure_ascii=False)}")
    
    # CORS対応
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }
    
    try:
        # リクエストボディからSQLを取得
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight OK'})
            }
        
        body = json.loads(event.get('body', '{}'))
        sql_query = body.get('sql', '').strip()
        
        if not sql_query:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'SQLクエリが指定されていません',
                    'usage': {
                        'description': 'POSTボディにJSONで"sql"キーを指定してください',
                        'example': {
                            'sql': 'SELECT * FROM products LIMIT 10;'
                        }
                    }
                }, ensure_ascii=False)
            }
        
        # SELECTのみ許可（セキュリティ対策）
        if not sql_query.upper().strip().startswith('SELECT'):
            return {
                'statusCode': 403,
                'headers': headers,
                'body': json.dumps({
                    'error': 'SELECTクエリのみ実行可能です',
                    'query': sql_query[:50] + '...' if len(sql_query) > 50 else sql_query
                }, ensure_ascii=False)
            }
        
        # 環境変数
        db_host = os.environ['DB_HOST']
        db_port = os.environ['DB_PORT']
        db_name = os.environ['DB_NAME']
        db_user = os.environ['DB_USER']
        db_password = os.environ['DB_PASSWORD']
        
        # データベース接続
        print(f"Connecting to database: {db_host}:{db_port}")
        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=30
        )
        
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        # クエリ実行
        start_time = datetime.now()
        cursor.execute(sql_query)
        results = cursor.fetchall()
        execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
        
        # カラム名取得
        column_names = [desc[0] for desc in cursor.description] if cursor.description else []
        
        cursor.close()
        conn.close()
        
        # 結果を返す
        response_body = {
            'success': True,
            'query': sql_query[:100] + '...' if len(sql_query) > 100 else sql_query,
            'columns': column_names,
            'rows': results,
            'row_count': len(results),
            'execution_time_ms': execution_time_ms,
            'timestamp': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(response_body, ensure_ascii=False, cls=DecimalEncoder)
        }
        
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'データベースエラー',
                'message': str(e),
                'type': 'DatabaseError'
            }, ensure_ascii=False)
        }
        
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': '予期しないエラー',
                'message': str(e),
                'type': type(e).__name__
            }, ensure_ascii=False)
        }
