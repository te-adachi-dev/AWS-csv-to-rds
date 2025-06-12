#!/bin/bash

# ETL CSV to RDS PostgreSQL System デプロイスクリプト（3Lambda + 外部Pythonファイル対応）
# UTF-8で保存してください

set -e

# 設定変数
STACK_NAME="etl-csv-to-rds-postgresql"
TEMPLATE_FILE="etl-csv-to-rds-postgresql.yaml"
REGION="us-east-2"
PROJECT_NAME="etl-csv-to-rds-postgresql"
DB_PASSWORD="TestPassword123!"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 色付き出力用
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 必要ファイル確認
check_required_files() {
    local missing_files=()
    
    # 必須ファイル
    if [ ! -f "psycopg2-layer-python311-fixed.zip" ]; then
        missing_files+=("psycopg2-layer-python311-fixed.zip")
    fi
    
    if [ ! -f "${TEMPLATE_FILE}" ]; then
        missing_files+=("${TEMPLATE_FILE}")
    fi
    
    # Pythonファイル
    if [ ! -f "table_creator.py" ]; then
        missing_files+=("table_creator.py")
    fi
    
    if [ ! -f "csv_processor.py" ]; then
        missing_files+=("csv_processor.py")
    fi
    
    if [ ! -f "query_executor.py" ]; then
        missing_files+=("query_executor.py")
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "必要ファイルが見つかりません:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi
    
    # SQLファイルの存在確認
    local sql_count=0
    print_info "SQLファイル検出結果:"
    for file in *.sql; do
        if [ -f "$file" ]; then
            echo "  ✓ $file"
            ((sql_count++))
        fi
    done
    
    if [ $sql_count -eq 0 ]; then
        print_warning "SQLファイルが見つかりません。テーブル作成処理はスキップされます。"
        return 1
    else
        print_success "SQLファイル: ${sql_count}個見つかりました"
        return 0
    fi
}

# Lambda関数のZIPファイル作成
create_lambda_zips() {
    print_info "Lambda関数のZIPファイル作成中..."
    
    # table_creator.zip
    zip -j table_creator.zip table_creator.py
    
    # csv_processor.zip
    zip -j csv_processor.zip csv_processor.py
    
    # query_executor.zip
    zip -j query_executor.zip query_executor.py
    
    print_success "Lambda関数のZIPファイル作成完了"
}

# Change Set作成・実行関数
deploy_with_changeset() {
    local changeset_name="update-$(date +%Y%m%d-%H%M%S)"
    
    print_info "Change Set作成中: ${changeset_name}"
    
    # Change Set作成
    aws cloudformation create-change-set \
        --stack-name "${STACK_NAME}" \
        --template-body "file://${TEMPLATE_FILE}" \
        --change-set-name "${changeset_name}" \
        --parameters \
            ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
            ParameterKey=DBMasterPassword,ParameterValue="${DB_PASSWORD}" \
        --capabilities CAPABILITY_IAM \
        --region "${REGION}"
    
    # Change Set作成完了待機
    print_info "Change Set作成完了待機中..."
    aws cloudformation wait change-set-create-complete \
        --stack-name "${STACK_NAME}" \
        --change-set-name "${changeset_name}" \
        --region "${REGION}"
    
    # Change Set内容表示
    print_info "Change Set内容:"
    aws cloudformation describe-change-set \
        --stack-name "${STACK_NAME}" \
        --change-set-name "${changeset_name}" \
        --region "${REGION}" \
        --query 'Changes[].{Action:Action,ResourceType:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId,Replacement:ResourceChange.Replacement}' \
        --output table
    
    # 実行確認
    echo ""
    read -p "Change Setを実行しますか？ (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "Change Set実行中..."
        aws cloudformation execute-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}"
        
        print_info "スタック更新完了待機中..."
        aws cloudformation wait stack-update-complete \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}"
        
        print_success "Change Set実行完了"
        return 0
    else
        print_info "Change Set削除中..."
        aws cloudformation delete-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}"
        print_info "Change Setをキャンセルしました"
        return 1
    fi
}

print_info "=== ETL CSV to RDS PostgreSQL System デプロイ（3Lambda構成） ==="

# Step 1: ファイル確認
print_info "必要ファイル確認中..."
SQL_FILES_EXIST=true
check_required_files || SQL_FILES_EXIST=false
print_success "必要ファイル確認完了"

# Step 2: Lambda関数のZIPファイル作成
create_lambda_zips

# Step 3: 既存スタック確認
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_EXISTS")

if [ "${STACK_STATUS}" = "NOT_EXISTS" ]; then
    print_info "新規スタック作成モード"
    DEPLOY_MODE="CREATE"
else
    print_info "既存スタック更新モード (現在の状態: ${STACK_STATUS})"
    DEPLOY_MODE="UPDATE"
fi

# Step 4: 一時S3バケット作成
TEMP_BUCKET_NAME="etl-csv-to-rds-postgresql-temp-files-${ACCOUNT_ID}"

# 一時バケットが存在するか確認
if aws s3 ls "s3://${TEMP_BUCKET_NAME}" 2>/dev/null; then
    print_info "一時S3バケット既存: ${TEMP_BUCKET_NAME}"
else
    print_info "一時S3バケット作成中: ${TEMP_BUCKET_NAME}"
    aws s3 mb s3://${TEMP_BUCKET_NAME} --region ${REGION}
    print_success "一時S3バケット作成完了"
fi

# Step 5: ファイルアップロード
print_info "ファイルアップロード中..."

# Lambda関数ファイルのアップロード
aws s3 cp table_creator.zip "s3://${TEMP_BUCKET_NAME}/lambda-code/table_creator.zip" --region ${REGION}
aws s3 cp csv_processor.zip "s3://${TEMP_BUCKET_NAME}/lambda-code/csv_processor.zip" --region ${REGION}
aws s3 cp query_executor.zip "s3://${TEMP_BUCKET_NAME}/lambda-code/query_executor.zip" --region ${REGION}

# psycopg2レイヤーのアップロード
aws s3 cp psycopg2-layer-python311-fixed.zip "s3://${TEMP_BUCKET_NAME}/layers/psycopg2-layer-python311-fixed.zip" --region ${REGION}

print_success "ファイルアップロード完了"

# Step 6: CloudFormationデプロイ
if [ "${DEPLOY_MODE}" = "CREATE" ]; then
    print_info "=== 新規スタック作成開始 ==="
    
    aws cloudformation deploy \
        --template-file "${TEMPLATE_FILE}" \
        --stack-name "${STACK_NAME}" \
        --parameters \
            ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
            ParameterKey=DBMasterPassword,ParameterValue="${DB_PASSWORD}" \
        --capabilities CAPABILITY_IAM \
        --region "${REGION}"
    
    if [ $? -eq 0 ]; then
        print_success "新規スタック作成完了"
    else
        print_error "新規スタック作成失敗"
        exit 1
    fi
else
    print_info "=== スタック更新開始（Change Set使用） ==="
    
    if deploy_with_changeset; then
        print_success "スタック更新完了"
    else
        print_info "スタック更新をキャンセルしました"
        exit 0
    fi
fi

# Step 7: リソース情報取得
print_info "リソース情報取得中..."

S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

TABLE_CREATOR_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`TableCreatorFunction`].OutputValue' \
    --output text)

CSV_PROCESSOR_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`CSVProcessorFunction`].OutputValue' \
    --output text)

QUERY_EXECUTOR_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`QueryExecutorFunction`].OutputValue' \
    --output text)

RDS_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
    --output text)

RDS_PORT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`RDSPort`].OutputValue' \
    --output text)

print_success "リソース情報取得完了"

# Step 8: 本番S3バケットにレイヤーファイル移動
print_info "本番S3バケットにレイヤーファイル移動中..."
aws s3 cp "s3://${TEMP_BUCKET_NAME}/layers/psycopg2-layer-python311-fixed.zip" \
    "s3://${S3_BUCKET}/layers/psycopg2-layer-python311-fixed.zip" --region ${REGION}
print_success "レイヤーファイル移動完了"

# Step 9: SQLファイルアップロード
if [ "$SQL_FILES_EXIST" = true ]; then
    print_info "SQLファイルアップロード開始"
    
    for sql_file in *.sql; do
        if [ -f "$sql_file" ]; then
            print_info "  アップロード: $sql_file"
            aws s3 cp "$sql_file" "s3://${S3_BUCKET}/init-sql/$sql_file" --region ${REGION}
        fi
    done
    print_success "SQLファイルアップロード完了"
fi

# Step 10: テーブル作成実行
if [ "$SQL_FILES_EXIST" = true ]; then
    print_info "テーブル作成Lambda実行中..."
    
    TABLE_CREATION_RESULT=$(aws lambda invoke \
        --function-name "${TABLE_CREATOR_FUNCTION_NAME}" \
        --payload '{}' \
        --region "${REGION}" \
        table_creation_response.json 2>/dev/null && cat table_creation_response.json 2>/dev/null || echo '{"error": "実行失敗"}')
    
    print_info "テーブル作成結果:"
    echo "$TABLE_CREATION_RESULT" | python3 -m json.tool 2>/dev/null || echo "$TABLE_CREATION_RESULT"
    
    print_success "テーブル作成実行完了"
fi

# Step 11: 設定情報保存
print_info "設定情報保存中..."

cat > deployment_info.txt << EOF
# ETL CSV to RDS PostgreSQL System デプロイ情報（3Lambda構成）
# デプロイ日時: $(date)

STACK_NAME="${STACK_NAME}"
REGION="${REGION}"
PROJECT_NAME="${PROJECT_NAME}"
S3_BUCKET="${S3_BUCKET}"
TABLE_CREATOR_FUNCTION_NAME="${TABLE_CREATOR_FUNCTION_NAME}"
CSV_PROCESSOR_FUNCTION_NAME="${CSV_PROCESSOR_FUNCTION_NAME}"
QUERY_EXECUTOR_FUNCTION_NAME="${QUERY_EXECUTOR_FUNCTION_NAME}"
RDS_ENDPOINT="${RDS_ENDPOINT}"
RDS_PORT="${RDS_PORT}"
DB_USER="postgres"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="postgres"

# === Lambda関数の使い方 ===

# 1. テーブル作成Lambda（手動実行）
aws lambda invoke --function-name ${TABLE_CREATOR_FUNCTION_NAME} --payload '{}' --region ${REGION} result.json

# 2. CSV処理Lambda（S3トリガー自動実行）
aws s3 cp test.csv s3://${S3_BUCKET}/csv/test.csv --region ${REGION}

# 3. 運用SQL実行Lambda（手動実行）
aws lambda invoke \
    --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \
    --payload '{"sql":"SELECT * FROM test20250611 LIMIT 10;","output_format":"csv","output_name":"test_query"}' \
    --region ${REGION} \
    query_result.json

# === 動作確認コマンド ===

# データ確認クエリ実行
aws lambda invoke \
    --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \
    --payload '{"sql":"SELECT COUNT(*) as total_records FROM sales_data_20250611_20250611_143000;","output_format":"json","output_name":"record_count"}' \
    --region ${REGION} \
    count_result.json

# 集計クエリ実行
aws lambda invoke \
    --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \
    --payload '{"sql":"SELECT department, COUNT(*) as cnt, AVG(CAST(age as INTEGER)) as avg_age FROM test20250611 GROUP BY department;","output_format":"csv","output_name":"department_summary"}' \
    --region ${REGION} \
    summary_result.json

# === Change Set使用方法 ===

# Change Set作成（差分確認）
aws cloudformation create-change-set \
    --stack-name ${STACK_NAME} \
    --template-body file://${TEMPLATE_FILE} \
    --change-set-name update-$(date +%Y%m%d-%H%M%S) \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=${PROJECT_NAME} \
        ParameterKey=DBMasterPassword,ParameterValue=${DB_PASSWORD} \
    --capabilities CAPABILITY_IAM \
    --region ${REGION}

# Change Set内容確認
aws cloudformation describe-change-set \
    --stack-name ${STACK_NAME} \
    --change-set-name <CHANGESET_NAME> \
    --region ${REGION}

# Change Set実行
aws cloudformation execute-change-set \
    --stack-name ${STACK_NAME} \
    --change-set-name <CHANGESET_NAME> \
    --region ${REGION}

# === トラブルシューティング ===

# Lambda関数詳細確認
aws lambda get-function --function-name ${TABLE_CREATOR_FUNCTION_NAME} --region ${REGION}
aws lambda get-function --function-name ${CSV_PROCESSOR_FUNCTION_NAME} --region ${REGION}
aws lambda get-function --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} --region ${REGION}

# S3バケット内容確認
aws s3 ls s3://${S3_BUCKET}/ --recursive --region ${REGION}

# RDSステータス確認
aws rds describe-db-instances --db-instance-identifier ${PROJECT_NAME}-postgres-20250611 --region ${REGION}

# === データベース直接接続 ===
psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres

# テーブル一覧確認
psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres -c "\\dt"

# === S3フォルダ構成 ===
# s3://${S3_BUCKET}/
# ├── csv/               # CSV投入フォルダ（自動処理）
# ├── init-sql/          # 初期テーブル作成SQL
# ├── query-results/     # クエリ結果出力
# └── layers/            # Lambda Layer

# === ログ監視 ===
aws logs tail /aws/lambda/${TABLE_CREATOR_FUNCTION_NAME} --follow --region ${REGION}
aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --follow --region ${REGION}
aws logs tail /aws/lambda/${QUERY_EXECUTOR_FUNCTION_NAME} --follow --region ${REGION}

# === 運用例 ===

# CSVデータ投入
aws s3 cp sales_data_20250611.csv s3://${S3_BUCKET}/csv/sales_data_20250611.csv --region ${REGION}

# データ確認
aws lambda invoke \
    --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \
    --payload '{"sql":"SELECT COUNT(*) FROM sales_data_20250611_20250612_120000;","output_format":"json","output_name":"count_check"}' \
    --region ${REGION} \
    check_result.json

# 集計処理
aws lambda invoke \
    --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \
    --payload '{"sql":"SELECT category, SUM(amount) as total_amount FROM sales_data_20250611_20250612_120000 GROUP BY category ORDER BY total_amount DESC;","output_format":"csv","output_name":"category_summary"}' \
    --region ${REGION} \
    aggregation_result.json

# === スタック削除 ===
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}

# === 一時バケット削除（必要に応じて） ===
aws s3 rm s3://${TEMP_BUCKET_NAME} --recursive --region ${REGION}
aws s3 rb s3://${TEMP_BUCKET_NAME} --region ${REGION}

EOF

# 一時ファイル削除
rm -f table_creation_response.json table_creator.zip csv_processor.zip query_executor.zip 2>/dev/null || true

print_success "=== ETL CSV to RDS PostgreSQL System デプロイ完了（3Lambda構成）! ==="

echo ""
echo "=== デプロイ結果サマリー ==="
echo "✅ デプロイモード: ${DEPLOY_MODE}"
echo "✅ S3バケット: ${S3_BUCKET}"
echo "✅ テーブル作成Lambda: ${TABLE_CREATOR_FUNCTION_NAME}"
echo "✅ CSV処理Lambda: ${CSV_PROCESSOR_FUNCTION_NAME}"
echo "✅ 運用SQL実行Lambda: ${QUERY_EXECUTOR_FUNCTION_NAME}"
echo "✅ RDSエンドポイント: ${RDS_ENDPOINT}:${RDS_PORT}"
if [ "$SQL_FILES_EXIST" = true ]; then
    echo "✅ SQLファイルアップロード: 完了"
    echo "✅ テーブル作成実行: 完了"
else
    echo "⚠️  SQLファイル: 見つからず（後で手動追加可能）"
fi
echo ""
echo "=== 3つのLambda関数 ==="
echo "1. 📋 テーブル作成Lambda: ${TABLE_CREATOR_FUNCTION_NAME}"
echo "   用途: 初期テーブル作成（手動実行）"
echo "   実行: aws lambda invoke --function-name ${TABLE_CREATOR_FUNCTION_NAME} --payload '{}' --region ${REGION} result.json"
echo ""
echo "2. 📊 CSV処理Lambda: ${CSV_PROCESSOR_FUNCTION_NAME}"
echo "   用途: CSVファイル自動処理（S3トリガー）"
echo "   実行: aws s3 cp test.csv s3://${S3_BUCKET}/csv/test.csv --region ${REGION}"
echo ""
echo "3. 🔍 運用SQL実行Lambda: ${QUERY_EXECUTOR_FUNCTION_NAME}"
echo "   用途: 任意SQL実行・結果S3出力（手動実行）"
echo "   実行例:"
echo "   aws lambda invoke \\"
echo "     --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\"
echo "     --payload '{\"sql\":\"SELECT * FROM test20250611 LIMIT 10;\",\"output_format\":\"csv\",\"output_name\":\"test_query\"}' \\"
echo "     --region ${REGION} query_result.json"
echo ""
echo "=== 次のステップ ==="
echo "1. データベース接続確認:"
echo "   psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres"
echo ""
echo "2. CSVデータ投入テスト:"
echo "   aws s3 cp sample.csv s3://${S3_BUCKET}/csv/sample.csv --region ${REGION}"
echo ""
echo "3. 運用クエリ実行テスト:"
echo "   aws lambda invoke --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} --payload '{\"sql\":\"SELECT version();\",\"output_format\":\"json\"}' --region ${REGION} version.json"
echo ""
echo "詳細情報: deployment_info.txt を参照してください"

# 実行結果の表示
if [ "$SQL_FILES_EXIST" = true ]; then
    echo ""
    echo "=== テーブル作成結果の確認 ==="
    echo "以下のコマンドで最新のテーブル作成結果を確認できます:"
    echo "aws lambda invoke --function-name ${TABLE_CREATOR_FUNCTION_NAME} --payload '{}' --region ${REGION} latest_result.json && cat latest_result.json | python3 -m json.tool"
fi

echo ""
echo "=== CloudFormation Change Set について ==="
echo "今後のスタック更新時は Change Set を使用して安全にデプロイできます:"
echo "1. このスクリプトを再実行すると自動的に Change Set が作成されます"
echo "2. 変更内容を確認してから実行するかを選択できます"
echo "3. 問題があればキャンセルしてロールバック可能です"

echo ""
echo "🎉 デプロイ完了! 🎉"

exit 0