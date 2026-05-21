# CLAUDE.md — 実装ガイド

このファイルはコードから読み取れない決定事項・制約・仕様を記録する。実装済みのファイルの説明は書かない。

---

## アーキテクチャ決定事項

1つの Cloud Run Jobs が3ステップを順次実行する（複数 Job には分割しない）。

```
Step 1: Spotify API → GCS (JSONL)
Step 2: GCS → BigQuery Load Job (raw テーブル)
Step 3: dbt run
```

### GCS への書き込み
- フォーマット：JSONL（1行1レコード）
- パス：`raw/saved_tracks/YYYY-MM-DD.jsonl` / `raw/audio_features/YYYY-MM-DD.jsonl`
- フラット化しない。ネスト構造はそのまま書き込む（dbt に委譲）

### BigQuery への Load
- `WRITE_TRUNCATE`（毎回全件取得のため上書き）
- スキーマ自動検出は使わず、明示的にスキーマを定義する

---

## 環境変数・シークレット

| 環境変数名 | 取得元 | 値 |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | Secret Manager: `spotify-client-id` | |
| `SPOTIFY_CLIENT_SECRET` | Secret Manager: `spotify-client-secret` | |
| `SPOTIFY_REFRESH_TOKEN` | Secret Manager: `spotify-refresh-token` | |
| `GCS_BUCKET` | Cloud Run 環境変数 | `dp-spotify-raw` |
| `BQ_PROJECT` | Cloud Run 環境変数 | GCP プロジェクト ID |
| `BQ_DATASET` | Cloud Run 環境変数 | `raw` |

---

## Spotify API の仕様と制約

- `saved_tracks`：最大50件/リクエスト。`next` フィールドが存在する間ループする
- `audio_features`：最大100件/リクエスト。track_id をチャンク分割して呼ぶ
- 429 が返ったら `Retry-After` ヘッダの秒数だけ待ってリトライ（最大3回）
- リクエスト間に 0.1秒の sleep を入れる

---

## BigQuery テーブルスキーマ

### raw.saved_tracks
```json
[
  {"name": "added_at", "type": "TIMESTAMP"},
  {"name": "track",    "type": "JSON"}
]
```

---

## dbt モデル設計

### staging
- `stg_saved_tracks`：`raw.saved_tracks` の `track` JSON を展開してカラム化

### dimensions
- `dim_track`：`track_id` でユニーク化
- `dim_artist`：`artists` 配列を UNNEST して `artist_id` でユニーク化
- `dim_date`：`added_at` から `date_id`（YYYYMMDD整数）/ `year` / `month` / `day` / `day_of_week` を生成

### facts
- `fct_saved_tracks`：`added_at` / `track_id` / `artist_id` / `date_id` のグレイン

### genres の扱い
`track.artists[].genres` は REPEATED。`dim_artist` 作成時に UNNEST して `artist_genres` ブリッジテーブルを生成する。

---

## GCP リソース

| リソース | 値 |
|---|---|
| リージョン | `asia-northeast1` |
| GCS バケット | `dp-spotify-raw` |
| BQ データセット（ETL） | `raw` |
| Scheduler cron | `0 21 * * *` UTC = JST 06:00 |
| BQ パーティション | `added_at` で DATE パーティション |
| BQ クラスタリング | `track_id` |

---

## Lint / Format

### Python — ruff

```bash
cd etl
uv run ruff check . --fix   # lint + 自動修正
uv run ruff format .        # format
```

CI（`lint.yml`）は `ruff check` と `ruff format --check` を実行する。ローカルで通してから push する。

### SQL — sqlfluff（dialect: bigquery）

```bash
cd etl
uv run sqlfluff lint ../dbt/ --dialect bigquery   # lint
uv run sqlfluff fix ../dbt/ --dialect bigquery    # format
```

dbt モデル（`.sql`）はすべて sqlfluff の対象。CI も同じコマンドを実行する。

---

## 実装時の注意点

- Cloud Run Jobs 上では ADC が自動的に `etl-job-sa` として動作する。クレデンシャルファイルを扱わない
- dbt の `profiles.yml` は `method: oauth`（ADC）でローカル・Cloud Run を統一する
- エラーは例外をそのまま raise する（Cloud Run Jobs はノンゼロ終了コードで失敗＝リトライ）
- ローカル開発は `uv`。`pip` は使わない
