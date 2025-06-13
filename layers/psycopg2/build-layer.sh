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
