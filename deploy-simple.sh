#!/bin/bash

# シンプルなETLデプロイスクリプト
# 使用方法: ./deploy-simple.sh <source-bucket-name>

set -e

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <source-bucket-name>"
    echo "例: $0 20250613-source-bucket"
    exit 1
fi

SOURCE_BUCKET=$1
STACK_NAME="etl-csv-to-rds-postgresql"

echo "=== ETL System 段階的デプロイ ==="
echo "Source Bucket: $SOURCE_BUCKET"
echo "Stack Name: $STACK_NAME"
echo ""

# Step 1: ファイルアップロード
echo "Step 1: CloudFormationテンプレートとアーティファクトをS3にアップロード"
aws s3 sync cfn-templates/ s3://$SOURCE_BUCKET/cfn-templates/
aws s3 sync lambda-code/ s3://$SOURCE_BUCKET/lambda-code/
aws s3 sync init-sql/ s3://$SOURCE_BUCKET/init-sql/
aws s3 sync layers/ s3://$SOURCE_BUCKET/layers/

echo "✓ アップロード完了"
echo ""

# Step 2: メインスタックデプロイ
echo "Step 2: メインスタックデプロイ"

# スタック存在確認
if aws cloudformation describe-stacks --stack-name $STACK_NAME >/dev/null 2>&1; then
    echo "既存スタックを更新します..."
    
    # Change Set作成
    CHANGE_SET_NAME="changeset-$(date +%Y%m%d%H%M%S)"
    
    aws cloudformation create-change-set \
        --stack-name $STACK_NAME \
        --template-url https://$SOURCE_BUCKET.s3.$AWS_DEFAULT_REGION.amazonaws.com/cfn-templates/01-main-stack.yaml \
        --parameters \
            ParameterKey=ProjectName,ParameterValue=$STACK_NAME \
            ParameterKey=SourceBucket,ParameterValue=$SOURCE_BUCKET \
            ParameterKey=DBMasterPassword,ParameterValue=TestPassword123! \
        --capabilities CAPABILITY_NAMED_IAM \
        --change-set-name $CHANGE_SET_NAME
    
    echo "Change Set作成完了。変更内容："
    aws cloudformation describe-change-set \
        --stack-name $STACK_NAME \
        --change-set-name $CHANGE_SET_NAME \
        --query 'Changes[].{Action:Action,Type:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId}' \
        --output table
    
    read -p "変更を適用しますか？ (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws cloudformation execute-change-set \
            --stack-name $STACK_NAME \
            --change-set-name $CHANGE_SET_NAME
        
        echo "更新実行中..."
        aws cloudformation wait stack-update-complete --stack-name $STACK_NAME
        echo "✓ スタック更新完了"
    else
        aws cloudformation delete-change-set \
            --stack-name $STACK_NAME \
            --change-set-name $CHANGE_SET_NAME
        echo "変更をキャンセルしました"
        exit 0
    fi
else
    echo "新規スタックを作成します..."
    
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-url https://$SOURCE_BUCKET.s3.$AWS_DEFAULT_REGION.amazonaws.com/cfn-templates/01-main-stack.yaml \
        --parameters \
            ParameterKey=ProjectName,ParameterValue=$STACK_NAME \
            ParameterKey=SourceBucket,ParameterValue=$SOURCE_BUCKET \
            ParameterKey=DBMasterPassword,ParameterValue=TestPassword123! \
        --capabilities CAPABILITY_NAMED_IAM \
        --tags \
            Key=Environment,Value=poc \
            Key=Project,Value=ETL-System
    
    echo "作成実行中..."
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
    echo "✓ スタック作成完了"
fi

echo ""

# Step 3: 結果確認
echo "Step 3: デプロイ結果確認"

echo "スタック出力:"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
    --output table

# データバケット名取得
DATA_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
    --output text)

echo ""
echo "✓ デプロイ完了！"
echo ""
echo "=== 次のステップ ==="
echo "1. テスト用CSVファイルをアップロード:"
echo "   aws s3 cp your-file.csv s3://$DATA_BUCKET/csv/"
echo ""
echo "2. Lambda関数ログの確認:"
echo "   aws logs tail /aws/lambda/$STACK_NAME-csv-processor --follow"
echo ""
echo "3. RDS接続確認 (VPC内のEC2から):"
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
    --output text)
echo "   psql -h $RDS_ENDPOINT -U postgres -d postgres"
