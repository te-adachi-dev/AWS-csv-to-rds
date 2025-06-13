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
