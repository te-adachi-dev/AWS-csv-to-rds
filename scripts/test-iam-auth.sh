#!/bin/bash

# IAMデータベース認証のテストスクリプト

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== IAMデータベース認証テストスクリプト ===${NC}"

# Terraformアウトプットから値を取得
cd terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_PORT=$(terraform output -raw rds_port)
RDS_RESOURCE_ID=$(terraform output -raw rds_resource_id)
AWS_REGION=$(terraform output -json | jq -r '.vpc_id.value' | cut -d: -f4)
cd ..

echo -e "${YELLOW}RDS情報:${NC}"
echo "Endpoint: $RDS_ENDPOINT"
echo "Port: $RDS_PORT"
echo "Resource ID: $RDS_RESOURCE_ID"
echo "Region: $AWS_REGION"

# テストユーザーリスト
USERS=("test_readonly" "test_fullaccess" "test_limited")

# SSL証明書のダウンロード
echo -e "\n${YELLOW}SSL証明書をダウンロード中...${NC}"
if [ ! -f "rds-ca-2019-root.pem" ]; then
    wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
    mv global-bundle.pem rds-ca-2019-root.pem
fi

# 各ユーザーでテスト
for USER in "${USERS[@]}"; do
    echo -e "\n${GREEN}=== $USER のテスト ===${NC}"
    
    # 認証トークンを生成
    echo -e "${YELLOW}認証トークンを生成中...${NC}"
    TOKEN=$(aws rds generate-db-auth-token \
        --hostname "$RDS_ENDPOINT" \
        --port "$RDS_PORT" \
        --region "$AWS_REGION" \
        --username "$USER")
    
    echo "トークン生成完了（最初の50文字）: ${TOKEN:0:50}..."
    
    # PostgreSQLで接続テスト
    echo -e "${YELLOW}PostgreSQL接続テスト中...${NC}"
    
    # 接続文字列を作成
    CONNECTION_STRING="host=$RDS_ENDPOINT port=$RDS_PORT dbname=postgres user=$USER sslmode=require sslrootcert=rds-ca-2019-root.pem"
    
    # パスワードとして認証トークンを使用
    export PGPASSWORD="$TOKEN"
    
    # 権限テスト用のSQLを実行
    case $USER in
        "test_readonly")
            echo -e "${YELLOW}読み取り専用ユーザーのテスト${NC}"
            psql "$CONNECTION_STRING" -c "SELECT * FROM accounts LIMIT 5;" || echo -e "${RED}読み取り失敗${NC}"
            psql "$CONNECTION_STRING" -c "INSERT INTO accounts (name, email) VALUES ('test', 'test@example.com');" 2>&1 | grep -q "ERROR" && echo -e "${GREEN}書き込み拒否: 期待通り${NC}" || echo -e "${RED}書き込みできてしまった！${NC}"
            ;;
        "test_fullaccess")
            echo -e "${YELLOW}フルアクセスユーザーのテスト${NC}"
            psql "$CONNECTION_STRING" -c "SELECT * FROM accounts LIMIT 5;" || echo -e "${RED}読み取り失敗${NC}"
            psql "$CONNECTION_STRING" -c "INSERT INTO accounts (name, email) VALUES ('test_$RANDOM', 'test_$RANDOM@example.com');" && echo -e "${GREEN}書き込み成功: 期待通り${NC}" || echo -e "${RED}書き込み失敗${NC}"
            ;;
        "test_limited")
            echo -e "${YELLOW}制限付きユーザーのテスト${NC}"
            psql "$CONNECTION_STRING" -c "SELECT * FROM accounts LIMIT 5;" || echo -e "${RED}読み取り失敗${NC}"
            psql "$CONNECTION_STRING" -c "SELECT * FROM products LIMIT 5;" 2>&1 | grep -q "ERROR" && echo -e "${GREEN}他テーブルアクセス拒否: 期待通り${NC}" || echo -e "${RED}他テーブルにアクセスできてしまった！${NC}"
            ;;
    esac
    
    unset PGPASSWORD
done

echo -e "\n${GREEN}=== テスト完了 ===${NC}"
