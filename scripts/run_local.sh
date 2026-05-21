#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$ROOT/.env" ]; then
  echo "Error: .env not found. Run: cp .env.example .env and fill in the values."
  exit 1
fi

# venv がなければ作成して依存関係をインストール
if [ ! -d "$ROOT/etl/.venv" ]; then
  echo "Setting up venv..."
  cd "$ROOT/etl" && uv venv && uv pip install -r requirements.txt
fi

# 環境変数を読み込んで ETL 実行
set -a && source "$ROOT/.env" && set +a
cd "$ROOT/etl" && source .venv/bin/activate && python3 main.py
