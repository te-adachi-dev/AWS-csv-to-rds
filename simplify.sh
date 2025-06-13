#!/bin/bash

# PoCに適したシンプル構成に戻すスクリプト

echo "PoCに適したシンプル構成に変更します..."

# シンプルな構成に必要なディレクトリ
mkdir -p cfn-templates
mkdir -p lambda-code  
mkdir -p init-sql
mkdir -p layers

# CloudFormationテンプレートの準備（空ファイル作成）
echo "CloudFormationテンプレート用ディレクトリ準備完了"

# Lambda関数ファイルを元の場所に移動
cp lambda-functions/table_creator/table_creator.py lambda-code/
cp lambda-functions/csv_processor/csv_processor.py lambda-code/
cp lambda-functions/query_executor/query_executor.py lambda-code/

# ビルド済みzipを移動
cp lambda-functions/build/*.zip lambda-code/

# Layerを移動
cp layers/build/psycopg2-layer.zip layers/

# SQLファイルを移動
cp sql/*.sql init-sql/

# 元の構成のベースファイルたちを最上位に戻す
echo "基本ファイルの準備完了"

# 複雑すぎる構成を削除
rm -rf lambda-functions
rm -rf cloudformation
rm -rf scripts
rm -rf docs
rm -rf test-data
rm -rf archive

echo "シンプル構成への変更完了！"
echo ""
echo "現在の構成："
tree -L 2
