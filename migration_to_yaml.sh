#!/bin/bash

# 既存環境からYAML単体デプロイへの移行スクリプト
set -e

echo "=== ETL システム YAML単体デプロイ移行開始 ==="

# 設定変数
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-2"
DEPLOY_BUCKET="etl-csv-deployment-${ACCOUNT_ID}-20250613"
STACK_NAME="etl-csv-to-rds-postgresql"

echo "アカウントID: ${ACCOUNT_ID}"
echo "リージョン: ${REGION}"
echo "デプロイバケット: ${DEPLOY_BUCKET}"

# Step 1: ディレクトリ構造作成
echo "=== Step 1: ディレクトリ構造作成 ==="
mkdir -p etl-yaml-deploy/{lambda-code,init-sql,layers}

# Step 2: 既存ファイルをコピー
echo "=== Step 2: 既存ファイルコピー ==="

# Lambda コードファイル
cp csv_processor.py etl-yaml-deploy/lambda-code/
cp query_executor.py etl-yaml-deploy/lambda-code/  
cp table_creator.py etl-yaml-deploy/lambda-code/

# psycopg2レイヤー
cp psycopg2-layer-python311-fixed.zip etl-yaml-deploy/layers/psycopg2-layer.zip

# SQLファイル
cp create_table_afc_accounts.sql etl-yaml-deploy/init-sql/01_afc_accounts.sql

echo "✅ ファイルコピー完了"

# Step 3: 完全版CloudFormationテンプレート作成
echo "=== Step 3: 完全版テンプレート作成 ==="

cat > etl-yaml-deploy/complete-etl-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Complete ETL CSV to RDS PostgreSQL System - Deploy with YAML only'

Parameters:
  ProjectName:
    Type: String
    Default: 'etl-csv-to-rds-postgresql'
    Description: 'Project name for resource naming'

  DBMasterUsername:
    Type: String
    Default: 'postgres'
    Description: 'RDS Master Username'

  DBMasterPassword:
    Type: String
    NoEcho: true
    MinLength: 8
    Description: 'RDS Master Password (minimum 8 characters)'
    Default: 'TestPassword123!'

  SourceBucket:
    Type: String
    Description: 'S3 Bucket containing Lambda code and SQL files'

  CSVProcessorCodeKey:
    Type: String
    Default: 'lambda-code/csv_processor.py'
    Description: 'S3 Key for CSV Processor Lambda code'

  QueryExecutorCodeKey:
    Type: String
    Default: 'lambda-code/query_executor.py'
    Description: 'S3 Key for Query Executor Lambda code'

  TableCreatorCodeKey:
    Type: String
    Default: 'lambda-code/table_creator.py'
    Description: 'S3 Key for Table Creator Lambda code'

  Psycopg2LayerKey:
    Type: String
    Default: 'layers/psycopg2-layer.zip'
    Description: 'S3 Key for psycopg2 Lambda Layer'

  InitSqlPrefix:
    Type: String
    Default: 'init-sql/'
    Description: 'S3 Prefix for initialization SQL files'

Resources:
  # VPC
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-vpc'

  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-igw'

  InternetGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  # Subnets
  PrivateSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: 10.0.1.0/24
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-private-subnet-1'

  PrivateSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: 10.0.2.0/24
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-private-subnet-2'

  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: 10.0.101.0/24
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-public-subnet-1'

  # Route Tables
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-public-rt'

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: InternetGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet1

  PrivateRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-private-rt'

  PrivateSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable
      SubnetId: !Ref PrivateSubnet1

  PrivateSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable
      SubnetId: !Ref PrivateSubnet2

  # データ用S3バケット
  DataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${ProjectName}-data-${AWS::AccountId}-${AWS::StackId}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      VersioningConfiguration:
        Status: Enabled
      NotificationConfiguration:
        LambdaConfigurations:
          - Event: s3:ObjectCreated:*
            Function: !GetAtt CSVProcessorLambdaFunction.Arn
            Filter:
              S3Key:
                Rules:
                  - Name: prefix
                    Value: csv/
                  - Name: suffix
                    Value: .csv
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-data-bucket'

  # S3 VPC Endpoint
  S3VPCEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub 'com.amazonaws.${AWS::Region}.s3'
      VpcEndpointType: Gateway
      RouteTableIds:
        - !Ref PrivateRouteTable

  # Lambda VPC Endpoint  
  LambdaVPCEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub 'com.amazonaws.${AWS::Region}.lambda'
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnet1
        - !Ref PrivateSubnet2
      SecurityGroupIds:
        - !Ref VPCEndpointSecurityGroup
      PrivateDnsEnabled: true

  # CloudWatch Logs VPC Endpoint
  CloudWatchLogsVPCEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub 'com.amazonaws.${AWS::Region}.logs'
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnet1
        - !Ref PrivateSubnet2
      SecurityGroupIds:
        - !Ref VPCEndpointSecurityGroup
      PrivateDnsEnabled: true

  # Security Groups
  VPCEndpointSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for VPC Endpoints
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 10.0.0.0/16
          Description: HTTPS from VPC
      SecurityGroupEgress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: HTTPS to anywhere

  LambdaSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for Lambda
      VpcId: !Ref VPC
      SecurityGroupEgress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: HTTPS for S3/AWS API access
        - IpProtocol: tcp
          FromPort: 5432
          ToPort: 5432
          CidrIp: 10.0.0.0/16
          Description: PostgreSQL access to RDS

  RDSSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for RDS
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 5432
          ToPort: 5432
          SourceSecurityGroupId: !Ref LambdaSecurityGroup
          Description: PostgreSQL from Lambda

  # RDS Subnet Group
  DBSubnetGroup:
    Type: AWS::RDS::DBSubnetGroup
    Properties:
      DBSubnetGroupDescription: Subnet group for RDS
      SubnetIds:
        - !Ref PrivateSubnet1
        - !Ref PrivateSubnet2

  # RDS Instance
  RDSInstance:
    Type: AWS::RDS::DBInstance
    Properties:
      DBInstanceIdentifier: !Sub '${ProjectName}-postgres-${AWS::StackId}'
      DBInstanceClass: db.t3.micro
      Engine: postgres
      EngineVersion: '15.8'
      AllocatedStorage: 20
      StorageType: gp2
      MasterUsername: !Ref DBMasterUsername
      MasterUserPassword: !Ref DBMasterPassword
      VPCSecurityGroups:
        - !Ref RDSSecurityGroup
      DBSubnetGroupName: !Ref DBSubnetGroup
      BackupRetentionPeriod: 7
      MultiAZ: false
      PubliclyAccessible: false
      StorageEncrypted: true
      DeletionProtection: false

  # Lambda Execution Role
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: S3Access
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - 's3:GetObject'
                  - 's3:ListBucket'
                  - 's3:PutObject'
                  - 's3:DeleteObject'
                Resource:
                  - !Sub '${SourceBucket}/*'
                  - !Sub '${SourceBucket}'
                  - !Sub '${DataBucket}/*'
                  - !Sub '${DataBucket}'

  # カスタムリソース用Lambda実行ロール
  CustomResourceLambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: InvokeLambdaPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - lambda:InvokeFunction
                Resource: !Sub 'arn:aws:lambda:${AWS::Region}:${AWS::AccountId}:function:${ProjectName}-table-creator'

  # psycopg2 Lambda Layer
  Psycopg2Layer:
    Type: AWS::Lambda::LayerVersion
    Properties:
      LayerName: !Sub '${ProjectName}-psycopg2-layer'
      Description: 'psycopg2 library for PostgreSQL connectivity'
      Content:
        S3Bucket: !Ref SourceBucket
        S3Key: !Ref Psycopg2LayerKey
      CompatibleRuntimes:
        - python3.11

  # Lambda Function 1: Table Creator
  TableCreatorLambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${ProjectName}-table-creator'
      Runtime: python3.11
      Handler: table_creator.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Timeout: 900
      MemorySize: 1024
      VpcConfig:
        SecurityGroupIds:
          - !Ref LambdaSecurityGroup
        SubnetIds:
          - !Ref PrivateSubnet1
          - !Ref PrivateSubnet2
      Environment:
        Variables:
          DB_HOST: !GetAtt RDSInstance.Endpoint.Address
          DB_PORT: !GetAtt RDSInstance.Endpoint.Port
          DB_NAME: postgres
          DB_USER: !Ref DBMasterUsername
          DB_PASSWORD: !Ref DBMasterPassword
          S3_BUCKET: !Ref SourceBucket
          SQL_PREFIX: !Ref InitSqlPrefix
      Code:
        S3Bucket: !Ref SourceBucket
        S3Key: !Ref TableCreatorCodeKey
      Layers:
        - !Ref Psycopg2Layer

  # Lambda Function 2: CSV Processor
  CSVProcessorLambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${ProjectName}-csv-processor'
      Runtime: python3.11
      Handler: csv_processor.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Timeout: 900
      MemorySize: 1024
      VpcConfig:
        SecurityGroupIds:
          - !Ref LambdaSecurityGroup
        SubnetIds:
          - !Ref PrivateSubnet1
          - !Ref PrivateSubnet2
      Environment:
        Variables:
          DB_HOST: !GetAtt RDSInstance.Endpoint.Address
          DB_PORT: !GetAtt RDSInstance.Endpoint.Port
          DB_NAME: postgres
          DB_USER: !Ref DBMasterUsername
          DB_PASSWORD: !Ref DBMasterPassword
          S3_BUCKET: !Ref DataBucket
      Code:
        S3Bucket: !Ref SourceBucket
        S3Key: !Ref CSVProcessorCodeKey
      Layers:
        - !Ref Psycopg2Layer

  # Lambda Function 3: Query Executor
  QueryExecutorLambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${ProjectName}-query-executor'
      Runtime: python3.11
      Handler: query_executor.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Timeout: 900
      MemorySize: 1024
      VpcConfig:
        SecurityGroupIds:
          - !Ref LambdaSecurityGroup
        SubnetIds:
          - !Ref PrivateSubnet1
          - !Ref PrivateSubnet2
      Environment:
        Variables:
          DB_HOST: !GetAtt RDSInstance.Endpoint.Address
          DB_PORT: !GetAtt RDSInstance.Endpoint.Port
          DB_NAME: postgres
          DB_USER: !Ref DBMasterUsername
          DB_PASSWORD: !Ref DBMasterPassword
          S3_BUCKET: !Ref DataBucket
          OUTPUT_PREFIX: 'query-results/'
      Code:
        S3Bucket: !Ref SourceBucket
        S3Key: !Ref QueryExecutorCodeKey
      Layers:
        - !Ref Psycopg2Layer

  # カスタムリソース用Lambda関数
  CustomResourceLambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${ProjectName}-custom-resource'
      Runtime: python3.11
      Handler: index.lambda_handler
      Role: !GetAtt CustomResourceLambdaExecutionRole.Arn
      Timeout: 900
      MemorySize: 512
      Environment:
        Variables:
          TABLE_CREATOR_FUNCTION_NAME: !Ref TableCreatorLambdaFunction
      Code:
        ZipFile: !Sub |
          import json
          import boto3
          import cfnresponse
          
          def lambda_handler(event, context):
              print(f"Event: {json.dumps(event)}")
              
              try:
                  request_type = event['RequestType']
                  
                  if request_type == 'Create':
                      # 初回デプロイ時のみテーブル作成実行
                      lambda_client = boto3.client('lambda')
                      table_creator_function = event['ResourceProperties']['TableCreatorFunctionName']
                      
                      print(f"テーブル作成Lambda実行: {table_creator_function}")
                      
                      response = lambda_client.invoke(
                          FunctionName=table_creator_function,
                          InvocationType='RequestResponse',
                          Payload=json.dumps({})
                      )
                      
                      result = json.loads(response['Payload'].read())
                      print(f"テーブル作成結果: {result}")
                      
                      cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                          'Message': 'テーブル作成完了',
                          'Result': result
                      }, 'TableCreationResource')
                      
                  elif request_type == 'Update':
                      cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                          'Message': '更新時はスキップ'
                      }, 'TableCreationResource')
                      
                  elif request_type == 'Delete':
                      cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                          'Message': '削除時はスキップ'
                      }, 'TableCreationResource')
                      
              except Exception as e:
                  print(f"エラー: {str(e)}")
                  cfnresponse.send(event, context, cfnresponse.FAILED, {
                      'Error': str(e)
                  }, 'TableCreationResource')

  # カスタムリソース（初回のみテーブル作成実行）
  TableCreationCustomResource:
    Type: AWS::CloudFormation::CustomResource
    DependsOn:
      - TableCreatorLambdaFunction
      - DataBucket
    Properties:
      ServiceToken: !GetAtt CustomResourceLambdaFunction.Arn
      TableCreatorFunctionName: !Ref TableCreatorLambdaFunction

  # S3からLambdaへの実行権限
  CSVProcessorLambdaPermission:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref CSVProcessorLambdaFunction
      Action: lambda:InvokeFunction
      Principal: s3.amazonaws.com
      SourceArn: !Sub '${DataBucket}/*'

Outputs:
  DataBucketName:
    Description: Name of the S3 bucket for CSV data and results
    Value: !Ref DataBucket

  SourceBucketName:
    Description: Name of the S3 bucket containing Lambda code and SQL files
    Value: !Ref SourceBucket

  TableCreatorFunction:
    Description: Table Creator Lambda Function Name
    Value: !Ref TableCreatorLambdaFunction

  CSVProcessorFunction:
    Description: CSV Processor Lambda Function Name
    Value: !Ref CSVProcessorLambdaFunction

  QueryExecutorFunction:
    Description: Query Executor Lambda Function Name
    Value: !Ref QueryExecutorLambdaFunction

  CustomResourceFunction:
    Description: Custom Resource Lambda Function Name
    Value: !Ref CustomResourceLambdaFunction

  RDSEndpoint:
    Description: RDS PostgreSQL Endpoint
    Value: !GetAtt RDSInstance.Endpoint.Address

  RDSPort:
    Description: RDS PostgreSQL Port
    Value: !GetAtt RDSInstance.Endpoint.Port

  DatabaseName:
    Description: Database Name
    Value: postgres

  DatabaseUser:
    Description: Database Username
    Value: !Ref DBMasterUsername
EOF

echo "✅ CloudFormationテンプレート作成完了"

# Step 4: サンプルSQLファイル追加
echo "=== Step 4: サンプルSQLファイル追加 ==="

cat > etl-yaml-deploy/init-sql/02_sample_tables.sql << 'EOF'
-- サンプルテーブル作成
CREATE TABLE IF NOT EXISTS sample_users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(200),
    age INTEGER,
    department VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sample_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    product_name VARCHAR(200),
    amount DECIMAL(10,2),
    order_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

echo "✅ サンプルSQLファイル作成完了"

# Step 5: デプロイバケット作成
echo "=== Step 5: デプロイバケット作成 ==="

if aws s3 ls s3://${DEPLOY_BUCKET} 2>/dev/null; then
    echo "デプロイバケット既存: ${DEPLOY_BUCKET}"
else
    aws s3 mb s3://${DEPLOY_BUCKET} --region ${REGION}
    echo "✅ デプロイバケット作成完了: ${DEPLOY_BUCKET}"
fi

# Step 6: ファイルアップロード
echo "=== Step 6: ファイルアップロード ==="

cd etl-yaml-deploy
aws s3 sync . s3://${DEPLOY_BUCKET}/ --exclude "*.pyc" --exclude "__pycache__/*" --region ${REGION}
cd ..

echo "✅ ファイルアップロード完了"

# Step 7: ファイル構成確認
echo "=== Step 7: ファイル構成確認 ==="
echo "ローカルファイル構成:"
tree etl-yaml-deploy

echo ""
echo "S3ファイル構成:"
aws s3 ls s3://${DEPLOY_BUCKET}/ --recursive --region ${REGION}

# Step 8: デプロイコマンド生成
echo ""
echo "=== Step 8: デプロイ準備完了 ==="
echo ""
echo "🚀 以下のコマンドでデプロイしてください:"
echo ""
echo "aws cloudformation deploy \\"
echo "  --template-file etl-yaml-deploy/complete-etl-template.yaml \\"
echo "  --stack-name ${STACK_NAME} \\"
echo "  --parameter-overrides \\"
echo "    ProjectName=\"etl-csv-to-rds-postgresql\" \\"
echo "    DBMasterPassword=\"TestPassword123!\" \\"
echo "    SourceBucket=\"${DEPLOY_BUCKET}\" \\"
echo "    CSVProcessorCodeKey=\"lambda-code/csv_processor.py\" \\"
echo "    QueryExecutorCodeKey=\"lambda-code/query_executor.py\" \\"
echo "    TableCreatorCodeKey=\"lambda-code/table_creator.py\" \\"
echo "    Psycopg2LayerKey=\"layers/psycopg2-layer.zip\" \\"
echo "    InitSqlPrefix=\"init-sql/\" \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region ${REGION}"
echo ""
echo "=== 移行準備完了 ==="
