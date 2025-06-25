import json
import boto3
import psycopg2
import psycopg2.extras
import csv
import io
import os
import re
from urllib.parse import unquote_plus
from datetime import datetime

def parse_postgres_error(error, row_data, column_info):
    """PostgreSQLのエラーメッセージを解析して構造化された情報を返す"""
    error_info = {
        'error_type': 'UNKNOWN',
        'error_code': getattr(error, 'pgcode', 'UNKNOWN'),
        'error_message': str(error),
        'affected_columns': [],
        'details': []
    }
    
    error_msg = str(error)
    
    # NOT NULL制約違反
    null_matches = re.findall(r'null value in column "([^"]+)" violates not-null constraint', error_msg)
    if null_matches:
        error_info['error_type'] = 'NOT_NULL_VIOLATION'
        for col in null_matches:
            error_info['affected_columns'].append(col)
            error_info['details'].append(f"カラム '{col}' にNULL値は許可されていません")
    
    # 主キー・一意制約重複
    pk_match = re.search(r'duplicate key value violates unique constraint "([^"]+)".*Key \(([^)]+)\)=\(([^)]+)\)', error_msg)
    if pk_match:
        constraint_name = pk_match.group(1)
        key_columns = pk_match.group(2)
        key_values = pk_match.group(3)
        
        # 制約名から種類を判定
        if 'pk' in constraint_name.lower() or 'pkey' in constraint_name.lower():
            error_info['error_type'] = 'PRIMARY_KEY_VIOLATION'
        else:
            error_info['error_type'] = 'UNIQUE_CONSTRAINT_VIOLATION'
        
        error_info['affected_columns'].append(key_columns)
        error_info['details'].append(f"制約 '{constraint_name}' 違反: キー({key_columns})=({key_values}) は既に存在します")
    
    # 外部キー制約違反
    fk_match = re.search(r'violates foreign key constraint "([^"]+)".*Key \(([^)]+)\)=\(([^)]+)\) is not present', error_msg)
    if fk_match:
        error_info['error_type'] = 'FOREIGN_KEY_VIOLATION'
        constraint_name = fk_match.group(1)
        key_columns = fk_match.group(2)
        key_values = fk_match.group(3)
        error_info['affected_columns'].append(key_columns)
        error_info['details'].append(f"外部キー制約 '{constraint_name}' 違反: 参照先に値({key_values})が存在しません")
    
    # データ型不一致
    type_matches = re.findall(r'invalid input syntax for type (\w+): "([^"]+)"', error_msg)
    if type_matches:
        error_info['error_type'] = 'DATA_TYPE_MISMATCH'
        for data_type, value in type_matches:
            # どのカラムでエラーが発生したか推測
            for col, col_info in column_info.items():
                if col in row_data and str(row_data[col]) == value:
                    error_info['affected_columns'].append(col)
                    error_info['details'].append(f"カラム '{col}' (型: {data_type}): 値 '{value}' は無効な形式です")
                    break
    
    # 文字列長超過
    length_match = re.search(r'value too long for type character varying\((\d+)\)', error_msg)
    if length_match:
        error_info['error_type'] = 'STRING_LENGTH_EXCEEDED'
        max_length = length_match.group(1)
        # 長すぎる値を持つカラムを特定
        for col, value in row_data.items():
            if value and len(str(value)) > int(max_length):
                error_info['affected_columns'].append(col)
                error_info['details'].append(f"カラム '{col}': 値の長さ {len(str(value))} が最大長 {max_length} を超過")
    
    # 数値オーバーフロー
    overflow_match = re.search(r'numeric field overflow', error_msg)
    if overflow_match:
        error_info['error_type'] = 'NUMERIC_OVERFLOW'
        error_info['details'].append("数値が許容範囲を超えています")
    
    # CHECK制約違反
    check_match = re.search(r'new row for relation "([^"]+)" violates check constraint "([^"]+)"', error_msg)
    if check_match:
        error_info['error_type'] = 'CHECK_CONSTRAINT_VIOLATION'
        table_name = check_match.group(1)
        constraint_name = check_match.group(2)
        error_info['details'].append(f"CHECK制約 '{constraint_name}' 違反")
    
    return error_info

def format_error_details(row_number, row_data, error_info):
    """エラー情報を箇条書き形式でフォーマット"""
    lines = [
        f"\n{'='*60}",
        f"【エラー発生】行番号: {row_number}",
        f"{'='*60}",
        f"■ エラータイプ: {error_info['error_type']}",
        f"■ エラーコード: {error_info['error_code']}",
        f"■ 影響を受けたカラム: {', '.join(error_info['affected_columns']) if error_info['affected_columns'] else '不明'}",
        f"■ エラー詳細:"
    ]
    
    for detail in error_info['details']:
        lines.append(f"  - {detail}")
    
    lines.append(f"■ 元のエラーメッセージ: {error_info['error_message']}")
    lines.append(f"■ 該当行のデータ:")
    
    for col, value in row_data.items():
        if col in error_info['affected_columns']:
            lines.append(f"  - {col}: '{value}' ← ★問題のある値")
        else:
            lines.append(f"  - {col}: '{value}'")
    
    lines.append(f"{'='*60}\n")
    
    return '\n'.join(lines)

def send_sns_notification(sns_client, topic_arn, subject, message):
    """SNS通知を送信する関数"""
    try:
        response = sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
        print(f"SNS通知送信成功: MessageId={response['MessageId']}")
        return True
    except Exception as e:
        print(f"SNS通知送信エラー: {str(e)}")
        return False

def create_sns_message(file_name, table_name, total_rows, inserted_rows, failed_rows, error_summary):
    """SNS通知用のメッセージを作成"""
    message = f"""
CSV処理結果通知

ファイル名: {file_name}
テーブル名: {table_name}
処理日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

【処理結果】
- 総行数: {total_rows}
- 成功: {inserted_rows}行
- 失敗: {failed_rows}行
- 成功率: {(inserted_rows/total_rows*100):.1f}%

"""
    
    if error_summary:
        message += "【エラー内訳】\n"
        for error_type, info in error_summary.items():
            message += f"- {error_type}: {info['count']}件\n"
    
    return message

def lambda_handler(event, context):
    print("=== CSV処理Lambda関数開始 ===")
    print(f"Event: {json.dumps(event, ensure_ascii=False)}")
    
    # 環境変数のデバッグ
    print("=== 環境変数 ===")
    print(f"DB_HOST: {os.environ.get('DB_HOST', 'NOT_SET')}")
    print(f"DB_PORT: {os.environ.get('DB_PORT', 'NOT_SET')}")
    print(f"DB_NAME: {os.environ.get('DB_NAME', 'NOT_SET')}")
    print(f"DB_USER: {os.environ.get('DB_USER', 'NOT_SET')}")
    print(f"DB_PASSWORD: {'SET' if os.environ.get('DB_PASSWORD') else 'NOT_SET'}")
    # print(f"SNS_TOPIC_ARN: {os.environ.get('SNS_TOPIC_ARN', 'NOT_SET')}")

    s3_client = boto3.client('s3')
    # sns_client = boto3.client('sns')

    db_host = os.environ['DB_HOST']
    db_port = os.environ['DB_PORT']
    db_name = os.environ['DB_NAME']
    db_user = os.environ['DB_USER']
    db_password = os.environ['DB_PASSWORD']
    # sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')

    try:
        # S3イベントから情報取得
        print("=== S3イベント解析 ===")
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        object_key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        object_size = event['Records'][0]['s3']['object']['size']

        print(f"バケット名: {bucket_name}")
        print(f"オブジェクトキー: {object_key}")
        print(f"ファイルサイズ: {object_size} bytes")
        print(f"処理対象ファイル: s3://{bucket_name}/{object_key}")

        # CSVファイルを取得
        print("=== S3からCSVファイル取得 ===")
        s3_response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        csv_content = s3_response['Body'].read().decode('utf-8')
        print(f"CSV内容取得完了: {len(csv_content)} 文字")

        # CSV解析
        print("=== CSV解析 ===")
        csv_reader = csv.DictReader(io.StringIO(csv_content))
        rows = list(csv_reader)
        print(f"CSV行数: {len(rows)}")
        
        if rows:
            print(f"CSVカラム: {list(rows[0].keys())}")
            print(f"最初の行データ: {rows[0]}")

        if not rows:
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'CSVファイルにデータがありません'}, ensure_ascii=False)
            }

        # ファイル名からテーブル名を決定
        print("=== テーブル名決定 ===")
        file_name = object_key.split('/')[-1]
        print(f"ファイル名: {file_name}")
        
        file_name_without_ext = file_name.replace('.csv', '')
        print(f"拡張子除去後: {file_name_without_ext}")
        
        # アンダースコアで分割して、接頭辞以降を取得
        parts = file_name_without_ext.split('_', 1)
        print(f"分割結果: {parts}")
        
        if len(parts) >= 2:
            table_name = parts[1]  # 接頭辞以降がテーブル名
            print(f"接頭辞除去後のテーブル名: {table_name}")
        else:
            # アンダースコアがない場合はファイル名全体をテーブル名とする
            table_name = file_name_without_ext
            print(f"アンダースコアなし、全体をテーブル名に: {table_name}")
        
        # テーブル名の正規化（英数字とアンダースコアのみ）
        original_table_name = table_name
        table_name = ''.join(c for c in table_name if c.isalnum() or c == '_').lower()
        print(f"正規化前: {original_table_name}")
        print(f"正規化後（対象テーブル）: {table_name}")

        # データベース接続
        print("=== データベース接続 ===")
        print(f"接続先: {db_host}:{db_port}/{db_name}")
        
        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=30
        )
        print("データベース接続成功")

        conn.autocommit = False
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # テーブル存在確認
        print("=== テーブル存在確認 ===")
        cursor.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_name = %s
            )
        """, (table_name,))
        
        table_exists = cursor.fetchone()['exists']
        print(f"テーブル '{table_name}' 存在: {table_exists}")
        
        if not table_exists:
            error_msg = f"テーブル '{table_name}' が存在しません。事前にテーブルを作成してください。"
            print(f"エラー: {error_msg}")
            
            # 既存テーブル一覧を表示
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                ORDER BY table_name
            """)
            existing_tables = [row['table_name'] for row in cursor.fetchall()]
            print(f"既存テーブル一覧: {existing_tables}")
            
            cursor.close()
            conn.close()
            
            # エラー時のSNS通知
            # if sns_topic_arn:
            #     error_subject = f"CSV処理エラー: {file_name}"
            #     error_message = f"""
            # CSV処理でエラーが発生しました。
            # 
            # ファイル名: {file_name}
            # エラー内容: {error_msg}
            # 既存テーブル: {', '.join(existing_tables)}
            # """
            #     send_sns_notification(sns_client, sns_topic_arn, error_subject, error_message)
            
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': error_msg,
                    'table_name': table_name,
                    'existing_tables': existing_tables,
                    'source_file': f"s3://{bucket_name}/{object_key}"
                }, ensure_ascii=False)
            }

        # 既存テーブルのカラム情報を取得（PRIMARY KEYも含めて取得）
        print("=== テーブルカラム情報取得 ===")
        cursor.execute("""
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns 
            WHERE table_schema = 'public' 
            AND table_name = %s 
            AND column_name NOT IN ('file_source', 'processed_at')
            ORDER BY ordinal_position
        """, (table_name,))
        
        table_columns_info = cursor.fetchall()
        table_columns = [row['column_name'] for row in table_columns_info]
        
        print(f"既存テーブルのカラム数: {len(table_columns)}")
        print(f"既存テーブルのカラム: {table_columns}")
        for col_info in table_columns_info:
            print(f"  - {col_info['column_name']}: {col_info['data_type']} (nullable: {col_info['is_nullable']}, default: {col_info['column_default']})")

        # CSVのカラムを取得
        csv_columns = list(rows[0].keys())
        print(f"CSVのカラム: {csv_columns}")

        # CSVのカラムが全てテーブルに存在するか確認
        missing_columns = set(csv_columns) - set(table_columns)
        if missing_columns:
            print(f"警告: CSVに含まれる以下のカラムはテーブルに存在しません: {missing_columns}")
            print("存在するカラムのみINSERTします")

        # テーブルに存在するカラムのみを使用
        insert_columns = [col for col in csv_columns if col in table_columns]
        print(f"INSERT対象カラム: {insert_columns}")
        
        if not insert_columns:
            error_msg = "CSVとテーブルで一致するカラムがありません"
            print(f"エラー: {error_msg}")
            cursor.close()
            conn.close()
            
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': error_msg,
                    'csv_columns': csv_columns,
                    'table_columns': table_columns
                }, ensure_ascii=False)
            }

        # データ挿入準備
        print("=== データ挿入準備 ===")
        
        # file_sourceとprocessed_atを追加（これらのカラムが存在する場合）
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_schema = 'public' 
            AND table_name = %s 
            AND column_name IN ('file_source', 'processed_at')
        """, (table_name,))
        
        system_columns = [row['column_name'] for row in cursor.fetchall()]
        print(f"システムカラム: {system_columns}")
        
        # INSERT文の構築
        all_columns = insert_columns.copy()
        placeholders = ['%s'] * len(insert_columns)
        
        if 'file_source' in system_columns:
            all_columns.append('file_source')
            placeholders.append('%s')
            print("file_sourceカラムを追加")
        
        column_names = ', '.join([f'"{col}"' for col in all_columns])
        placeholders_str = ', '.join(placeholders)
        insert_sql = f'INSERT INTO "{table_name}" ({column_names}) VALUES ({placeholders_str})'
        
        print(f"INSERT SQL: {insert_sql}")

        # データ挿入
        print("=== データ挿入開始 ===")
        total_inserted = 0
        failed_rows = 0
        failed_details = []
        error_summary = {}  # エラータイプ別の集計
        
        # カラム情報を辞書形式で保持（エラー解析用）
        column_info = {col['column_name']: col for col in table_columns_info}
        
        for i, row in enumerate(rows):
            try:
                values = []
                for col in insert_columns:
                    value = row.get(col, '')
                    if value == '':
                        values.append(None)
                    else:
                        values.append(str(value))
                
                # file_source情報を追加（カラムが存在する場合）
                if 'file_source' in system_columns:
                    values.append(f"s3://{bucket_name}/{object_key}")
                
                print(f"行 {i+1}: 挿入値: {values}")
                
                cursor.execute(insert_sql, values)
                conn.commit()  # 各行ごとにコミット
                total_inserted += 1
                print(f"行 {i+1}: 挿入成功")
                
                if (i + 1) % 100 == 0:
                    print(f"処理中: {i + 1}/{len(rows)} 行")
                    
            except psycopg2.Error as e:
                failed_rows += 1
                
                # PostgreSQLエラーを詳細に解析
                error_info = parse_postgres_error(e, row, column_info)
                
                # エラーの詳細をログ出力
                error_log = format_error_details(i + 1, row, error_info)
                print(error_log)
                
                # エラータイプ別に集計
                error_type = error_info['error_type']
                if error_type not in error_summary:
                    error_summary[error_type] = {
                        'count': 0,
                        'examples': []
                    }
                
                error_summary[error_type]['count'] += 1
                if len(error_summary[error_type]['examples']) < 3:
                    error_summary[error_type]['examples'].append({
                        'row_number': i + 1,
                        'affected_columns': error_info['affected_columns'],
                        'details': error_info['details']
                    })
                
                # 既存のfailed_detailsにも追加
                error_detail = {
                    'row_number': i + 1,
                    'error': str(e),
                    'error_info': error_info,
                    'values': values,
                    'row_data': row
                }
                failed_details.append(error_detail)
                
                conn.rollback()  # エラー時はロールバック
                
            except Exception as e:
                # PostgreSQL以外のエラー
                failed_rows += 1
                error_detail = {
                    'row_number': i + 1,
                    'error': str(e),
                    'values': values,
                    'row_data': row
                }
                failed_details.append(error_detail)
                
                print(f"行 {i+1} の処理でエラー: {e}")
                print(f"失敗した値: {values}")
                print(f"元のデータ: {row}")
                
                conn.rollback()
        
        # エラーサマリーを出力
        if error_summary:
            print("\n" + "="*60)
            print("【エラーサマリー】")
            print("="*60)
            for error_type, info in error_summary.items():
                print(f"\n■ {error_type}: {info['count']}件")
                for idx, example in enumerate(info['examples'], 1):
                    print(f"  例{idx}) 行 {example['row_number']}:")
                    print(f"     影響カラム: {', '.join(example['affected_columns'])}")
                    for detail in example['details']:
                        print(f"     - {detail}")
            print("="*60 + "\n")
        
        print(f"=== データ挿入完了 ===")
        print(f"成功: {total_inserted}行")
        print(f"失敗: {failed_rows}行")
        
        # 処理結果確認
        print("=== 最終結果確認 ===")
        cursor.execute(f'SELECT COUNT(*) as count FROM "{table_name}"')
        result = cursor.fetchone()
        final_count = result['count'] if result else 0
        print(f"テーブル '{table_name}' の最終行数: {final_count}")
        
        cursor.close()
        conn.close()

        success_message = f"CSV処理完了: {total_inserted}行挿入, {failed_rows}行失敗, テーブル '{table_name}' 最終行数: {final_count}"
        print(f"=== 処理結果 ===")
        print(success_message)

        # SNS通知の送信
        # if sns_topic_arn:
        #     # 成功率に応じて通知レベルを変更
        #     success_rate = (total_inserted / len(rows) * 100) if len(rows) > 0 else 0
        #     
        #     if success_rate == 100:
        #         subject = f"✅ CSV処理成功: {file_name}"
        #     elif success_rate >= 80:
        #         subject = f"⚠️ CSV処理一部エラー: {file_name} ({success_rate:.1f}%成功)"
        #     else:
        #         subject = f"❌ CSV処理エラー多数: {file_name} ({success_rate:.1f}%成功)"
        #     
        #     message = create_sns_message(
        #         file_name, table_name, len(rows), 
        #         total_inserted, failed_rows, error_summary
        #     )
        #     
        #     send_sns_notification(sns_client, sns_topic_arn, subject, message)

        # レスポンスボディに error_summary を追加
        response_body = {
            'message': success_message,
            'table_name': table_name,
            'source_file': f"s3://{bucket_name}/{object_key}",
            'total_rows': len(rows),
            'inserted_rows': total_inserted,
            'failed_rows': failed_rows,
            'final_table_count': final_count,
            'matched_columns': insert_columns,
            'missing_columns': list(missing_columns) if missing_columns else [],
            'failed_details': failed_details[:10]  # 最初の10件のエラー詳細
        }
        
        # error_summaryがある場合は追加
        if error_summary:
            response_body['error_summary'] = error_summary

        return {
            'statusCode': 200,
            'body': json.dumps(response_body, ensure_ascii=False)
        }

    except Exception as e:
        print(f"=== 予期しないエラー ===")
        print(f"CSV処理エラー: {str(e)}")
        import traceback
        print(f"詳細エラー: {traceback.format_exc()}")
        
        # 予期しないエラー時のSNS通知
        # if 'sns_topic_arn' in locals() and sns_topic_arn:
        #     critical_subject = f"🚨 CSV処理で重大エラー: {file_name if 'file_name' in locals() else 'unknown'}"
        #     critical_message = f"""
        # CSV処理で予期しないエラーが発生しました。
        # 
        # エラー内容: {str(e)}
        # エラータイプ: {type(e).__name__}
        # 
        # 詳細はCloudWatch Logsを確認してください。
        # """
        #     send_sns_notification(sns_client, sns_topic_arn, critical_subject, critical_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'CSV処理エラー: {str(e)}',
                'error_type': type(e).__name__,
                'error_detail': traceback.format_exc(),
                'source_file': f"s3://{bucket_name}/{object_key}" if 'bucket_name' in locals() else 'unknown'
            }, ensure_ascii=False)
        }