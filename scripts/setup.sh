#!/bin/bash
set -e

# gitコマンドを使って、スクリプトの場所に関わらずプロジェクトのルート絶対パスを強制取得
ROOT="$(git rev-parse --show-toplevel)"

echo "Creating virtual environment at Root: $ROOT"
cd "$ROOT"
uv venv --clear

echo "Installing product and dev dependencies..."
# 絶対パスで確実にファイルを指定する
uv pip install -r "$ROOT/requirements.txt"
uv pip install -r "$ROOT/requirements-dev.txt"

echo "------------------------------------------------"
echo "Done! Pure root-based environment is ready."
echo "- Run lint: uv run sqlfluff lint dbt/models/"
echo "- Run ETL:  uv run python3 etl/main.py"
echo "------------------------------------------------"
