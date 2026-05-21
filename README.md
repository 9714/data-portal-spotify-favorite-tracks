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

## ディレクトリ構成

```
.
├── etl/                    # Cloud Run Jobs で実行する Python コード
│   ├── main.py             # エントリポイント（Step 1-3 を順次実行）
│   ├── spotify_client.py   # Spotify API クライアント
│   ├── gcs_writer.py       # GCS への JSONL 書き込み
│   ├── bq_loader.py        # GCS → BigQuery Load Job
│   └── requirements.txt
├── dbt/                    # dbt プロジェクト
│   ├── dbt_project.yml
│   ├── profiles.yml        # BigQuery 接続設定（dev/prd ターゲット）
│   ├── packages.yml        # dbt_utils
│   ├── macros/
│   │   └── generate_schema_name.sql
│   └── models/
│       ├── staging/        # raw JSON の展開
│       ├── intermediate/   # 配列の UNNEST など中間変換
│       ├── dimensions/     # dim_track / dim_artist / dim_date
│       └── facts/          # fct_saved_tracks
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
| Cloud Scheduler | `0 21 * * 0` UTC（JST 月曜 06:00） |
| Cloud Storage | `dp-spotify-raw` / asia-northeast1 |
| BigQuery（raw） | `raw` dataset / asia-northeast1 |
| BigQuery（mart） | `mart` dataset / asia-northeast1 |
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
4. Cloud Scheduler のスケジュールを更新

GitHub Secrets：`WIF_PROVIDER` / `GCP_PROJECT_ID` / `GCP_REGION`

## BigQuery データモデル

```
raw.saved_tracks          GCS から Load したまま（ネスト構造維持）

stg_saved_tracks          型変換・JSON 展開・JST カラム追加

int_track_artists         artists 配列を UNNEST した track × artist ペア

dim_track                 track_id でユニーク
dim_artist                artist_id でユニーク
dim_date                  2005-01-01 〜 当日の日付ディメンション（date_spine）

fct_saved_tracks          added_at / track_id / date_id（grain = track_id）
```

dev 環境では各データセットに `dev_` プレフィックスが付く（`dev_raw` / `dev_mart`）。

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
