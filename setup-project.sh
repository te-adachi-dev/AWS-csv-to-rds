#!/bin/bash

# ETL Project セットアップスクリプト
# 現在のフォルダ構成をTo-Be構成に変換

set -e

print_step() {
    echo -e "\033[1;34m[STEP $1]\033[0m $2"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_info() {
    echo -e "\033[1;33m[INFO]\033[0m $1"
}

# プロジェクト構成セットアップ
setup_project_structure() {
    print_step "1" "プロジェクト構成のセットアップ"
    
    # 新しいディレクトリ構造の作成
    mkdir -p cloudformation/parameters
    mkdir -p lambda-functions/{table_creator,csv_processor,query_executor,build}
    mkdir -p layers/{psycopg2,build}
    mkdir -p sql
    mkdir -p test-data
    mkdir -p scripts
    mkdir -p docs
    mkdir -p archive
    
    print_info "ディレクトリ構造作成完了"
}

# 既存ファイルの移動・整理
reorganize_existing_files() {
    print_step "2" "既存ファイルの移動・整理"
    
    # CloudFormationテンプレートの整理
    if [ -f "etl-yaml-deploy/complete-etl-template.yaml" ]; then
        mv etl-yaml-deploy/complete-etl-template.yaml archive/
        print_info "元テンプレートをarchive/に移動"
    fi
    
    # Lambda関数ファイルの移動
    if [ -f "etl-yaml-deploy/lambda-code/table_creator.py" ]; then
        mv etl-yaml-deploy/lambda-code/table_creator.py lambda-functions/table_creator/
    fi
    if [ -f "etl-yaml-deploy/lambda-code/csv_processor.py" ]; then
        mv etl-yaml-deploy/lambda-code/csv_processor.py lambda-functions/csv_processor/
    fi
    if [ -f "etl-yaml-deploy/lambda-code/query_executor.py" ]; then
        mv etl-yaml-deploy/lambda-code/query_executor.py lambda-functions/query_executor/
    fi
    
    # ビルド済みzipファイルの移動
    if [ -f "etl-yaml-deploy/lambda-code/table_creator.zip" ]; then
        mv etl-yaml-deploy/lambda-code/table_creator.zip lambda-functions/build/
    fi
    if [ -f "etl-yaml-deploy/lambda-code/csv_processor.zip" ]; then
        mv etl-yaml-deploy/lambda-code/csv_processor.zip lambda-functions/build/
    fi
    if [ -f "etl-yaml-deploy/lambda-code/query_executor.zip" ]; then
        mv etl-yaml-deploy/lambda-code/query_executor.zip lambda-functions/build/
    fi
    
    # Layerファイルの移動
    if [ -f "etl-yaml-deploy/layers/psycopg2-layer.zip" ]; then
        mv etl-yaml-deploy/layers/psycopg2-layer.zip layers/build/
    fi
    if [ -f "psycopg2-layer-python311-fixed.zip" ]; then
        mv psycopg2-layer-python311-fixed.zip layers/build/psycopg2-layer-backup.zip
    fi
    
    # SQLファイルの移動
    if [ -f "etl-yaml-deploy/init-sql/01_afc_accounts.sql" ]; then
        mv etl-yaml-deploy/init-sql/01_afc_accounts.sql sql/
    fi
    if [ -f "etl-yaml-deploy/init-sql/02_sample_tables.sql" ]; then
        mv etl-yaml-deploy/init-sql/02_sample_tables.sql sql/
    fi
    
    # ルート直下の古いファイルをarchiveに移動
    for file in csv_processor.py query_executor.py table_creator.py create_table_afc_accounts.sql; do
        if [ -f "$file" ]; then
            mv "$file" archive/
            print_info "古いファイルをarchive/に移動: $file"
        fi
    done
    
    # 空になったディレクトリの削除
    if [ -d "etl-yaml-deploy" ]; then
        rm -rf etl-yaml-deploy
        print_info "古いetl-yaml-deployディレクトリを削除"
    fi
    
    print_success "ファイル移動・整理完了"
}

# 各Lambda関数のrequirements.txt作成
create_requirements_files() {
    print_step "3" "requirements.txtファイルの作成"
    
    # table_creator用
    cat > lambda-functions/table_creator/requirements.txt << 'EOF'
# table_creator用依存関係
# psycopg2はLayerで提供
boto3>=1.26.0
botocore>=1.29.0
EOF

    # csv_processor用
    cat > lambda-functions/csv_processor/requirements.txt << 'EOF'
# csv_processor用依存関係
# psycopg2はLayerで提供
boto3>=1.26.0
botocore>=1.29.0
pandas>=1.5.0
EOF

    # query_executor用
    cat > lambda-functions/query_executor/requirements.txt << 'EOF'
# query_executor用依存関係
# psycopg2はLayerで提供
boto3>=1.26.0
botocore>=1.29.0
pandas>=1.5.0
EOF

    # psycopg2 Layer用
    cat > layers/psycopg2/requirements.txt << 'EOF'
# psycopg2 Layer用依存関係
psycopg2-binary==2.9.7
EOF

    print_success "requirements.txtファイル作成完了"
}

# パッケージングスクリプトの作成
create_package_scripts() {
    print_step "4" "パッケージングスクリプトの作成"
    
    # table_creator用パッケージスクリプト
    cat > lambda-functions/table_creator/package.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
zip -r ../build/table_creator.zip table_creator.py
echo "table_creator.zip created successfully"
EOF
    chmod +x lambda-functions/table_creator/package.sh
    
    # csv_processor用パッケージスクリプト
    cat > lambda-functions/csv_processor/package.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
zip -r ../build/csv_processor.zip csv_processor.py
echo "csv_processor.zip created successfully"
EOF
    chmod +x lambda-functions/csv_processor/package.sh
    
    # query_executor用パッケージスクリプト
    cat > lambda-functions/query_executor/package.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
zip -r ../build/query_executor.zip query_executor.py
echo "query_executor.zip created successfully"
EOF
    chmod +x lambda-functions/query_executor/package.sh
    
    # Layer作成スクリプト
    cat > layers/psycopg2/build-layer.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 一時ディレクトリの作成
rm -rf temp_layer
mkdir -p temp_layer/python

# psycopg2のインストール
pip install -r requirements.txt -t temp_layer/python/

# zipファイルの作成
cd temp_layer
zip -r ../build/psycopg2-layer.zip python/

# クリーンアップ
cd ..
rm -rf temp_layer

echo "psycopg2-layer.zip created successfully"
EOF
    chmod +x layers/psycopg2/build-layer.sh
    
    print_success "パッケージングスクリプト作成完了"
}

# パラメータファイルの作成
create_parameter_files() {
    print_step "5" "環境別パラメータファイルの作成"
    
    # 開発環境用
    cat > cloudformation/parameters/dev-parameters.json << 'EOF'
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "etl-csv-to-rds-postgresql-dev"
  },
  {
    "ParameterKey": "DBMasterUsername",
    "ParameterValue": "postgres"
  },
  {
    "ParameterKey": "DBMasterPassword",
    "ParameterValue": "DevPassword123!"
  },
  {
    "ParameterKey": "SourceBucket",
    "ParameterValue": "REPLACE_WITH_YOUR_SOURCE_BUCKET"
  },
  {
    "ParameterKey": "CSVProcessorCodeKey",
    "ParameterValue": "lambda-code/csv_processor.zip"
  },
  {
    "ParameterKey": "QueryExecutorCodeKey",
    "ParameterValue": "lambda-code/query_executor.zip"
  },
  {
    "ParameterKey": "TableCreatorCodeKey",
    "ParameterValue": "lambda-code/table_creator.zip"
  },
  {
    "ParameterKey": "Psycopg2LayerKey",
    "ParameterValue": "layers/psycopg2-layer.zip"
  },
  {
    "ParameterKey": "InitSqlPrefix",
    "ParameterValue": "init-sql/"
  }
]
EOF
    
    # ステージング環境用
    sed 's/dev/staging/g; s/DevPassword123!/StagingPassword123!/g' \
        cloudformation/parameters/dev-parameters.json > cloudformation/parameters/staging-parameters.json
    
    # 本番環境用
    sed 's/dev/prod/g; s/DevPassword123!/CHANGE_THIS_PRODUCTION_PASSWORD!/g' \
        cloudformation/parameters/dev-parameters.json > cloudformation/parameters/prod-parameters.json
    
    print_success "パラメータファイル作成完了"
}

# 運用スクリプトの作成
create_operational_scripts() {
    print_step "6" "運用スクリプトの作成"
    
    # ソースバケット作成スクリプト
    cat > scripts/create-source-bucket.sh << 'EOF'
#!/bin/bash
# ソースバケット作成スクリプト

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <bucket-name>"
    exit 1
fi

BUCKET_NAME=$1
REGION=${AWS_DEFAULT_REGION:-us-east-1}

aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled

echo "ソースバケット作成完了: ${BUCKET_NAME}"
EOF
    chmod +x scripts/create-source-bucket.sh
    
    # アーティファクトアップロードスクリプト
    cat > scripts/upload-artifacts.sh << 'EOF'
#!/bin/bash
# Lambda関数とLayerのアップロードスクリプト

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <source-bucket-name>"
    exit 1
fi

SOURCE_BUCKET=$1

# CloudFormationテンプレートのアップロード
aws s3 sync cloudformation/ s3://${SOURCE_BUCKET}/cfn-templates/ --exclude "parameters/*"

# Lambda関数のアップロード
aws s3 sync lambda-functions/build/ s3://${SOURCE_BUCKET}/lambda-code/

# Layerのアップロード
aws s3 sync layers/build/ s3://${SOURCE_BUCKET}/layers/

# SQLファイルのアップロード
aws s3 sync sql/ s3://${SOURCE_BUCKET}/init-sql/

echo "アーティファクトアップロード完了"
EOF
    chmod +x scripts/upload-artifacts.sh
    
    # ログ監視スクリプト
    cat > scripts/monitor-logs.sh << 'EOF'
#!/bin/bash
# Lambda関数ログ監視スクリプト

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <function-name>"
    echo "例: $0 etl-csv-to-rds-postgresql-csv-processor"
    exit 1
fi

FUNCTION_NAME=$1

echo "Lambda関数 ${FUNCTION_NAME} のログを監視中..."
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow
EOF
    chmod +x scripts/monitor-logs.sh
    
    print_success "運用スクリプト作成完了"
}

# テストデータの作成
create_test_data() {
    print_step "7" "テストデータの作成"
    
    # サンプルCSVファイル
    cat > test-data/sample_afc_accounts.csv << 'EOF'
id,account_name,account_type,balance,created_at,status
1,田中太郎,普通預金,100000,2025-06-13 10:00:00,active
2,佐藤花子,普通預金,250000,2025-06-13 11:00:00,active
3,鈴木一郎,定期預金,500000,2025-06-13 12:00:00,active
4,高橋美咲,普通預金,75000,2025-06-13 13:00:00,inactive
5,伊藤健太,普通預金,320000,2025-06-13 14:00:00,active
EOF
    
    # テストデータアップロードスクリプト
    cat > test-data/upload-test-data.sh << 'EOF'
#!/bin/bash
# テストデータアップロードスクリプト

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <data-bucket-name>"
    exit 1
fi

DATA_BUCKET=$1

echo "テストデータをアップロード中..."
aws s3 cp sample_afc_accounts.csv s3://${DATA_BUCKET}/csv/sample_afc_accounts.csv

echo "テストデータアップロード完了"
echo "CloudWatch Logsで処理状況を確認してください"
EOF
    chmod +x test-data/upload-test-data.sh
    
    print_success "テストデータ作成完了"
}

# README.mdの作成
create_readme() {
    print_step "8" "README.mdの作成"
    
    cat > README.md << 'EOF'
# ETL CSV to RDS PostgreSQL System

## 概要
このプロジェクトは、S3にアップロードされたCSVファイルを自動的にRDS PostgreSQLに取り込むETLシステムです。

## アーキテクチャ
- VPC内でのプライベート通信
- VPCエンドポイントによる AWS API アクセス
- Lambda による CSV 処理
- RDS PostgreSQL へのデータ投入

## フォルダ構成
```
├── cloudformation/          # CloudFormationテンプレート
├── lambda-functions/        # Lambda関数ソースコード
├── layers/                  # Lambda Layer
├── sql/                     # SQL初期化ファイル
├── test-data/              # テストデータ
├── scripts/                # 運用スクリプト
└── docs/                   # ドキュメント
```

## デプロイ手順
1. プロジェクトセットアップ: `./setup-project.sh`
2. ソースバケット作成: `./scripts/create-source-bucket.sh <bucket-name>`
3. アーティファクトアップロード: `./scripts/upload-artifacts.sh <bucket-name>`
4. システムデプロイ: `./deploy.sh <source-bucket-name>`

## 使用方法
1. CSVファイルを `s3://<data-bucket>/csv/` にアップロード
2. 自動的にLambda関数が起動してRDSに取り込み
3. CloudWatch Logsで処理状況を確認

詳細は `docs/` フォルダ内のドキュメントを参照してください。
EOF
    
    print_success "README.md作成完了"
}

# メイン処理
main() {
    print_info "ETL Project セットアップを開始します"
    
    setup_project_structure
    reorganize_existing_files
    create_requirements_files
    create_package_scripts
    create_parameter_files
    create_operational_scripts
    create_test_data
    create_readme
    
    print_success "プロジェクト構成セットアップ完了！"
    print_info "次のステップ:"
    echo "1. cloudformation/parameters/ 内のパラメータファイルを環境に合わせて編集"
    echo "2. scripts/create-source-bucket.sh でソースバケットを作成"
    echo "3. scripts/upload-artifacts.sh でアーティファクトをアップロード"
    echo "4. deploy.sh で段階的デプロイを実行"
}

main "$@"
