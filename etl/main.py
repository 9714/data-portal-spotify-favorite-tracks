from datetime import date

from bq_loader import BQLoader
from dotenv import load_dotenv
from gcs_writer import GCSWriter
from spotify_client import SpotifyClient

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

    print("=== ETL done ===")


if __name__ == "__main__":
    main()
