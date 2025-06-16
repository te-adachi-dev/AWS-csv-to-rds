# AWS ETL System - CSV to RDS PostgreSQL

S3にアップロードされたCSVファイルを自動的にRDS PostgreSQLに取り込むサーバーレスETLシステムです。

## 🚀 主な機能

- **自動CSV処理**: S3にCSVをアップロードすると自動的にRDSにデータを挿入
- **動的テーブル作成**: CSVファイル名から自動的にテーブルを作成
- **SQLクエリ実行**: Lambda経由でRDSにクエリを実行し、結果をS3に出力
- **初期化処理**: S3に配置したSQLファイルでテーブルを自動作成

## 📋 前提条件

- AWS CLI v1またはv2がインストール済み
- AWS アカウントと適切な権限（Administrator推奨）
- Python 3.x（Lambda関数のローカルテスト用）
- Git

## 🛠️ セットアップ手順

### 1. リポジトリのクローン

```bash
# リポジトリをクローン
git clone https://github.com/te-adachi-dev/AWS-csv-to-rds
cd AWS-csv-to-rds

# ディレクトリ構造の確認
tree
```

### 2. AWS環境の設定

```bash
# AWS CLIの設定（未設定の場合）
aws configure

# 環境変数の設定（必須）
export AWS_DEFAULT_REGION=us-east-2  # 使用するリージョンに変更

# 別リージョンを使用する場合の例
# export AWS_DEFAULT_REGION=ap-northeast-1  # 東京リージョン
# export AWS_DEFAULT_REGION=eu-west-1      # アイルランド
```

### 3. ソースコード保存用S3バケットの作成

```bash
# バケット名を決定（グローバルユニークである必要があります）
BUCKET_NAME="etl-csv-to-rds-postgresql-source-$(date +%Y%m%d)-$RANDOM"

# バケット作成
aws s3 mb s3://$BUCKET_NAME

# 作成確認
aws s3 ls | grep $BUCKET_NAME

echo "Source Bucket: $BUCKET_NAME"
```

### 4. Lambda関数のパッケージング

```bash
# Lambda関数のzipファイルが存在しない場合は作成
cd lambda-code

# CSV Processor
if [ ! -f csv_processor.zip ]; then
    zip csv_processor.zip csv_processor.py
fi

# Query Executor
if [ ! -f query_executor.zip ]; then
    zip query_executor.zip query_executor.py
fi

# Table Creator
if [ ! -f table_creator.zip ]; then
    zip table_creator.zip table_creator.py
fi

cd ..
```

### 5. psycopg2レイヤーの準備

```bash
# レイヤーファイルが存在しない場合
if [ ! -f layers/psycopg2-layer.zip ]; then
    # 事前ビルド済みファイルをコピー（存在する場合）
    cp layers/build/psycopg2-layer.zip layers/
fi

# ファイル確認
ls -la layers/psycopg2-layer.zip
```

## 🚀 デプロイ

### ワンコマンドデプロイ

```bash
# デプロイ実行（15-20分かかります）
./deploy-simple.sh $BUCKET_NAME

# または、直接バケット名を指定
./deploy-simple.sh etl-csv-to-rds-postgresql-source-20240614-12345
```

### デプロイ成功の確認

デプロイが成功すると以下のような出力が表示されます：

```
✓ デプロイ完了！

=== 次のステップ ===
1. テスト用CSVファイルをアップロード:
   aws s3 cp your-file.csv s3://etl-csv-to-rds-postgresql-data-xxxxxxxx-test/csv/

2. Lambda関数ログの確認:
   aws logs tail /aws/lambda/etl-csv-to-rds-postgresql-csv-processor --follow

3. RDS接続確認 (VPC内のEC2から):
   psql -h etl-csv-to-rds-postgresql-pg-test.xxxxx.rds.amazonaws.com -U postgres -d postgres
```

## 📊 使用方法

### 1. CSVファイルの処理

```bash
# データバケット名を環境変数に設定
DATA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name etl-csv-to-rds-postgresql \
  --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
  --output text)

# テスト用CSVファイルの作成
cat > products.csv << EOF
product_id,name,quantity,price,category
1,ノートPC,10,85000,電子機器
2,マウス,50,2500,アクセサリ
3,キーボード,30,5500,アクセサリ
EOF

# S3にアップロード（自動的に処理されます）
aws s3 cp products.csv s3://$DATA_BUCKET/csv/
```

### 2. データの確認（QueryExecutor使用）

```bash
# テーブル一覧の確認
aws lambda invoke \
  --function-name etl-csv-to-rds-postgresql-query-executor \
  --payload '{"sql": "SELECT tablename FROM pg_tables WHERE schemaname = '\''public'\'' ORDER BY tablename;"}' \
  result.json

cat result.json | jq .

# データの取得（JSON形式）
aws lambda invoke \
  --function-name etl-csv-to-rds-postgresql-query-executor \
  --payload '{"sql": "SELECT * FROM products_20240614_123456 LIMIT 10;", "output_format": "json"}' \
  result.json

cat result.json | jq .
```

### 3. カスタムSQLの実行

```bash
# 集計クエリの例
aws lambda invoke \
  --function-name etl-csv-to-rds-postgresql-query-executor \
  --payload '{
    "sql": "SELECT category, COUNT(*) as count, SUM(price * quantity) as total_value FROM products_20240614_123456 GROUP BY category;",
    "output_format": "csv",
    "output_name": "category_summary"
  }' \
  result.json
```

## 🔍 ログの確認

### AWS CLI v2の場合
```bash
# リアルタイムログ監視
aws logs tail /aws/lambda/etl-csv-to-rds-postgresql-csv-processor --follow
```

### AWS CLI v1の場合
```bash
# 過去5分のログを確認
aws logs filter-log-events \
  --log-group-name /aws/lambda/etl-csv-to-rds-postgresql-csv-processor \
  --start-time $(($(date +%s -d '5 minutes ago') * 1000)) \
  --query 'events[*].message' \
  --output text
```

## 🛡️ トラブルシューティング

### よくあるエラーと対処法

#### 1. TemplateURL must be a supported URL
```bash
# 原因: AWS_DEFAULT_REGIONが未設定
# 解決方法:
export AWS_DEFAULT_REGION=us-east-2
```

#### 2. CSVの`id`カラムエラー
```
エラー: column "id" specified more than once
```
- 原因: Lambda関数が自動的に`id SERIAL PRIMARY KEY`を追加
- 解決方法: CSVのidカラムを別名（例：product_id）に変更

#### 3. RDS接続エラー
- VPCエンドポイントが正しく設定されているか確認
- セキュリティグループの設定を確認

## 🗑️ リソースの削除

```bash
# スタックの削除（全リソースを削除）
aws cloudformation delete-stack --stack-name etl-csv-to-rds-postgresql

# 削除完了の確認
aws cloudformation wait stack-delete-complete --stack-name etl-csv-to-rds-postgresql
```

## 📝 設定のカスタマイズ

### 別リージョンへのデプロイ

1. 環境変数を変更
```bash
export AWS_DEFAULT_REGION=ap-northeast-1  # 東京リージョンの例
```

2. 新しいソースバケットを作成
```bash
BUCKET_NAME="etl-csv-rds-tokyo-$(date +%Y%m%d)"
aws s3 mb s3://$BUCKET_NAME
```

3. デプロイ実行
```bash
./deploy-simple.sh $BUCKET_NAME
```

### RDSの設定変更

`cfn-templates/03-database-storage-stack.yaml`を編集：

- インスタンスクラス: `db.t3.micro` → `db.t3.small`
- ストレージサイズ: `20` → `100`
- PostgreSQLバージョン: `17.4` → 必要なバージョン

## 📚 アーキテクチャ

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│     S3      │────▶│   Lambda    │────▶│     RDS     │
│  (CSV置場)  │     │ (処理関数)  │     │(PostgreSQL) │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │     S3      │
                    │ (結果出力)  │
                    └─────────────┘
```
