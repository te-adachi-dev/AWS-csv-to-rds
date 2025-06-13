import json
import boto3
import psycopg2
import os
import re
import traceback

def lambda_handler(event, context):
    print("=== テーブル作成Lambda関数開始 ===")
    print(f"Event: {json.dumps(event, ensure_ascii=False)}")
    
    s3_client = boto3.client('s3')
    
    db_host = os.environ['DB_HOST']
    db_port = os.environ['DB_PORT']
    db_name = os.environ['DB_NAME']
    db_user = os.environ['DB_USER']
    db_password = os.environ['DB_PASSWORD']
    s3_bucket = os.environ['S3_BUCKET']
    sql_prefix = os.environ.get('SQL_PREFIX', 'init-sql/')
    
    created_tables = []
    failed_tables = []
    
    try:
        # S3からSQLファイル一覧を取得
        print(f"S3バケット '{s3_bucket}' の '{sql_prefix}' 以下のSQLファイルを検索中...")
        
        try:
            response = s3_client.list_objects_v2(
                Bucket=s3_bucket,
                Prefix=sql_prefix
            )
        except Exception as e:
            print(f"S3アクセスエラー: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': f"S3バケット '{s3_bucket}' にアクセスできません: {str(e)}"
                }, ensure_ascii=False)
            }
        
        if 'Contents' not in response:
            print("SQLファイルが見つかりません")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'warning': f"S3バケット '{s3_bucket}/{sql_prefix}' にSQLファイルが見つかりません",
                    'created_tables': [],
                    'failed_tables': []
                }, ensure_ascii=False)
            }
        
        sql_files = [obj['Key'] for obj in response['Contents'] 
                    if obj['Key'].endswith('.sql')]
        
        print(f"見つかったSQLファイル: {len(sql_files)}個")
        for sql_file in sql_files:
            print(f"  - {sql_file}")
        
        if not sql_files:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'warning': f"SQLファイル（.sql）が見つかりません",
                    'created_tables': [],
                    'failed_tables': []
                }, ensure_ascii=False)
            }
        
        # データベース接続
        print(f"データベース接続中: {db_host}:{db_port}")
        
        try:
            conn = psycopg2.connect(
                host=db_host,
                port=int(db_port),
                database=db_name,
                user=db_user,
                password=db_password,
                connect_timeout=30
            )
            
            conn.autocommit = True
            cursor = conn.cursor()
            print("データベース接続成功")
            
        except Exception as e:
            print(f"データベース接続エラー: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': f"データベース接続失敗: {str(e)}"
                }, ensure_ascii=False)
            }
        
        # 各SQLファイルを処理
        for sql_file in sql_files:
            try:
                print(f"\n=== 処理中: {sql_file} ===")
                
                # S3からSQLファイルを取得
                s3_response = s3_client.get_object(Bucket=s3_bucket, Key=sql_file)
                sql_content = s3_response['Body'].read().decode('utf-8')
                
                print(f"SQLファイル読み込み完了: {len(sql_content)}文字")
                
                # SQLを実行
                # セミコロンで分割して複数のSQL文を処理
                sql_statements = [stmt.strip() for stmt in sql_content.split(';') 
                                if stmt.strip() and not stmt.strip().startswith('--')]
                
                table_names = []
                for i, sql_statement in enumerate(sql_statements):
                    if sql_statement:
                        print(f"SQL実行 {i+1}/{len(sql_statements)}: {sql_statement[:150]}...")
                        
                        # CREATE TABLE文からテーブル名を抽出
                        create_match = re.search(
                            r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[`"]?(\w+)[`"]?\.)?[`"]?(\w+)[`"]?', 
                            sql_statement, re.IGNORECASE | re.DOTALL
                        )
                        if create_match:
                            table_name = create_match.group(2)
                            if table_name not in table_names:
                                table_names.append(table_name)
                        
                        cursor.execute(sql_statement)
                        print(f"SQL実行成功: {i+1}")
                
                if table_names:
                    created_tables.extend(table_names)
                    print(f"✅ テーブル作成完了: {table_names}")
                else:
                    print(f"⚠️ 警告: {sql_file} からテーブル名を抽出できませんでした")
                    
            except Exception as e:
                error_msg = f"SQLファイル '{sql_file}' の処理でエラー: {str(e)}"
                print(f"❌ {error_msg}")
                print(f"詳細エラー: {traceback.format_exc()}")
                failed_tables.append({
                    'file': sql_file,
                    'error': str(e)
                })
        
        # 作成済みテーブル一覧を確認
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            ORDER BY table_name;
        """)
        
        all_tables = cursor.fetchall()
        all_table_list = [table[0] for table in all_tables]
        
        print(f"\n=== 最終結果 ===")
        print(f"処理対象SQLファイル: {len(sql_files)}個")
        print(f"作成成功テーブル: {len(created_tables)}個 -> {created_tables}")
        print(f"作成失敗ファイル: {len(failed_tables)}個")
        print(f"データベース内全テーブル: {len(all_table_list)}個 -> {all_table_list}")
        
        if failed_tables:
            print(f"失敗詳細:")
            for fail in failed_tables:
                print(f"  - {fail['file']}: {fail['error']}")
        
        cursor.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'テーブル作成完了: 成功{len(created_tables)}個, 失敗{len(failed_tables)}個',
                'created_tables': created_tables,
                'failed_tables': failed_tables,
                'all_tables': all_table_list,
                'sql_files_processed': len(sql_files),
                'success_count': len(created_tables),
                'failed_count': len(failed_tables)
            }, ensure_ascii=False)
        }
        
    except Exception as e:
        error_msg = f"テーブル作成でエラー: {str(e)}"
        print(f"❌ {error_msg}")
        print(f"詳細エラー: {traceback.format_exc()}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'created_tables': created_tables,
                'failed_tables': failed_tables
            }, ensure_ascii=False)
        }