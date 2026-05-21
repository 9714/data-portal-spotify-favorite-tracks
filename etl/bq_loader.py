import os

from google.cloud import bigquery


class BQLoader:
    def __init__(self):
        self._client = bigquery.Client(project=os.environ["BQ_PROJECT"])
        self._project = os.environ["BQ_PROJECT"]
        # GCS_ENV=dev のときは dev_ プレフィックスを付けて本番データセットと分離する
        env = os.environ.get("GCS_ENV", "dev")
        base_dataset = os.environ["BQ_DATASET"]
        self._dataset = f"dev_{base_dataset}" if env == "dev" else base_dataset

    def load(self, gcs_path: str, table_name: str) -> int:
        # GCS URI から BigQuery テーブルへ Load Job を実行する
        bucket = os.environ["GCS_BUCKET"]
        uri = f"gs://{bucket}/{gcs_path}"
        table_ref = f"{self._project}.{self._dataset}.{table_name}"

        schema = self._get_schema(table_name)
        partition_field = self._get_partition_field(table_name)
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            schema=schema,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        )
        if partition_field:
            job_config.time_partitioning = bigquery.TimePartitioning(
                type_=bigquery.TimePartitioningType.DAY,
                field=partition_field,
            )

        load_job = self._client.load_table_from_uri(
            uri, table_ref, job_config=job_config
        )
        load_job.result()  # 完了まで待機（失敗時は例外を raise）
        return load_job.output_rows

    def _get_schema(self, table_name: str) -> list[bigquery.SchemaField]:
        schemas = {
            "saved_tracks": [
                bigquery.SchemaField("added_at", "TIMESTAMP"),
                bigquery.SchemaField("track", "JSON"),
            ],
            "artists": [
                bigquery.SchemaField("artist_id", "STRING"),
                bigquery.SchemaField("artist", "JSON"),
            ],
        }
        if table_name not in schemas:
            raise ValueError(f"Unknown table: {table_name}")
        return schemas[table_name]

    def _get_partition_field(self, table_name: str) -> str | None:
        partition_fields = {
            "saved_tracks": "added_at",
            "artists": None,
        }
        return partition_fields.get(table_name)
