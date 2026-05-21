#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing ETL and dbt dependencies..."
uv pip install --system -r "$ROOT/etl/requirements.txt"
uv pip install --system dbt-bigquery

echo "Done."
