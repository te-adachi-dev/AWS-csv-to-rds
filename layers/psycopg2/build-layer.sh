#!/bin/bash
cd "$(dirname "$0")"

# 一時ディレクトリの作成
rm -rf temp_layer
mkdir -p temp_layer/python

# psycopg2のインストール（プラットフォーム指定）
pip install \
    --platform manylinux2014_x86_64 \
    --target temp_layer/python/ \
    --implementation cp \
    --python-version 3.11 \
    --only-binary=:all: \
    --upgrade \
    psycopg2-binary==2.9.7

# zipファイルの作成
cd temp_layer
zip -r ../build/psycopg2-layer.zip python/

# クリーンアップ
cd ..
rm -rf temp_layer

echo "psycopg2-layer.zip created successfully"
