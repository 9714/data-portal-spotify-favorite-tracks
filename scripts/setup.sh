#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Setting up ETL environment..."
cd "$ROOT/etl"
uv venv
uv pip install -r requirements.txt

echo "Setting up dbt environment..."
uv pip install dbt-bigquery

echo "Done. Activate with: source etl/.venv/bin/activate"
