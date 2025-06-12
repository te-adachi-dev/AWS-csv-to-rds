#!/bin/bash

# 強制リソース削除スクリプト
set +e  # エラーで停止しない

REGION="us-east-2"
VPC_ID="vpc-04c13c59c875c5d7b"
SG_RDS="sg-0e8dc916a0928eb5a"
SG_LAMBDA="sg-0d27d43688f9cdddf"
TEMP_BUCKET="etl-csv-to-rds-postgresql-temp-files-442901050053"

echo "=== 強制リソース削除開始 ==="

# 1. VPCエンドポイント削除
echo "1. VPCエンドポイント削除中..."
VPC_ENDPOINT_IDS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null)
for endpoint_id in $VPC_ENDPOINT_IDS; do
    if [ "$endpoint_id" != "" ] && [ "$endpoint_id" != "None" ]; then
        echo "  削除: $endpoint_id"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $endpoint_id --region $REGION 2>/dev/null
    fi
done

# 2. セキュリティグループ依存関係削除
echo "2. セキュリティグループ削除中..."
aws ec2 revoke-security-group-ingress \
    --group-id $SG_RDS \
    --protocol tcp \
    --port 5432 \
    --source-group $SG_LAMBDA \
    --region $REGION 2>/dev/null

aws ec2 delete-security-group --group-id $SG_RDS --region $REGION 2>/dev/null
aws ec2 delete-security-group --group-id $SG_LAMBDA --region $REGION 2>/dev/null

# 3. サブネット削除
echo "3. サブネット削除中..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text --region $REGION 2>/dev/null)
for subnet_id in $SUBNET_IDS; do
    if [ "$subnet_id" != "" ] && [ "$subnet_id" != "None" ]; then
        echo "  削除: $subnet_id"
        aws ec2 delete-subnet --subnet-id $subnet_id --region $REGION 2>/dev/null
    fi
done

# 4. ルートテーブル削除
echo "4. ルートテーブル削除中..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text --region $REGION 2>/dev/null)
for rt_id in $ROUTE_TABLE_IDS; do
    if [ "$rt_id" != "" ] && [ "$rt_id" != "None" ]; then
        echo "  削除: $rt_id"
        aws ec2 delete-route-table --route-table-id $rt_id --region $REGION 2>/dev/null
    fi
done

# 5. インターネットゲートウェイ削除
echo "5. インターネットゲートウェイ削除中..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text --region $REGION 2>/dev/null)
if [ "$IGW_ID" != "None" ] && [ "$IGW_ID" != "" ]; then
    echo "  デタッチ: $IGW_ID"
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION 2>/dev/null
    echo "  削除: $IGW_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $REGION 2>/dev/null
fi

# 6. VPC削除
echo "6. VPC削除中..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null

# 7. 一時バケット削除
echo "7. 一時バケット削除中..."
aws s3 rm s3://$TEMP_BUCKET --recursive --region $REGION 2>/dev/null
aws s3 rb s3://$TEMP_BUCKET --region $REGION 2>/dev/null

# 8. Lambda Layer削除
echo "8. Lambda Layer削除中..."
LAYER_ARNS=$(aws lambda list-layers --query "Layers[?contains(LayerName, 'etl-csv-to-rds-postgresql')].LayerArn" --output text --region $REGION 2>/dev/null)
for layer_arn in $LAYER_ARNS; do
    if [ "$layer_arn" != "" ]; then
        LAYER_NAME=$(echo $layer_arn | cut -d':' -f7)
        VERSIONS=$(aws lambda list-layer-versions --layer-name $LAYER_NAME --query 'LayerVersions[].Version' --output text --region $REGION 2>/dev/null)
        for version in $VERSIONS; do
            if [ "$version" != "" ]; then
                echo "  削除: $LAYER_NAME:$version"
                aws lambda delete-layer-version --layer-name $LAYER_NAME --version-number $version --region $REGION 2>/dev/null
            fi
        done
    fi
done

echo "=== 強制削除完了 ==="

# 9. 最終確認
echo "9. 最終状態確認..."
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name etl-csv-to-rds-postgresql --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
echo "スタック状態: $STACK_STATUS"

# RDS確認
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier etl-csv-to-rds-postgresql-postgres-20250611 --region $REGION --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "削除済み")
echo "RDS状態: $RDS_STATUS"

echo "✅ 強制削除処理完了"
echo "注意: RDSの削除完了まで数分かかる場合があります"