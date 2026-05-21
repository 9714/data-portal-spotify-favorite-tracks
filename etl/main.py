import os
import re
import subprocess
from datetime import date
from pathlib import Path

from bq_loader import BQLoader
from dotenv import load_dotenv
from gcs_writer import GCSWriter
from spotify_client import SpotifyClient

_DBT_DIR = Path(__file__).parent.parent / "dbt"

load_dotenv()


def main():
    client = SpotifyClient()
    writer = GCSWriter()
    loader = BQLoader()
    run_date = date.today()

    print(f"=== ETL start: {run_date} ===")

    print("[Step 1] Spotify API → GCS: start")
    tracks = client.get_saved_tracks()
    path = writer.write(tracks, "saved_tracks", run_date)
    print(f"[Step 1] Spotify API → GCS: done ({len(tracks)} tracks, path={path})")

    print("[Step 2] GCS → BigQuery: start")
    loaded_rows = loader.load(path, "saved_tracks")
    print(
        f"[Step 2] GCS → BigQuery: done ({loaded_rows} rows, table={loader._dataset}.saved_tracks)"
    )

    print("[Step 3] dbt run: start")
    dbt_target = "prd" if os.environ.get("GCS_ENV") == "prd" else "dev"
    result = subprocess.run(
        [
            "dbt",
            "run",
            "--profiles-dir",
            str(_DBT_DIR),
            "--project-dir",
            str(_DBT_DIR),
            "--target",
            dbt_target,
        ],
        capture_output=True,
        text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode, result.args, result.stdout, result.stderr
        )
    match = re.search(r"PASS=(\d+).*TOTAL=(\d+)", result.stdout)
    models_summary = f"{match.group(1)}/{match.group(2)} models" if match else "done"
    print(f"[Step 3] dbt run: done ({models_summary})")

    print("=== ETL done ===")


if __name__ == "__main__":
    main()
