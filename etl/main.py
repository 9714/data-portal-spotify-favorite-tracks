from datetime import date

from dotenv import load_dotenv
from gcs_writer import GCSWriter
from spotify_client import SpotifyClient

load_dotenv()


def main():
    client = SpotifyClient()
    writer = GCSWriter()
    run_date = date.today()

    # Step 1: Spotify API → GCS
    print("Fetching saved tracks...")
    tracks = client.get_saved_tracks()
    print(f"Fetched {len(tracks)} tracks")

    path = writer.write(tracks, "saved_tracks", run_date)
    print(f"Written: {path}")


if __name__ == "__main__":
    main()
