#!/bin/bash

# ETL CSV to RDS PostgreSQL System デプロイスクリプト（完全版・改善版）
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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

# 前提条件チェック関数
check_prerequisites() {
    print_step "=== 前提条件チェック ==="
    
    # AWS CLI確認
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLIがインストールされていません"
        echo "AWS CLIをインストールしてください: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # AWS CLIバージョン確認
    AWS_CLI_VERSION=$(aws --version 2>&1 | head -n 1)
    print_success "AWS CLI: $AWS_CLI_VERSION"
    
    # AWS CLI v1の場合の警告
    if echo "$AWS_CLI_VERSION" | grep -q "aws-cli/1\."; then
        print_warning "AWS CLI v1を使用中。v2への更新を推奨します。"
        print_info "v2インストール: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    fi
    
    # AWS認証確認
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS認証が設定されていません"
        echo "aws configure または環境変数で認証情報を設定してください"
        exit 1
    fi
    
    # アカウント情報表示
    CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
    print_success "AWS認証: ${CURRENT_USER}"
    
    # CloudFormation操作権限確認
    print_info "CloudFormation権限チェック中..."
    if aws cloudformation list-stacks --region "${REGION}" --max-items 1 > /dev/null 2>&1; then
        print_success "CloudFormation権限: OK"
    else
        print_error "CloudFormationの操作権限がありません"
        exit 1
    fi
    
    # リージョンの利用可能ゾーン確認
    AZ_COUNT=$(aws ec2 describe-availability-zones --region ${REGION} --query 'length(AvailabilityZones)' --output text)
    if [ "$AZ_COUNT" -lt 3 ]; then
        print_warning "リージョン ${REGION} の利用可能ゾーンが3つ未満です (現在: ${AZ_COUNT})"
        print_info "RDS用に最低2つ、推奨3つの利用可能ゾーンが必要です"
        
        # 利用可能ゾーン一覧表示
        print_info "利用可能ゾーン一覧:"
        aws ec2 describe-availability-zones --region ${REGION} --query 'AvailabilityZones[].{Name:ZoneName,State:State}' --output table
        
        if [ "$AZ_COUNT" -lt 2 ]; then
            print_error "利用可能ゾーンが2つ未満のため、RDSが作成できません"
            exit 1
        fi
    else
        print_success "利用可能ゾーン: ${AZ_COUNT}個（十分）"
    fi
    
    # Pythonバージョン確認
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1)
        print_success "Python: ${PYTHON_VERSION}"
    else
        print_warning "Python3が見つかりません（JSON整形に影響する可能性があります）"
    fi
    
    # zipコマンド確認
    if ! command -v zip &> /dev/null; then
        print_error "zipコマンドがインストールされていません"
        exit 1
    fi
    print_success "zip: 確認済み"
    
    # psqlコマンド確認（オプション）
    if command -v psql &> /dev/null; then
        PSQL_VERSION=$(psql --version | head -n 1)
        print_success "PostgreSQL Client: ${PSQL_VERSION}"
    else
        print_warning "psqlコマンドが見つかりません（データベース直接接続に影響します）"
        print_info "インストール方法: sudo apt-get install postgresql-client (Ubuntu/Debian)"
        print_info "インストール方法: brew install postgresql (macOS)"
    fi
    
    print_success "前提条件チェック完了"
}

# VPC設定検証関数
validate_vpc_configuration() {
    print_step "=== VPC設定検証 ==="
    
    # テンプレートファイルの存在確認
    if [ ! -f "${TEMPLATE_FILE}" ]; then
        print_error "CloudFormationテンプレートファイルが見つかりません: ${TEMPLATE_FILE}"
        exit 1
    fi
    print_success "テンプレートファイル: ${TEMPLATE_FILE} 確認済み"
    
    # テンプレートファイルの構文チェック
    print_info "CloudFormationテンプレート構文チェック中..."
    if aws cloudformation validate-template \
        --template-body "file://${TEMPLATE_FILE}" \
        --region "${REGION}" > /dev/null 2>&1; then
        print_success "CloudFormationテンプレート構文: OK"
    else
        print_error "CloudFormationテンプレート構文エラー"
        aws cloudformation validate-template \
            --template-body "file://${TEMPLATE_FILE}" \
            --region "${REGION}" 2>&1
        exit 1
    fi
    
    # VPCクォータ確認
    print_info "VPCクォータ確認中..."
    VPC_COUNT=$(aws ec2 describe-vpcs --region ${REGION} --query 'length(Vpcs)' --output text)
    VPC_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-F678F1CE --region ${REGION} --query 'Quota.Value' --output text 2>/dev/null || echo "5")
    
    print_debug "現在のVPC数: ${VPC_COUNT}/${VPC_LIMIT}"
    if [ "$VPC_COUNT" -ge "$VPC_LIMIT" ]; then
        print_warning "VPC制限に近づいています (${VPC_COUNT}/${VPC_LIMIT})"
    fi
    
    print_success "VPC設定検証完了"
}

# 必要ファイル確認
check_required_files() {
    print_step "=== 必要ファイル確認 ==="
    local missing_files=()
    
    # 必須ファイル
    if [ ! -f "psycopg2-layer-python311-fixed.zip" ]; then
        missing_files+=("psycopg2-layer-python311-fixed.zip")
    fi
    
    if [ ! -f "${TEMPLATE_FILE}" ]; then
        missing_files+=("${TEMPLATE_FILE}")
    fi
    
    # Pythonファイル
    local python_files=("table_creator.py" "csv_processor.py" "query_executor.py")
    for py_file in "${python_files[@]}"; do
        if [ ! -f "$py_file" ]; then
            missing_files+=("$py_file")
        else
            # Pythonファイルの構文チェック
            if python3 -m py_compile "$py_file" 2>/dev/null; then
                print_success "Python構文チェック: $py_file OK"
            else
                print_warning "Python構文警告: $py_file （エラーの可能性）"
            fi
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "必要ファイルが見つかりません:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi
    
    # ファイルサイズ確認
    print_info "ファイルサイズ確認:"
    for file in "psycopg2-layer-python311-fixed.zip" "${python_files[@]}"; do
        if [ -f "$file" ]; then
            SIZE=$(du -h "$file" | cut -f1)
            print_debug "  $file: ${SIZE}"
        fi
    done
    
    # SQLファイルの存在確認
    local sql_count=0
    print_info "SQLファイル検出結果:"
    for file in *.sql; do
        if [ -f "$file" ]; then
            SIZE=$(du -h "$file" | cut -f1)
            echo "  ✓ $file (${SIZE})"
            ((sql_count++))
            
            # SQLファイルの簡単な構文チェック
            if grep -qi "CREATE TABLE" "$file"; then
                print_debug "    CREATE TABLE文を検出"
            fi
            if grep -qi "INSERT INTO" "$file"; then
                print_debug "    INSERT文を検出"
            fi
        fi
    done
    
    if [ $sql_count -eq 0 ]; then
        print_warning "SQLファイルが見つかりません。テーブル作成処理はスキップされます。"
        print_info "後でSQLファイルを追加してテーブル作成Lambda関数を実行してください。"
        return 1
    else
        print_success "SQLファイル: ${sql_count}個見つかりました"
        return 0
    fi
}

# Lambda関数のZIPファイル作成
create_lambda_zips() {
    print_step "=== Lambda関数ZIPファイル作成 ==="
    
    # 既存のZIPファイル削除
    rm -f table_creator.zip csv_processor.zip query_executor.zip 2>/dev/null || true
    
    # table_creator.zip
    print_info "table_creator.zip作成中..."
    if zip -j table_creator.zip table_creator.py > /dev/null 2>&1; then
        ZIP_SIZE=$(du -h table_creator.zip | cut -f1)
        print_success "table_creator.zip作成完了 (${ZIP_SIZE})"
    else
        print_error "table_creator.zip作成失敗"
        exit 1
    fi
    
    # csv_processor.zip
    print_info "csv_processor.zip作成中..."
    if zip -j csv_processor.zip csv_processor.py > /dev/null 2>&1; then
        ZIP_SIZE=$(du -h csv_processor.zip | cut -f1)
        print_success "csv_processor.zip作成完了 (${ZIP_SIZE})"
    else
        print_error "csv_processor.zip作成失敗"
        exit 1
    fi
    
    # query_executor.zip
    print_info "query_executor.zip作成中..."
    if zip -j query_executor.zip query_executor.py > /dev/null 2>&1; then
        ZIP_SIZE=$(du -h query_executor.zip | cut -f1)
        print_success "query_executor.zip作成完了 (${ZIP_SIZE})"
    else
        print_error "query_executor.zip作成失敗"
        exit 1
    fi
    
    print_success "Lambda関数ZIPファイル作成完了"
}

# Change Set作成・実行関数
deploy_with_changeset() {
    local changeset_name="update-$(date +%Y%m%d-%H%M%S)"
    
    print_step "=== Change Set使用によるスタック更新 ==="
    print_info "Change Set作成中: ${changeset_name}"
    
    # Change Set作成
    if aws cloudformation create-change-set \
        --stack-name "${STACK_NAME}" \
        --template-body "file://${TEMPLATE_FILE}" \
        --change-set-name "${changeset_name}" \
        --parameters \
            ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
            ParameterKey=DBMasterPassword,ParameterValue="${DB_PASSWORD}" \
        --capabilities CAPABILITY_IAM \
        --region "${REGION}" > /dev/null 2>&1; then
        print_success "Change Set作成リクエスト送信"
    else
        print_error "Change Set作成失敗"
        return 1
    fi
    
    # Change Set作成完了待機
    print_info "Change Set作成完了待機中..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        STATUS=$(aws cloudformation describe-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}" \
            --query 'Status' \
            --output text 2>/dev/null || echo "PENDING")
        
        if [ "$STATUS" = "CREATE_COMPLETE" ]; then
            print_success "Change Set作成完了"
            break
        elif [ "$STATUS" = "FAILED" ]; then
            print_error "Change Set作成失敗"
            REASON=$(aws cloudformation describe-change-set \
                --stack-name "${STACK_NAME}" \
                --change-set-name "${changeset_name}" \
                --region "${REGION}" \
                --query 'StatusReason' \
                --output text 2>/dev/null || echo "不明")
            print_error "失敗理由: ${REASON}"
            return 1
        fi
        
        echo -n "."
        sleep 5
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        print_error "Change Set作成がタイムアウトしました"
        return 1
    fi
    
    # Change Set内容表示
    print_info "Change Set内容:"
    echo ""
    aws cloudformation describe-change-set \
        --stack-name "${STACK_NAME}" \
        --change-set-name "${changeset_name}" \
        --region "${REGION}" \
        --query 'Changes[].{Action:Action,ResourceType:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId,Replacement:ResourceChange.Replacement}' \
        --output table 2>/dev/null || echo "変更内容の取得に失敗しました"
    
    # 変更数確認
    CHANGE_COUNT=$(aws cloudformation describe-change-set \
        --stack-name "${STACK_NAME}" \
        --change-set-name "${changeset_name}" \
        --region "${REGION}" \
        --query 'length(Changes)' \
        --output text 2>/dev/null || echo "0")
    
    print_info "変更項目数: ${CHANGE_COUNT}"
    
    if [ "$CHANGE_COUNT" = "0" ]; then
        print_info "変更がないため、Change Setを削除します"
        aws cloudformation delete-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}" > /dev/null 2>&1
        return 2  # 変更なしを示す特別なリターンコード
    fi
    
    # 実行確認
    echo ""
    echo -e "${YELLOW}Change Setを実行しますか？${NC}"
    echo "  - 変更項目数: ${CHANGE_COUNT}"
    echo "  - スタック名: ${STACK_NAME}"
    echo "  - リージョン: ${REGION}"
    echo ""
    read -p "実行する場合は 'yes' を入力してください: " confirm
    
    if [[ $confirm = "yes" ]]; then
        print_info "Change Set実行中..."
        if aws cloudformation execute-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}" > /dev/null 2>&1; then
            print_success "Change Set実行開始"
        else
            print_error "Change Set実行失敗"
            return 1
        fi
        
        print_info "スタック更新完了待機中..."
        print_warning "この処理には数分かかる場合があります..."
        
        if aws cloudformation wait stack-update-complete \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}"; then
            print_success "Change Set実行完了"
            return 0
        else
            print_error "スタック更新に失敗しました"
            print_info "CloudFormationコンソールで詳細を確認してください"
            return 1
        fi
    else
        print_info "Change Set削除中..."
        aws cloudformation delete-change-set \
            --stack-name "${STACK_NAME}" \
            --change-set-name "${changeset_name}" \
            --region "${REGION}" > /dev/null 2>&1
        print_info "Change Setをキャンセルしました"
        return 1
    fi
}

# スタック状態確認
check_stack_status() {
    print_step "=== スタック状態確認 ==="
    
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_EXISTS")
    
    case "$STACK_STATUS" in
        "NOT_EXISTS")
            print_info "新規スタック作成モード"
            return 0
            ;;
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_info "既存スタック更新モード (状態: ${STACK_STATUS})"
            return 1
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
            print_warning "スタック処理中 (状態: ${STACK_STATUS})"
            print_info "処理完了まで待機してから再実行してください"
            exit 1
            ;;
        "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
            print_warning "スタックエラー状態 (状態: ${STACK_STATUS})"
            print_info "失敗したスタックを削除してから再実行することを推奨します"
            echo ""
            print_info "失敗の詳細:"
            aws cloudformation describe-stack-events \
                --stack-name "${STACK_NAME}" \
                --region "${REGION}" \
                --max-items 5 \
                --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].{Time:Timestamp,Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
                --output table 2>/dev/null || echo "詳細の取得に失敗しました"
            
            echo ""
            read -p "失敗したスタックを自動削除しますか？ (y/N): " delete_confirm
            if [[ $delete_confirm =~ ^[Yy]$ ]]; then
                print_info "スタック削除中..."
                if aws cloudformation delete-stack \
                    --stack-name "${STACK_NAME}" \
                    --region "${REGION}" > /dev/null 2>&1; then
                    
                    print_info "スタック削除完了待機中..."
                    local delete_wait_count=0
                    while [ $delete_wait_count -lt 20 ]; do  # 最大10分待機
                        DELETE_STATUS=$(aws cloudformation describe-stacks \
                            --stack-name "${STACK_NAME}" \
                            --region "${REGION}" \
                            --query 'Stacks[0].StackStatus' \
                            --output text 2>/dev/null || echo "DELETED")
                        
                        if [ "$DELETE_STATUS" = "DELETED" ]; then
                            print_success "スタック削除完了"
                            return 0  # 新規作成モードに変更
                        elif [ "$DELETE_STATUS" = "DELETE_FAILED" ]; then
                            print_error "スタック削除失敗"
                            exit 1
                        fi
                        
                        echo -n "."
                        sleep 30
                        ((delete_wait_count++))
                    done
                    
                    print_error "スタック削除がタイムアウトしました"
                    exit 1
                else
                    print_error "スタック削除コマンドの実行に失敗しました"
                    exit 1
                fi
            else
                print_info "手動でスタックを削除してから再実行してください:"
                echo "aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}"
                exit 1
            fi
            ;;
        *)
            print_warning "不明なスタック状態: ${STACK_STATUS}"
            return 1
            ;;
    esac
}

# 一時S3バケット管理
manage_temp_bucket() {
    print_step "=== 一時S3バケット管理 ==="
    
    TEMP_BUCKET_NAME="etl-csv-to-rds-postgresql-temp-files-${ACCOUNT_ID}"
    
    # 一時バケットが存在するか確認
    if aws s3 ls "s3://${TEMP_BUCKET_NAME}" > /dev/null 2>&1; then
        print_info "一時S3バケット既存: ${TEMP_BUCKET_NAME}"
        
        # バケット内容確認
        OBJECT_COUNT=$(aws s3 ls "s3://${TEMP_BUCKET_NAME}" --recursive --region ${REGION} | wc -l)
        print_debug "バケット内オブジェクト数: ${OBJECT_COUNT}"
    else
        print_info "一時S3バケット作成中: ${TEMP_BUCKET_NAME}"
        if aws s3 mb "s3://${TEMP_BUCKET_NAME}" --region ${REGION} > /dev/null 2>&1; then
            print_success "一時S3バケット作成完了"
        else
            print_error "一時S3バケット作成失敗"
            exit 1
        fi
    fi
}

# ファイルアップロード
upload_files() {
    print_step "=== ファイルアップロード ==="
    
    local upload_errors=0
    
    # Lambda関数ファイルのアップロード
    local lambda_files=("table_creator.zip" "csv_processor.zip" "query_executor.zip")
    for zip_file in "${lambda_files[@]}"; do
        print_info "${zip_file}をアップロード中..."
        if aws s3 cp "$zip_file" "s3://${TEMP_BUCKET_NAME}/lambda-code/$zip_file" --region ${REGION} > /dev/null 2>&1; then
            print_success "${zip_file}アップロード完了"
        else
            print_error "${zip_file}アップロード失敗"
            ((upload_errors++))
        fi
    done
    
    # psycopg2レイヤーのアップロード
    print_info "psycopg2レイヤーをアップロード中..."
    if aws s3 cp psycopg2-layer-python311-fixed.zip "s3://${TEMP_BUCKET_NAME}/layers/psycopg2-layer-python311-fixed.zip" --region ${REGION} > /dev/null 2>&1; then
        print_success "psycopg2レイヤーアップロード完了"
    else
        print_error "psycopg2レイヤーアップロード失敗"
        ((upload_errors++))
    fi
    
    if [ $upload_errors -gt 0 ]; then
        print_error "ファイルアップロードでエラーが発生しました (${upload_errors}件)"
        exit 1
    fi
    
    print_success "ファイルアップロード完了"
}

# CloudFormationデプロイ
deploy_cloudformation() {
    print_step "=== CloudFormationデプロイ ==="
    
    if check_stack_status; then
        # 新規作成
        print_info "新規スタック作成開始..."
        print_warning "この処理には10-15分かかります（RDS作成のため）"
        
        # aws cloudformation deployの代わりにcreate-stackとwaitを使用
        if aws cloudformation create-stack \
            --stack-name "${STACK_NAME}" \
            --template-body "file://${TEMPLATE_FILE}" \
            --parameters \
                ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
                ParameterKey=DBMasterPassword,ParameterValue="${DB_PASSWORD}" \
            --capabilities CAPABILITY_IAM \
            --region "${REGION}" > /dev/null 2>&1; then
            print_success "スタック作成リクエスト送信完了"
            
            print_info "スタック作成完了待機中..."
            print_warning "RDS作成のため10-15分かかります。しばらくお待ちください..."
            
            # 進行状況表示
            local wait_count=0
            while [ $wait_count -lt 60 ]; do  # 最大30分待機
                STACK_STATUS=$(aws cloudformation describe-stacks \
                    --stack-name "${STACK_NAME}" \
                    --region "${REGION}" \
                    --query 'Stacks[0].StackStatus' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                case "$STACK_STATUS" in
                    "CREATE_COMPLETE")
                        echo ""
                        print_success "新規スタック作成完了"
                        return 0
                        ;;
                    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
                        echo ""
                        print_error "スタック作成失敗 (状態: ${STACK_STATUS})"
                        print_info "失敗理由確認中..."
                        
                        # 失敗したリソースの詳細を表示
                        echo ""
                        echo "=== 失敗したリソース一覧 ==="
                        aws cloudformation describe-stack-events \
                            --stack-name "${STACK_NAME}" \
                            --region "${REGION}" \
                            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Time:Timestamp,Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
                            --output table 2>/dev/null || echo "詳細情報の取得に失敗しました"
                        
                        echo ""
                        echo "=== 最新のスタックイベント（最新10件） ==="
                        aws cloudformation describe-stack-events \
                            --stack-name "${STACK_NAME}" \
                            --region "${REGION}" \
                            --max-items 10 \
                            --query 'StackEvents[].{Time:Timestamp,Status:ResourceStatus,Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
                            --output table 2>/dev/null || echo "イベント情報の取得に失敗しました"
                        
                        echo ""
                        print_info "CloudFormationコンソールで詳細を確認:"
                        echo "https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks?filteringStatus=active&filteringText=&viewNested=true&hideStacks=false"
                        
                        return 1
                        ;;
                    "CREATE_IN_PROGRESS")
                        echo -n "."
                        ;;
                    *)
                        echo -n "?"
                        ;;
                esac
                
                sleep 30
                ((wait_count++))
            done
            
            echo ""
            print_error "スタック作成がタイムアウトしました（30分経過）"
            print_info "現在の状態: ${STACK_STATUS}"
            return 1
        else
            print_error "スタック作成リクエスト送信失敗"
            return 1
        fi
    else
        # 更新
        print_info "既存スタック更新開始..."
        
        if deploy_with_changeset; then
            print_success "スタック更新完了"
            return 0
        elif [ $? -eq 2 ]; then
            print_info "変更がないため更新をスキップしました"
            return 0
        else
            print_error "スタック更新失敗"
            return 1
        fi
    fi
}

# リソース情報取得
get_resource_info() {
    print_step "=== リソース情報取得 ==="
    
    # CloudFormationスタックの出力値を取得
    local outputs=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null)
    
    if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
        print_error "スタック出力値の取得に失敗しました"
        return 1
    fi
    
    # 各出力値を変数に格納
    S3_BUCKET=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='S3BucketName'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    TABLE_CREATOR_FUNCTION_NAME=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='TableCreatorFunction'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    CSV_PROCESSOR_FUNCTION_NAME=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='CSVProcessorFunction'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    QUERY_EXECUTOR_FUNCTION_NAME=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='QueryExecutorFunction'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    RDS_ENDPOINT=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='RDSEndpoint'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    RDS_PORT=$(echo "$outputs" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['OutputValue'] for item in data if item['OutputKey']=='RDSPort'), 'NOT_FOUND'))" 2>/dev/null || echo "NOT_FOUND")
    
    # 取得結果確認
    if [ "$S3_BUCKET" = "NOT_FOUND" ] || [ "$TABLE_CREATOR_FUNCTION_NAME" = "NOT_FOUND" ]; then
        print_error "必要なリソース情報の取得に失敗しました"
        print_debug "利用可能な出力値:"
        echo "$outputs" | python3 -m json.tool 2>/dev/null || echo "$outputs"
        return 1
    fi
    
    print_success "リソース情報取得完了"
    print_debug "S3バケット: ${S3_BUCKET}"
    print_debug "テーブル作成Lambda: ${TABLE_CREATOR_FUNCTION_NAME}"
    print_debug "CSV処理Lambda: ${CSV_PROCESSOR_FUNCTION_NAME}"
    print_debug "クエリ実行Lambda: ${QUERY_EXECUTOR_FUNCTION_NAME}"
    print_debug "RDSエンドポイント: ${RDS_ENDPOINT}:${RDS_PORT}"
    
    return 0
}

# 本番S3バケットにファイル移動
move_files_to_production() {
    print_step "=== 本番S3バケットにファイル移動 ==="
    
    # レイヤーファイル移動
    print_info "psycopg2レイヤーファイル移動中..."
    if aws s3 cp "s3://${TEMP_BUCKET_NAME}/layers/psycopg2-layer-python311-fixed.zip" \
        "s3://${S3_BUCKET}/layers/psycopg2-layer-python311-fixed.zip" \
        --region ${REGION} > /dev/null 2>&1; then
        print_success "レイヤーファイル移動完了"
    else
        print_warning "レイヤーファイル移動に失敗しました（Lambda関数は既に作成済みのため影響なし）"
    fi
}

# SQLファイルアップロード
upload_sql_files() {
    if [ "$SQL_FILES_EXIST" != true ]; then
        print_warning "SQLファイルが見つからないため、アップロードをスキップします"
        return 0
    fi
    
    print_step "=== SQLファイルアップロード ==="
    
    local sql_upload_count=0
    for sql_file in *.sql; do
        if [ -f "$sql_file" ]; then
            print_info "アップロード: $sql_file"
            if aws s3 cp "$sql_file" "s3://${S3_BUCKET}/init-sql/$sql_file" --region ${REGION} > /dev/null 2>&1; then
                print_success "  ✓ $sql_file"
                ((sql_upload_count++))
            else
                print_error "  ✗ $sql_file アップロード失敗"
            fi
        fi
    done
    
    if [ $sql_upload_count -gt 0 ]; then
        print_success "SQLファイルアップロード完了: ${sql_upload_count}件"
    else
        print_warning "SQLファイルのアップロードに失敗しました"
    fi
}

# テーブル作成実行
execute_table_creation() {
    if [ "$SQL_FILES_EXIST" != true ]; then
        print_warning "SQLファイルがないため、テーブル作成をスキップします"
        return 0
    fi
    
    print_step "=== テーブル作成実行 ==="
    
    print_info "テーブル作成Lambda実行中..."
    print_warning "この処理には数分かかる場合があります"
    
    # Lambda関数実行
    local table_result_file="table_creation_response.json"
    if aws lambda invoke \
        --function-name "${TABLE_CREATOR_FUNCTION_NAME}" \
        --payload '{}' \
        --region "${REGION}" \
        "$table_result_file" > /dev/null 2>&1; then
        
        print_success "テーブル作成Lambda実行完了"
        
        # 結果表示
        if [ -f "$table_result_file" ]; then
            print_info "テーブル作成結果:"
            if command -v python3 &> /dev/null; then
                cat "$table_result_file" | python3 -m json.tool 2>/dev/null || cat "$table_result_file"
            else
                cat "$table_result_file"
            fi
            
            # エラーチェック
            if grep -q '"error"' "$table_result_file" 2>/dev/null; then
                print_warning "テーブル作成でエラーが発生した可能性があります"
            elif grep -q '"created_tables"' "$table_result_file" 2>/dev/null; then
                CREATED_COUNT=$(grep -o '"created_tables":\[.*\]' "$table_result_file" | grep -o ',' | wc -l)
                CREATED_COUNT=$((CREATED_COUNT + 1))
                print_success "テーブル作成成功: ${CREATED_COUNT}個"
            fi
        else
            print_warning "結果ファイルが見つかりませんでした"
        fi
    else
        print_error "テーブル作成Lambda実行失敗"
        print_info "Lambda関数のログを確認してください:"
        echo "aws logs tail /aws/lambda/${TABLE_CREATOR_FUNCTION_NAME} --follow --region ${REGION}"
    fi
}

# テスト用ペイロード作成
create_test_payloads() {
    print_step "=== テスト用ペイロード作成 ==="
    
    # テーブル作成テスト用
    cat > test_table_creation.json << EOF
{}
EOF
    
    # CSV処理テスト用（模擬S3イベント）
    cat > test_csv_processing.json << EOF
{
  "Records": [
    {
      "s3": {
        "bucket": {
          "name": "${S3_BUCKET}"
        },
        "object": {
          "key": "csv/test20250612.csv"
        }
      }
    }
  ]
}
EOF
    
    # クエリ実行テスト用
    cat > test_query_execution.json << EOF
{
  "sql": "SELECT version();",
  "output_format": "json",
  "output_name": "version_check"
}
EOF
    
    print_success "テスト用ペイロード作成完了"
}

# 接続性テスト
test_connectivity() {
    print_step "=== 接続性テスト ==="
    
    # Lambda to RDS接続テスト
    print_info "Lambda -> RDS接続テスト中..."
    
    local connectivity_result_file="connectivity_test_result.json"
    if aws lambda invoke \
        --function-name "${QUERY_EXECUTOR_FUNCTION_NAME}" \
        --payload file://test_query_execution.json \
        --region "${REGION}" \
        "$connectivity_result_file" > /dev/null 2>&1; then
        
        print_success "Lambda関数実行完了"
        
        # 結果確認
        if [ -f "$connectivity_result_file" ]; then
            if grep -q "PostgreSQL" "$connectivity_result_file" 2>/dev/null || grep -q "version" "$connectivity_result_file" 2>/dev/null; then
                print_success "✅ Lambda -> RDS接続: OK"
                
                # PostgreSQLバージョン表示
                if command -v python3 &> /dev/null; then
                    VERSION_INFO=$(cat "$connectivity_result_file" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'body' in data:
        body = json.loads(data['body'])
        print('PostgreSQL接続成功')
    else:
        print('接続確認完了')
except:
    print('結果解析エラー')
" 2>/dev/null || echo "結果解析エラー")
                    print_debug "$VERSION_INFO"
                fi
            else
                print_warning "⚠️  Lambda -> RDS接続: 要確認"
                print_debug "応答内容:"
                cat "$connectivity_result_file" | head -n 5
            fi
        fi
    else
        print_warning "Lambda関数実行でエラーが発生しました"
    fi
    
    # S3アクセステスト
    print_info "Lambda -> S3接続テスト中..."
    
    # テストCSVファイル作成
    echo "test_column,data_column" > test_connectivity.csv
    echo "test_value,$(date)" >> test_connectivity.csv
    
    if aws s3 cp test_connectivity.csv "s3://${S3_BUCKET}/csv/test_connectivity.csv" --region ${REGION} > /dev/null 2>&1; then
        print_success "テストCSVファイルアップロード完了"
        
        # 少し待機してからログ確認
        print_info "CSV処理結果待機中..."
        sleep 15
        
        # CSV処理ログ確認
        print_info "CSV処理ログ確認中..."
        if aws logs filter-log-events \
            --log-group-name "/aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME}" \
            --start-time $(date -d '5 minutes ago' +%s)000 \
            --region "${REGION}" \
            --query 'events[].message' \
            --output text 2>/dev/null | grep -q "CSV処理完了"; then
            print_success "✅ S3 -> Lambda CSV処理: OK"
        else
            print_warning "⚠️  S3 -> Lambda CSV処理: ログ確認が必要"
            print_debug "最新ログを確認してください:"
            print_debug "aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --since 5m --region ${REGION}"
        fi
    else
        print_warning "テストCSVファイルのアップロードに失敗しました"
    fi
    
    # テストファイル削除
    rm -f test_connectivity.csv
    aws s3 rm "s3://${S3_BUCKET}/csv/test_connectivity.csv" --region ${REGION} > /dev/null 2>&1 || true
    
    print_success "接続性テスト完了"
}

# 運用ガイド生成
generate_operations_guide() {
    print_step "=== 運用ガイド生成 ==="
    
    cat > operations_guide.md << EOF
# ETL CSV to RDS PostgreSQL System 運用ガイド

## 📋 デプロイ情報
- **デプロイ日時**: $(date)
- **スタック名**: ${STACK_NAME}
- **リージョン**: ${REGION}
- **プロジェクト名**: ${PROJECT_NAME}
- **S3バケット**: ${S3_BUCKET}
- **RDSエンドポイント**: ${RDS_ENDPOINT}:${RDS_PORT}
- **データベース名**: postgres
- **データベースユーザー**: postgres

## 🚀 Lambda関数一覧

### 1. テーブル作成Lambda
- **関数名**: \`${TABLE_CREATOR_FUNCTION_NAME}\`
- **用途**: SQLファイルからテーブル作成
- **トリガー**: 手動実行
- **実行方法**:
\`\`\`bash
aws lambda invoke \\
  --function-name ${TABLE_CREATOR_FUNCTION_NAME} \\
  --payload '{}' \\
  --region ${REGION} \\
  result.json && cat result.json | python3 -m json.tool
\`\`\`

### 2. CSV処理Lambda
- **関数名**: \`${CSV_PROCESSOR_FUNCTION_NAME}\`
- **用途**: S3のCSVファイル自動処理してRDSに投入
- **トリガー**: S3の\`csv/\`フォルダへのCSVファイル投入
- **実行方法**:
\`\`\`bash
# CSVファイルをS3にアップロードすると自動実行
aws s3 cp sample.csv s3://${S3_BUCKET}/csv/sample.csv --region ${REGION}

# 処理状況確認
aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --follow --region ${REGION}
\`\`\`

### 3. クエリ実行Lambda
- **関数名**: \`${QUERY_EXECUTOR_FUNCTION_NAME}\`
- **用途**: 任意SQLの実行と結果S3出力
- **トリガー**: 手動実行
- **実行方法**:
\`\`\`bash
# 基本的なクエリ実行
aws lambda invoke \\
  --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\
  --payload '{"sql":"SELECT COUNT(*) FROM information_schema.tables;","output_format":"json","output_name":"table_count"}' \\
  --region ${REGION} \\
  result.json && cat result.json | python3 -m json.tool

# CSV形式での出力
aws lambda invoke \\
  --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\
  --payload '{"sql":"SELECT table_name FROM information_schema.tables WHERE table_schema='"'"'public'"'"';","output_format":"csv","output_name":"table_list"}' \\
  --region ${REGION} \\
  result.json
\`\`\`

## 📁 S3フォルダ構成
\`\`\`
s3://${S3_BUCKET}/
├── csv/               # CSV投入フォルダ（自動処理される）
├── init-sql/          # 初期テーブル作成SQL
├── query-results/     # クエリ結果出力フォルダ
└── layers/            # Lambda Layer（psycopg2）
\`\`\`

## 🔧 基本操作手順

### データベーステーブル作成
1. SQLファイルを \`init-sql/\` フォルダにアップロード
\`\`\`bash
aws s3 cp create_tables.sql s3://${S3_BUCKET}/init-sql/ --region ${REGION}
\`\`\`

2. テーブル作成Lambda実行
\`\`\`bash
aws lambda invoke --function-name ${TABLE_CREATOR_FUNCTION_NAME} --payload '{}' --region ${REGION} result.json
\`\`\`

### CSVデータ投入
1. CSVファイルを \`csv/\` フォルダにアップロード（自動で処理される）
\`\`\`bash
aws s3 cp sales_data.csv s3://${S3_BUCKET}/csv/ --region ${REGION}
\`\`\`

2. 処理状況確認
\`\`\`bash
aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --since 5m --region ${REGION}
\`\`\`

### データ分析・クエリ実行
1. 集計クエリ実行例
\`\`\`bash
aws lambda invoke \\
  --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\
  --payload '{"sql":"SELECT department, COUNT(*) as count, AVG(salary) as avg_salary FROM employees GROUP BY department ORDER BY count DESC;","output_format":"csv","output_name":"department_stats"}' \\
  --region ${REGION} \\
  result.json
\`\`\`

2. 結果確認
\`\`\`bash
aws s3 ls s3://${S3_BUCKET}/query-results/ --region ${REGION}
aws s3 cp s3://${S3_BUCKET}/query-results/department_stats_YYYYMMDD_HHMMSS.csv . --region ${REGION}
\`\`\`

## 🔍 トラブルシューティング

### Lambda関数のログ確認
\`\`\`bash
# テーブル作成Lambda
aws logs tail /aws/lambda/${TABLE_CREATOR_FUNCTION_NAME} --follow --region ${REGION}

# CSV処理Lambda
aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --follow --region ${REGION}

# クエリ実行Lambda
aws logs tail /aws/lambda/${QUERY_EXECUTOR_FUNCTION_NAME} --follow --region ${REGION}
\`\`\`

### データベース直接接続
\`\`\`bash
# psqlでの直接接続（VPC内からのみ可能）
psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres

# テーブル一覧確認
psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres -c "\\dt"

# 接続テスト（Lambda経由）
aws lambda invoke \\
  --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\
  --payload '{"sql":"SELECT version();","output_format":"json"}' \\
  --region ${REGION} \\
  version_check.json
\`\`\`

### S3アクセス確認
\`\`\`bash
# バケット内容確認
aws s3 ls s3://${S3_BUCKET}/ --recursive --region ${REGION}

# 特定フォルダの確認
aws s3 ls s3://${S3_BUCKET}/csv/ --region ${REGION}
aws s3 ls s3://${S3_BUCKET}/query-results/ --region ${REGION}
\`\`\`

### ネットワーク・VPC確認
\`\`\`bash
# VPCエンドポイント確認
aws ec2 describe-vpc-endpoints --region ${REGION} --query 'VpcEndpoints[?VpcId==\`$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query 'Stacks[0].Outputs[?OutputKey==\`VPCId\`].OutputValue' --output text)\`].{Service:ServiceName,State:State}'

# セキュリティグループ確認
aws ec2 describe-security-groups --region ${REGION} --filters Name=group-name,Values='*etl-csv-to-rds-postgresql*'
\`\`\`

## 📊 監視・運用

### CloudWatch Logs監視
- Lambda関数の実行ログは30日間保持
- エラー発生時はCloudWatch Logsで詳細確認

### パフォーマンス監視
- RDS Performance Insightsが有効（7日間保持）
- Lambda関数のメトリクス監視

### バックアップ
- RDSの自動バックアップ（7日間保持）
- S3のバージョニング有効

## 🔐 セキュリティ

### ネットワーク分離
- すべてのリソースがプライベートサブネットに配置
- VPCエンドポイント経由でAWSサービスにアクセス
- インターネットへの直接通信なし

### アクセス制御
- IAMロールによる最小権限の原則
- セキュリティグループでポート制限
- S3バケットのパブリックアクセス無効

## 🚀 将来の拡張

### クロスアカウントアクセス対応
S3バケットポリシーを更新して外部アカウントアクセスを許可:
\`\`\`json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountPut",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::OTHER-ACCOUNT-ID:root"
      },
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/csv/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
\`\`\`

### スケーリング対応
- Lambda同時実行数の調整
- RDSの垂直/水平スケーリング
- S3ライフサイクル管理
- Aurora Serverlessへの移行検討

## 🗑️ システム削除

スタック削除時の手順:
\`\`\`bash
# スタック削除
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}

# 一時バケット削除（必要に応じて）
aws s3 rm s3://etl-csv-to-rds-postgresql-temp-files-${ACCOUNT_ID} --recursive --region ${REGION}
aws s3 rb s3://etl-csv-to-rds-postgresql-temp-files-${ACCOUNT_ID} --region ${REGION}
\`\`\`

---
**生成日時**: $(date)  
**バージョン**: 1.0  
**デプロイ環境**: ${REGION}
EOF

    print_success "運用ガイド生成完了: operations_guide.md"
}

# 設定情報保存
save_deployment_info() {
    print_step "=== 設定情報保存 ==="
    
    cat > deployment_info.txt << EOF
# ETL CSV to RDS PostgreSQL System デプロイ情報
# 生成日時: $(date)

# === 基本設定 ===
STACK_NAME="${STACK_NAME}"
REGION="${REGION}"
PROJECT_NAME="${PROJECT_NAME}"
ACCOUNT_ID="${ACCOUNT_ID}"

# === リソース情報 ===
S3_BUCKET="${S3_BUCKET}"
TABLE_CREATOR_FUNCTION_NAME="${TABLE_CREATOR_FUNCTION_NAME}"
CSV_PROCESSOR_FUNCTION_NAME="${CSV_PROCESSOR_FUNCTION_NAME}"
QUERY_EXECUTOR_FUNCTION_NAME="${QUERY_EXECUTOR_FUNCTION_NAME}"
RDS_ENDPOINT="${RDS_ENDPOINT}"
RDS_PORT="${RDS_PORT}"

# === データベース設定 ===
DB_USER="postgres"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="postgres"

# === 一時バケット ===
TEMP_BUCKET_NAME="etl-csv-to-rds-postgresql-temp-files-${ACCOUNT_ID}"

# === クイックコマンド ===

# テーブル作成
aws lambda invoke --function-name ${TABLE_CREATOR_FUNCTION_NAME} --payload '{}' --region ${REGION} result.json

# CSVアップロード（自動処理）
aws s3 cp sample.csv s3://${S3_BUCKET}/csv/sample.csv --region ${REGION}

# データ確認
aws lambda invoke --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} --payload '{"sql":"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='"'"'public'"'"';","output_format":"json"}' --region ${REGION} count.json

# ログ確認
aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --follow --region ${REGION}

# データベース直接接続
psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres

# スタック削除
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}
EOF

    print_success "設定情報保存完了: deployment_info.txt"
}

# 一時ファイル削除
cleanup_temp_files() {
    print_step "=== 一時ファイル削除 ==="
    
    local temp_files=(
        "table_creator.zip"
        "csv_processor.zip"
        "query_executor.zip"
        "test_table_creation.json"
        "test_csv_processing.json"
        "test_query_execution.json"
        "table_creation_response.json"
        "connectivity_test_result.json"
    )
    
    local cleaned_count=0
    for temp_file in "${temp_files[@]}"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            ((cleaned_count++))
        fi
    done
    
    if [ $cleaned_count -gt 0 ]; then
        print_success "一時ファイル削除完了: ${cleaned_count}件"
    else
        print_debug "削除対象の一時ファイルはありませんでした"
    fi
}

# 最終結果表示
show_deployment_summary() {
    print_step "=== デプロイ結果サマリー ==="
    
    echo ""
    echo "🎉 =============================================="
    echo "🎉   ETL CSV to RDS PostgreSQL System"
    echo "🎉        デプロイ完了！"
    echo "🎉 =============================================="
    echo ""
    
    echo "📋 **システム情報**"
    echo "   ✅ デプロイモード: ${DEPLOY_MODE:-UPDATE}"
    echo "   ✅ スタック名: ${STACK_NAME}"
    echo "   ✅ リージョン: ${REGION}"
    echo "   ✅ S3バケット: ${S3_BUCKET}"
    echo "   ✅ RDSエンドポイント: ${RDS_ENDPOINT}:${RDS_PORT}"
    echo ""
    
    echo "🔧 **Lambda関数（3つ）**"
    echo "   1. 📋 テーブル作成: ${TABLE_CREATOR_FUNCTION_NAME}"
    echo "   2. 📊 CSV処理: ${CSV_PROCESSOR_FUNCTION_NAME}"
    echo "   3. 🔍 クエリ実行: ${QUERY_EXECUTOR_FUNCTION_NAME}"
    echo ""
    
    echo "📁 **S3フォルダ構成**"
    echo "   📁 csv/           → CSVファイル投入（自動処理）"
    echo "   📁 init-sql/      → テーブル作成SQL"
    echo "   📁 query-results/ → クエリ結果出力"
    echo "   📁 layers/        → Lambda Layer"
    echo ""
    
    if [ "$SQL_FILES_EXIST" = true ]; then
        echo "✅ **SQLファイル**: アップロード済み・テーブル作成実行済み"
    else
        echo "⚠️  **SQLファイル**: 見つからず（後で手動追加可能）"
    fi
    echo ""
    
    echo "🚀 **次のステップ**"
    echo "   1. 運用ガイド確認: cat operations_guide.md"
    echo "   2. 接続テスト実行:"
    echo "      aws lambda invoke --function-name ${QUERY_EXECUTOR_FUNCTION_NAME} \\"
    echo "        --payload '{\"sql\":\"SELECT version();\",\"output_format\":\"json\"}' \\"
    echo "        --region ${REGION} version.json"
    echo "   3. CSVテストデータ投入:"
    echo "      aws s3 cp test.csv s3://${S3_BUCKET}/csv/test.csv --region ${REGION}"
    echo ""
    
    echo "📖 **ドキュメント**"
    echo "   📄 運用ガイド: operations_guide.md"
    echo "   📄 設定情報: deployment_info.txt"
    echo ""
    
    echo "🔧 **トラブルシューティング**"
    echo "   📝 ログ確認: aws logs tail /aws/lambda/${CSV_PROCESSOR_FUNCTION_NAME} --follow --region ${REGION}"
    echo "   🗄️  データベース接続: psql -h ${RDS_ENDPOINT} -p ${RDS_PORT} -U postgres -d postgres"
    echo "   🔍 S3内容確認: aws s3 ls s3://${S3_BUCKET}/ --recursive --region ${REGION}"
    echo ""
    
    echo "💡 **重要な特徴**"
    echo "   🔒 完全プライベート環境（VPCエンドポイント使用）"
    echo "   🚀 NATゲートウェイ不要（コスト効率的）"
    echo "   📊 3つのLambda関数で役割分離"
    echo "   🔄 S3トリガーによる自動CSV処理"
    echo "   📈 将来のクロスアカウント対応準備済み"
    echo ""
    
    echo "🎯 **システム削除方法**"
    echo "   aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}"
    echo ""
    
    echo "🎉 デプロイ成功おめでとうございます！ 🎉"
    echo ""
}

# メイン処理
main() {
    print_info "=== ETL CSV to RDS PostgreSQL System デプロイスクリプト（完全版・改善版） ==="
    print_info "開始日時: $(date)"
    echo ""
    
    # Step 1: 前提条件チェック
    check_prerequisites
    echo ""
    
    # Step 2: VPC設定検証
    validate_vpc_configuration
    echo ""
    
    # Step 3: 必要ファイル確認
    SQL_FILES_EXIST=true
    check_required_files || SQL_FILES_EXIST=false
    echo ""
    
    # Step 4: Lambda関数ZIPファイル作成
    create_lambda_zips
    echo ""
    
    # Step 5: 既存スタック確認・一時バケット管理
    manage_temp_bucket
    echo ""
    
    # Step 6: ファイルアップロード
    upload_files
    echo ""
    
    # Step 7: CloudFormationデプロイ
    if deploy_cloudformation; then
        DEPLOY_MODE="SUCCESS"
        echo ""
        
        # Step 8: リソース情報取得
        if get_resource_info; then
            echo ""
            
            # Step 9: 本番S3バケットにファイル移動
            move_files_to_production
            echo ""
            
            # Step 10: SQLファイルアップロード
            upload_sql_files
            echo ""
            
            # Step 11: テーブル作成実行
            execute_table_creation
            echo ""
            
            # Step 12: テスト用ペイロード作成・接続性テスト
            create_test_payloads
            test_connectivity
            echo ""
            
            # Step 13: ドキュメント生成
            generate_operations_guide
            save_deployment_info
            echo ""
            
            # Step 14: 一時ファイル削除
            cleanup_temp_files
            echo ""
            
            # Step 15: 最終結果表示
            show_deployment_summary
            
        else
            print_error "リソース情報の取得に失敗しました"
            exit 1
        fi
    else
        print_error "CloudFormationデプロイに失敗しました"
        exit 1
    fi
}

# スクリプト実行
main "$@"

exit 0