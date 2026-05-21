from datetime import date

from gcs_writer import GCSWriter
from spotify_client import SpotifyClient


def main():
    client = SpotifyClient()
    writer = GCSWriter()
    run_date = date.today()

    # Step 1: Spotify API → GCS
    # since=None で全件取得（差分取得は bq_loader 実装後に MAX(added_at) を渡す）
    print("Fetching saved tracks...")
    tracks = client.get_saved_tracks(since=None)
    print(f"Fetched {len(tracks)} tracks")

    # ローカルトラック（track が null のケース）を除外してから ID を抽出
    track_ids = [item["track"]["id"] for item in tracks if item.get("track")]

    print("Fetching audio features...")
    features = client.get_audio_features(track_ids)
    print(f"Fetched {len(features)} audio features")

    # 2種類のデータをそれぞれ別プレフィックスに書き込む
    path1 = writer.write(tracks, "saved_tracks", run_date)
    path2 = writer.write(features, "audio_features", run_date)
    print(f"Written: {path1}, {path2}")


if __name__ == "__main__":
    main()
