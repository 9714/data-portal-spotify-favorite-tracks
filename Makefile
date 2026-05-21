SHELL := /bin/bash

# ルートから直接実行するため、dbtのパス指定が超シンプルになります
DBT_FLAGS = --project-dir dbt --profiles-dir dbt
DBT = set -a && source .env && set +a && uv run dbt

.PHONY: etl dbt-deps dbt-run dbt-test lint-py lint-sql lint

# 1. ETLの実行 (ルートから直接スクリプトを叩く)
etl:
	uv run python3 etl/main.py

# 2. dbt関連のコマンド
dbt-deps:
	$(DBT) deps $(DBT_FLAGS)

dbt-run:
	$(DBT) run $(DBT_FLAGS)

dbt-test:
	$(DBT) test $(DBT_FLAGS)

# 3. PythonのLint/Format (etlフォルダ内をルートから検証)
lint-py:
	uv run ruff check etl/ --fix && uv run ruff format etl/

# 4. SQLのLint/Format (dbtフォルダ内をルートから検証、パス指定がシンプルに)
lint-sql:
	set -a && source .env && set +a && uv run sqlfluff fix dbt/models/ --force
lint: lint-py lint-sql
