# デプロイメントガイド

## 必要な権限

デプロイユーザーには以下のIAM権限が必要です：
- CloudFormation全権限
- IAM（GetRole, GetRolePolicy等を含む）
- EC2, RDS, S3, Lambda全権限
- その他（詳細はiam-policy-example.jsonを参照）

## デプロイ手順

1. ソースバケットを作成
2. ファイルをアップロード
3. deploy-simple.shを実行

詳細は[README.md](README.md)を参照してください。
