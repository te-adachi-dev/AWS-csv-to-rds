#!/bin/bash

# IAMデータベース認証テスト環境のセットアップスクリプト

set -e

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== IAMデータベース認証テスト環境セットアップ ===${NC}"

# 現在のIPアドレスを取得
echo -e "${YELLOW}現在のグローバルIPアドレスを取得中...${NC}"
MY_IP=$(curl -s ifconfig.me)
echo "あなたのIP: $MY_IP"

# terraform-iam-test.tfvarsを作成
echo -e "${YELLOW}terraform-iam-test.tfvarsを作成中...${NC}"
cat > terraform/terraform-iam-test.tfvars <<EOF
# IAMデータベース認証テスト用の設定

# パブリックアクセスを有効化（警告：セキュリティリスクあり）
enable_public_access = true

# 許可するIPアドレス
allowed_ips = ["$MY_IP/32"]

# その他の設定は既存のterraform.tfvarsから継承
EOF

echo -e "${GREEN}terraform-iam-test.tfvarsを作成しました${NC}"

# 既存のterraform.tfvarsの内容を追加
if [ -f "terraform/terraform.tfvars" ]; then
    echo -e "${YELLOW}既存のterraform.tfvarsから設定をコピー中...${NC}"
    echo "" >> terraform/terraform-iam-test.tfvars
    echo "# 既存の設定" >> terraform/terraform-iam-test.tfvars
    grep -E "^(aws_region|project_name|source_bucket|db_master_username|db_master_password)" terraform/terraform.tfvars >> terraform/terraform-iam-test.tfvars || true
fi

echo -e "${GREEN}セットアップ完了！${NC}"
echo -e "${YELLOW}次のステップ:${NC}"
echo "1. cd terraform"
echo "2. terraform plan -var-file=terraform-iam-test.tfvars"
echo "3. terraform apply -var-file=terraform-iam-test.tfvars"
