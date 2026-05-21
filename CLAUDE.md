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
- `GCS_ENV=dev` のときはデータセットに `dev_` プレフィックスを付ける（例：`dev_raw`）
- `GCS_ENV=prd` のときはプレフィックスなし（例：`raw`）
- dbt は `profiles.yml` の targets（dev/prd）で切り替える。`main.py` が `GCS_ENV` から `--target` を決定して渡す

---

## 環境変数・シークレット

| 環境変数名 | 取得元 | 値 |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | Secret Manager: `spotify-client-id` | |
| `SPOTIFY_CLIENT_SECRET` | Secret Manager: `spotify-client-secret` | |
| `SPOTIFY_REFRESH_TOKEN` | Secret Manager: `spotify-refresh-token` | |
| `GCS_ENV` | Cloud Run 環境変数 | `prd`（ローカルはコードデフォルトの `dev`） |
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
- `stg_saved_tracks`：`raw.saved_tracks` の `track` JSON を展開してカラム化（1行=1 track）
  - 展開するカラム：`track_id` / `track_name` / `duration_ms` / `explicit` / `isrc` / `spotify_url` / `album_id` / `album_name` / `album_type` / `album_release_date` / `artists`（JSON配列のまま保持）

### dimensions
- `dim_track`：`track_id` でユニーク化（`track_name` / `duration_ms` / `explicit` / `isrc` / `spotify_url` / `album_id` / `album_name` / `album_type` / `album_release_date`）
- `dim_artist`：`stg_saved_tracks.artists` 配列を UNNEST して `artist_id` でユニーク化（`artist_name` / `spotify_url`）
- `dim_date`：`added_at` から `date_id`（YYYYMMDD整数）/ `date` / `year` / `month` / `day` / `day_of_week` を生成

### intermediate
- `int_track_artists`：`stg_saved_tracks.artists` を UNNEST した `track_id` × `artist_id` ペア。`dim_artist` の元データ

### facts
- `fct_saved_tracks`：grain = `track_id`（`added_at` / `track_id` / `date_id`）

### genres の扱い
Spotify API の `saved_tracks` レスポンスには `track.artists[].genres` が含まれない（`/artists/{id}` エンドポイントを別途呼ぶ必要がある）。現時点ではスコープ外とし、ETL 拡張時に追加する。

---

## BigQuery 物理設計

- raw テーブルは `added_at` で DATE パーティション
- mart テーブルの主キーカラムでクラスタリング（`track_id` など）

---

## ログ形式

```
=== ETL start: YYYY-MM-DD ===
[Step N] <処理名>: start
[Step N] <処理名>: done (<補足情報>)
=== ETL done ===
```

- 各ステップの開始・終了を `[Step N] 処理名: start/done` で出力する
- done 行には件数・パスなど有用な補足情報を含める

---

## dbt コーディング規約

### モデル YAML
- `description` はモデル・カラム問わず必ず記載する（日本語）
- `data_type` は全カラムに必ず指定する
- `not_null` テストは NULL を許容する明確な事情がない限り全カラムに追加する

### JOIN 構文

- `JOIN ... ON` を使う。`JOIN ... USING` は使わない（sqlfluff ST07 ルールで禁止）
- BigQuery は `USING` をサポートするが、このプロジェクトでは明示的な `ON` 句で統一する

### カラム命名・型規約

| 型 | タイムゾーン | サフィックス | 例 |
|---|---|---|---|
| `DATE` | JST 変換済み | `_date` | `added_date` |
| `DATETIME` | JST 変換済み | `_datetime` | `added_datetime` |
| `TIMESTAMP` | UTC | `_at` | `added_at` |

- `_at`：raw レイヤーの TIMESTAMP はそのまま UTC で保持
- `_date` / `_datetime`：staging 以降で JST に変換してカラム化する

---

## 実装時の注意点

- Cloud Run Jobs 上では ADC が自動的に `etl-job-sa` として動作する。クレデンシャルファイルを扱わない
- dbt の `profiles.yml` は `method: oauth`（ADC）でローカル・Cloud Run を統一する
- エラーは例外をそのまま raise する（Cloud Run Jobs はノンゼロ終了コードで失敗＝リトライ）
- ローカル開発は `uv`。`pip` は使わない
