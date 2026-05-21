# Spotify Favorite Tracks Data Portal

Spotify のお気に入り曲を毎日 BigQuery に蓄積し、ダッシュボードで可視化するデータパイプライン。

## 概要

Cloud Scheduler が毎朝6時（JST）に Cloud Run Jobs を起動し、Spotify API からデータを取得して BigQuery に格納する。dbt がデータモデルを変換する。可視化は別リポジトリの Streamlit Dashboard が担う。

```
Cloud Scheduler (毎日 06:00 JST)
  └→ Cloud Run Jobs
       ├─ Step 1: Spotify API → GCS (JSONL)
       ├─ Step 2: GCS → BigQuery raw テーブル
       └─ Step 3: dbt run (staging → dim → fct)

BigQuery  ←  別リポジトリの Streamlit Dashboard が参照
```

## 取得データ

| Spotify API | 内容 |
|---|---|
| `saved_tracks` | お気に入り曲 + `added_at` |

毎回全件取得する。

## ディレクトリ構成

```
.
├── etl/                    # Cloud Run Jobs で実行する Python コード
│   ├── main.py             # エントリポイント
│   ├── spotify_client.py   # Spotify API クライアント
│   ├── gcs_writer.py       # GCS への JSONL 書き込み
│   ├── bq_loader.py        # GCS → BigQuery Load Job（未実装）
│   └── requirements.txt
├── dbt/                    # dbt プロジェクト（未実装）
├── scripts/
│   └── setup.sh            # ローカル開発環境のセットアップ
├── .github/
│   └── workflows/
│       ├── lint.yml        # PR 時：ruff（Python）+ sqlfluff（SQL）
│       ├── build.yml       # PR 時：Docker build 確認
│       └── deploy.yml      # 手動：Artifact Registry push + Cloud Run Jobs デプロイ
└── Dockerfile
```

## GCP リソース

| リソース | 設定 |
|---|---|
| Cloud Run Jobs | 512Mi / タイムアウト 300s / asia-northeast1 |
| Cloud Scheduler | `0 21 * * *` UTC（JST 06:00） |
| Cloud Storage | `dp-spotify-raw` / asia-northeast1 |
| BigQuery | `raw` dataset / asia-northeast1 |
| Artifact Registry | `spotify-etl` / Docker / asia-northeast1 |
| Secret Manager | `spotify-client-id` / `spotify-client-secret` / `spotify-refresh-token` |

### サービスアカウント

| SA | 用途 |
|---|---|
| `etl-job-sa` | BQ・GCS・Secret Manager へのアクセス |
| `scheduler-sa` | Cloud Run Jobs の起動のみ |
| `github-actions-sa` | デプロイ用（Workload Identity Federation でキーレス認証） |

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

GitHub Secrets：`WIF_PROVIDER` / `GCP_PROJECT_ID` / `GCP_REGION`

## BigQuery データモデル

```
raw.saved_tracks      GCS から Load したまま（ネスト構造維持）

stg_saved_tracks      型変換・カラム名の整理

dim_track             track_id ユニーク
dim_artist            artist_id ユニーク
dim_date              added_at から生成した日付ディメンション

fct_saved_tracks      added_at / track_id / artist_id / date_id
```

## ローカル開発

```bash
# 初回のみ
gcloud auth application-default login
cp .env.example .env  # SPOTIFY_* と BQ_PROJECT を入力
./scripts/setup.sh    # venv 構築・依存関係インストール

# ETL 実行
cd etl && uv run python3 main.py
```

実行後、GCS バケット `dp-spotify-raw/dev/raw/saved_tracks/YYYY-MM-DD.jsonl` が作成されれば成功。

```bash
# dbt（実装後）
cd etl && uv run dbt run --project-dir ../dbt/
cd etl && uv run dbt test --project-dir ../dbt/
```

## Lint / Format

### Python（ruff）

```bash
cd etl
uv run ruff check .          # lint
uv run ruff check . --fix    # lint + 自動修正
uv run ruff format .         # format
```

### SQL（sqlfluff / BigQuery dialect）

```bash
cd etl
uv run sqlfluff lint ../dbt/ --dialect bigquery    # lint
uv run sqlfluff fix ../dbt/ --dialect bigquery     # format
```
