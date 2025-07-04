#!/bin/bash

# パブリックアクセスを無効化してセキュリティを元に戻すスクリプト

set -e

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${RED}=== パブリックアクセスを無効化 ===${NC}"

cd terraform

echo -e "${YELLOW}現在の設定を確認中...${NC}"
terraform plan -var-file=terraform.tfvars | grep -E "(publicly_accessible|enable_public_access)" || true

echo -e "${YELLOW}パブリックアクセスを無効化しています...${NC}"
terraform apply -var-file=terraform.tfvars -auto-approve

echo -e "${GREEN}セキュリティ設定を元に戻しました${NC}"
