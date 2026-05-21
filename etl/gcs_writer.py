import json
import os
from datetime import date

from google.cloud import storage


class GCSWriter:
    def __init__(self):
        self._bucket = storage.Client().bucket(os.environ["GCS_BUCKET"])

    def write(self, records: list[dict], prefix: str, run_date: date) -> str:
        path = f"raw/{prefix}/{run_date.isoformat()}.jsonl"
        content = "\n".join(json.dumps(r, ensure_ascii=False) for r in records)
        self._bucket.blob(path).upload_from_string(content, content_type="application/jsonl")
        return path
