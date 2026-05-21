from datetime import date

from gcs_writer import GCSWriter
from spotify_client import SpotifyClient


def main():
    client = SpotifyClient()
    writer = GCSWriter()
    run_date = date.today()

    # Step 1: Spotify API → GCS
    # since=None for now; will be wired to MAX(added_at) from BQ when bq_loader is implemented
    print("Fetching saved tracks...")
    tracks = client.get_saved_tracks(since=None)
    print(f"Fetched {len(tracks)} tracks")

    track_ids = [item["track"]["id"] for item in tracks if item.get("track")]

    print("Fetching audio features...")
    features = client.get_audio_features(track_ids)
    print(f"Fetched {len(features)} audio features")

    path1 = writer.write(tracks, "saved_tracks", run_date)
    path2 = writer.write(features, "audio_features", run_date)
    print(f"Written: {path1}, {path2}")


if __name__ == "__main__":
    main()
