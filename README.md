# Spotify Favorite Tracks Data Portal

Spotify のお気に入り曲を毎週 BigQuery に蓄積し、ダッシュボードで可視化するデータパイプライン。

## 概要

Cloud Scheduler が毎週月曜 06:00（JST）に Cloud Run Jobs を起動し、Spotify API からデータを取得して BigQuery に格納する。dbt がデータモデルを変換する。可視化は別リポジトリの Streamlit Dashboard が担う。

```
Cloud Scheduler (毎週月曜 06:00 JST)
  └→ Cloud Run Jobs
       ├─ Step 1: Spotify API → GCS (JSONL)
       ├─ Step 2: GCS → BigQuery raw テーブル
       └─ Step 3: dbt run (staging → intermediate → dim → fct)

BigQuery  ←  別リポジトリの Streamlit Dashboard が参照
```

## 取得データ

| Spotify API | 内容 |
|---|---|
| `saved_tracks` | お気に入り曲 + `added_at` |

毎回全件取得する。

## CI/CD

### CI（PR 作成・更新）

| ワークフロー | 内容 | ツール |
|---|---|---|
| `lint.yml` | Python lint / format | `ruff` |
| `lint.yml` | SQL lint | `sqlfluff`（dialect: bigquery） |
| `build.yml` | Docker ビルド確認 | `docker build`（push なし） |

### CD（手動実行）

GitHub Actions → Deploy → **Run workflow** から手動実行：

1. Workload Identity Federation で認証
2. Docker イメージをビルドして Artifact Registry へ push
3. Cloud Run Jobs をデプロイ
4. Cloud Scheduler のスケジュールを更新

GitHub Secrets：`WIF_PROVIDER` / `GCP_PROJECT_ID` / `GCP_REGION`

## ローカル開発

### 前提

```bash
gcloud auth application-default login
cp .env.example .env  # SPOTIFY_* / BQ_PROJECT / GCS_BUCKET を入力（BQ_DATASET はデフォルト値あり）
```

### ETL 実行

```bash
make etl
```

- Step 1 完了後：GCS `dp-spotify-raw/raw/saved_tracks/YYYY-MM-DD.jsonl` が作成される
- Step 2 完了後：BigQuery `dev_raw.saved_tracks` にデータが格納される
- Step 3 完了後：BigQuery `dev_mart` に各モデルが作成される

### dbt 単体実行

```bash
make dbt-deps   # パッケージ取得（初回・packages.yml 変更時）
make dbt-run    # モデル実行
make dbt-test   # テスト
```

## Lint / Format

```bash
make lint       # Python（ruff）+ SQL（sqlfluff）まとめて実行
make lint-py    # Python のみ
make lint-sql   # SQL のみ
```
