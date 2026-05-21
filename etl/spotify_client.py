import os
import time
import requests
from datetime import datetime


class SpotifyClient:
    _TOKEN_URL = "https://accounts.spotify.com/api/token"
    _API_BASE = "https://api.spotify.com/v1"

    def __init__(self):
        self._client_id = os.environ["SPOTIFY_CLIENT_ID"]
        self._client_secret = os.environ["SPOTIFY_CLIENT_SECRET"]
        self._refresh_token = os.environ["SPOTIFY_REFRESH_TOKEN"]
        self._access_token = self._refresh_access_token()

    def _refresh_access_token(self) -> str:
        resp = requests.post(
            self._TOKEN_URL,
            data={"grant_type": "refresh_token", "refresh_token": self._refresh_token},
            auth=(self._client_id, self._client_secret),
        )
        resp.raise_for_status()
        return resp.json()["access_token"]

    def _get(self, url: str, params: dict = None) -> dict:
        for attempt in range(3):
            resp = requests.get(
                url,
                headers={"Authorization": f"Bearer {self._access_token}"},
                params=params,
            )
            if resp.status_code == 429:
                time.sleep(int(resp.headers.get("Retry-After", 1)))
                continue
            resp.raise_for_status()
            return resp.json()
        raise RuntimeError(f"Failed after 3 retries: {url}")

    def get_saved_tracks(self, since: datetime = None) -> list[dict]:
        """Fetch saved tracks. If since is given, stops when older tracks are encountered."""
        tracks = []
        url = f"{self._API_BASE}/me/tracks"
        params = {"limit": 50}

        while url:
            data = self._get(url, params)
            for item in data["items"]:
                if since:
                    added_at = datetime.fromisoformat(item["added_at"].replace("Z", "+00:00"))
                    if added_at <= since:
                        return tracks
                tracks.append(item)
            time.sleep(0.1)
            url = data.get("next")
            params = None

        return tracks

    def get_audio_features(self, track_ids: list[str]) -> list[dict]:
        features = []
        for i in range(0, len(track_ids), 100):
            chunk = track_ids[i : i + 100]
            data = self._get(f"{self._API_BASE}/audio-features", params={"ids": ",".join(chunk)})
            features.extend(f for f in data["audio_features"] if f)
            time.sleep(0.1)
        return features
