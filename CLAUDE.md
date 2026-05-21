# CLAUDE.md — 実装ガイド

このファイルはClaude Codeが実装時に参照するためのドキュメント。設計上の決定事項・制約・注意点をまとめる。

---

## アーキテクチャ決定事項

### データフロー
1つのCloud Run Jobsが3ステップを順次実行する（複数Jobには分割しない）。

```
Step 1: Spotify API → GCS (JSONL)
Step 2: GCS → BigQuery Load Job (raw テーブル)
Step 3: dbt run
```

### 差分取得ロジック
- 初回：`saved_tracks` を全件取得
- 2回目以降：BigQueryの `raw.saved_tracks` の `MAX(added_at)` を取得し、それ以降のみ取得
- `audio_features` は当日取得した `saved_tracks` の `track_id` 分だけ取得する

### GCS への書き込み
- フォーマット：JSONL（1行1レコード）
- パス：`raw/saved_tracks/YYYY-MM-DD.jsonl` / `raw/audio_features/YYYY-MM-DD.jsonl`
- フラット化しない。ネスト構造はそのまま書き込む（dbtに委譲）

### BigQuery への Load
- `WRITE_TRUNCATE` ではなく `WRITE_APPEND`（日付パーティションに追記）
- テーブル名：`raw.saved_tracks` / `raw.audio_features`
- スキーマ自動検出は使わず、明示的にスキーマを定義する

---

## ファイル構成と役割

```
etl/
  main.py           エントリポイント。3ステップを順次呼び出すだけ
  spotify_client.py Spotify Web API クライアント。認証・ページネーション処理
  gcs_writer.py     JSONL の生成と GCS へのアップロード
  bq_loader.py      GCS → BQ Load Job の実行・完了待ち
  requirements.txt

dbt/
  models/
    staging/
      stg_saved_tracks.sql
      stg_audio_features.sql
    dimensions/
      dim_track.sql
      dim_artist.sql
      dim_date.sql
    facts/
      fct_saved_tracks.sql
  dbt_project.yml
  profiles.yml       BigQuery 接続設定（環境変数から読む）

.github/workflows/
  lint.yml           PR時：ruff（Python）+ sqlfluff（SQL）
  build.yml          PR時：Docker build確認（pushなし）
  deploy.yml         mainマージ時：AR push → Cloud Run Jobs deploy

Dockerfile
```

---

## 環境変数・シークレット

### ランタイム（Cloud Run Jobs）
Secret Manager から環境変数として注入する。コードは `os.environ` から読む。

| 環境変数名 | Secret Manager のシークレット名 | 説明 |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | `spotify-client-id` | Spotify API Client ID |
| `SPOTIFY_CLIENT_SECRET` | `spotify-client-secret` | Spotify API Client Secret |
| `SPOTIFY_REFRESH_TOKEN` | `spotify-refresh-token` | OAuth2 Refresh Token |
| `GCS_BUCKET` | — | GCS バケット名（Cloud Run の環境変数で設定） |
| `BQ_PROJECT` | — | GCP プロジェクト ID |
| `BQ_DATASET` | — | `spotify_analytics` 固定 |

### GitHub Actions
GitHub Secrets に以下のみ設定する（Spotify 認証情報は含めない）：
- `WIF_PROVIDER`
- `GCP_PROJECT_ID`
- `GCP_REGION`

---

## Spotify API の仕様と制約

### 認証フロー
- Authorization Code Flow を事前に完了させ、Refresh Token を Secret Manager に保存済み
- ETL 実行時は Refresh Token → Access Token の交換のみ行う
- Access Token の有効期限は1時間。1回の ETL 実行内で再取得が必要なケースは想定しない

### ページネーション
- `saved_tracks` は最大50件/リクエスト。`next` フィールドが存在する間ループする
- `audio_features` は最大100件/リクエスト。track_id のリストをチャンク分割して呼ぶ

### レートリミット
- 429 が返ったら `Retry-After` ヘッダの秒数だけ待ってリトライ（最大3回）
- 実用上はリクエスト間に 0.1秒の sleep を入れる

---

## BigQuery テーブルスキーマ

### raw.saved_tracks
```json
[
  {"name": "added_at", "type": "TIMESTAMP"},
  {"name": "track", "type": "JSON"}
]
```
`track` は Spotify API のレスポンスをそのまま JSON 型で格納する。

### raw.audio_features
```json
[
  {"name": "id",               "type": "STRING"},
  {"name": "danceability",     "type": "FLOAT"},
  {"name": "energy",           "type": "FLOAT"},
  {"name": "key",              "type": "INTEGER"},
  {"name": "loudness",         "type": "FLOAT"},
  {"name": "mode",             "type": "INTEGER"},
  {"name": "speechiness",      "type": "FLOAT"},
  {"name": "acousticness",     "type": "FLOAT"},
  {"name": "instrumentalness", "type": "FLOAT"},
  {"name": "liveness",         "type": "FLOAT"},
  {"name": "valence",          "type": "FLOAT"},
  {"name": "tempo",            "type": "FLOAT"},
  {"name": "duration_ms",      "type": "INTEGER"},
  {"name": "time_signature",   "type": "INTEGER"}
]
```

---

## dbt モデル設計

### staging
- `stg_saved_tracks`：`raw.saved_tracks` の `track` JSON を UNNEST し、カラムとして展開
- `stg_audio_features`：`raw.audio_features` をそのままリネーム・型変換

### dimensions
- `dim_track`：`track_id` でユニーク化。`audio_features` の値を JOIN して保持
- `dim_artist`：`stg_saved_tracks` の `artists` 配列を UNNEST して `artist_id` でユニーク化
- `dim_date`：`added_at` から `date_id`（YYYYMMDD整数）/ `year` / `month` / `day` / `day_of_week` を生成

### facts
- `fct_saved_tracks`：`added_at` / `track_id` / `artist_id` / `date_id` のグレインで1行1レコード

### genres の扱い
`track.artists[].genres` は REPEATED フィールド。`dim_artist` を作る際に `UNNEST` して展開し、`artist_genres` ブリッジテーブルを生成する（SCD非対応）。

---

## GCP リソース詳細

| リソース | 値 |
|---|---|
| プロジェクト | 環境変数 `GCP_PROJECT_ID` から参照 |
| リージョン | `asia-northeast1` |
| Cloud Run Jobs メモリ | `512Mi` |
| Cloud Run Jobs タイムアウト | `300s` |
| Scheduler cron | `0 21 * * *`（UTC）= JST 06:00 |
| GCS バケット ライフサイクル | `raw/` プレフィックスのオブジェクトを90日後に削除 |
| BQ パーティション | `added_at` カラムで DATE パーティション |
| BQ クラスタリング | `track_id` |

---

## 依存関係ファイルの分離

| ファイル | 用途 | Dockerfileに含める |
|---|---|---|
| `etl/requirements.txt` | ETL ランタイム依存（google-cloud-bigquery 等） | はい |
| `requirements-dev.txt` | 開発・CI 専用（ruff / sqlfluff / dbt-bigquery） | いいえ |

`ruff` と `sqlfluff` は `requirements-dev.txt` にのみ記載する。

## Dockerfile の要件

- ベースイメージ：`python:3.12-slim`
- 作業ディレクトリ：`/app`
- `etl/` と `dbt/` の両方をコピーする
- `etl/requirements.txt` のみインストールする（`requirements-dev.txt` は含めない）
- dbt は `pip install dbt-bigquery` で導入
- エントリポイント：`python etl/main.py`

---

## GitHub Actions ワークフロー

ワークフローファイルは3つに分割する。

### lint.yml（PR 作成・更新時）

トリガー：`pull_request`

```
job: lint-python
  - ruff check etl/
  - ruff format --check etl/

job: lint-sql
  - sqlfluff lint dbt/models/ --dialect bigquery
```

- GCP 認証不要。ubuntu-latest に `uv pip install ruff sqlfluff dbt-bigquery` するだけ
- `ruff` / `sqlfluff` は Dockerfile には含めない（開発・CI専用）
- Python は `ruff`（lint + format チェックを1ツールで統一）
- SQL は `sqlfluff`（dialect: bigquery）

### build.yml（PR 作成・更新時）

トリガー：`pull_request`

```
job: build
  - docker build .  ※ push しない
```

- GCP 認証不要。Docker の buildx があれば動く
- lint.yml とは独立して並列実行

### deploy.yml（PR マージ = push to main 時）

トリガー：`push` to `main`

```
job: deploy
  1. Workload Identity Federation で GCP 認証
  2. gcloud auth configure-docker asia-northeast1-docker.pkg.dev
  3. docker build & push to Artifact Registry
  4. gcloud run jobs deploy
```

`gcloud run jobs deploy` のフラグ：
- `--image`
- `--region asia-northeast1`
- `--memory 512Mi`
- `--task-timeout 300`
- `--set-secrets` で Secret Manager のシークレットを環境変数にマップ
- `--service-account etl-job-sa@...`

---

## 実装時の注意点

### 認証・クレデンシャル
- ローカル開発は `gcloud auth application-default login` による ADC を使う
- Cloud Run Jobs 上では ADC が自動的に `etl-job-sa` として動作する。コード内でクレデンシャルファイルを扱わない
- dbt の `profiles.yml` は `method: oauth`（ADC）で統一する。ローカル・Cloud Run どちらも同じ設定で動く

### ローカル開発環境
- パッケージ管理は `uv`。`pip` は使わない
- venv は `.venv/`（`.gitignore` 済み）
- ETL の環境変数は `.env` ファイルで管理（`.gitignore` 済み）。`.env.example` をテンプレートとしてコミットする
- dbt 単体で動作確認する場合は `dbt run --select <model_name>` で個別モデルを指定する

### ライブラリ
- BigQuery クライアント：`google-cloud-bigquery`（`bigquery_storage` は不要）
- GCS クライアント：`google-cloud-storage`

### エラーハンドリング
- エラーが発生したら例外をそのまま raise する（Cloud Run Jobs はノンゼロ終了コードで失敗とみなされリトライされる）
