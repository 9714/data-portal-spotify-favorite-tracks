# Spotify Favorite Tracks Data Portal

Spotifyのお気に入り曲の音楽的特徴量を毎日BigQueryに蓄積し、ダッシュボードで可視化するデータパイプライン。

## 概要

Cloud Schedulerが毎朝6時（JST）にCloud Run Jobsを起動し、Spotify APIからデータを取得してBigQueryに格納する。dbtがデータモデルを変換し、BigQueryに蓄積する。可視化は別リポジトリの Streamlit Dashboard が担う。

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
│   ├── main.py             # エントリポイント（3ステップを順次実行）
│   ├── spotify_client.py   # Spotify API クライアント
│   ├── gcs_writer.py       # GCS への JSONL 書き込み
│   ├── bq_loader.py        # GCS → BigQuery Load Job
│   └── requirements.txt
├── dbt/                    # dbt プロジェクト
│   ├── models/
│   │   ├── staging/        # stg_saved_tracks, stg_audio_features
│   │   ├── dimensions/     # dim_track, dim_artist, dim_date
│   │   └── facts/          # fct_saved_tracks
│   └── dbt_project.yml
├── .github/
│   └── workflows/
│       ├── lint.yml        # PR 時：ruff（Python）+ sqlfluff（SQL）
│       ├── build.yml       # PR 時：Docker build 確認（push なし）
│       └── deploy.yml      # main マージ時：Artifact Registry push + Cloud Run Jobs デプロイ
└── Dockerfile
```

## GCP リソース

| リソース | 設定 |
|---|---|
| Cloud Run Jobs | 512Mi / タイムアウト300s / asia-northeast1 |
| Cloud Scheduler | `0 21 * * *` UTC（JST 06:00） |
| Cloud Storage | asia-northeast1 / rawプレフィックス / 90日ライフサイクル |
| BigQuery | `spotify_analytics` dataset / `added_at` パーティション |
| Artifact Registry | Docker / asia-northeast1 |
| Secret Manager | `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` / `SPOTIFY_REFRESH_TOKEN` |

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

### CD（PR マージ）

1. Workload Identity Federation で認証（サービスアカウントキー不要）
2. Docker イメージをビルドして Artifact Registry へ push
3. Cloud Run Jobs をデプロイ

GitHub Secrets に設定する値：`WIF_PROVIDER` / `GCP_PROJECT_ID` / `GCP_REGION`

Spotify 認証情報は Secret Manager で管理し、コードには含めない。

## BigQuery データモデル

```
raw.saved_tracks          GCS から Load したまま（ネスト構造維持）
raw.audio_features

stg_saved_tracks          型変換・カラム名の整理
stg_audio_features

dim_track                 track_id ユニーク・音楽特徴量を保持
dim_artist                artist_id ユニーク
dim_date                  added_at から生成した日付ディメンション

fct_saved_tracks          added_at / track_id / artist_id / date_id の集約テーブル
```

## ローカル開発

```bash
# 初回のみ
gcloud auth application-default login
cp .env.example .env  # SPOTIFY_* と BQ_PROJECT を入力

# ETL 実行（venv 未作成なら自動でセットアップ）
./scripts/run_local.sh
```

実行後、GCS バケット `dp-spotify-raw` に以下が作成されれば成功：
- `raw/saved_tracks/YYYY-MM-DD.jsonl`

```bash
# dbt（実装後）
dbt run --project-dir dbt/
dbt test --project-dir dbt/
```
