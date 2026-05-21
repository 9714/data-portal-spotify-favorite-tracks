#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing ETL and dbt dependencies..."
cd "$ROOT/etl"
uv venv --clear
uv pip install -r requirements.txt
uv pip install dbt-bigquery

echo "Done. Run with: cd etl && uv run python3 main.py"
