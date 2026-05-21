SHELL := /bin/bash
DBT_FLAGS = --project-dir ../dbt/ --profiles-dir ../dbt/
DBT = set -a && source .env && set +a && cd etl && uv run dbt

.PHONY: etl dbt-deps dbt-run dbt-test lint-py lint-sql lint

etl:
	cd etl && uv run python3 main.py

dbt-deps:
	$(DBT) deps $(DBT_FLAGS)

dbt-run:
	$(DBT) run $(DBT_FLAGS)

dbt-test:
	$(DBT) test $(DBT_FLAGS)

lint-py:
	cd etl && uv run ruff check . --fix && uv run ruff format .

lint-sql:
	cd etl && uv run sqlfluff fix ../dbt/ --dialect bigquery

lint: lint-py lint-sql
