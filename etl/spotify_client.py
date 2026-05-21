import os
import time
import requests


class SpotifyClient:
    _TOKEN_URL = "https://accounts.spotify.com/api/token"
    _API_BASE = "https://api.spotify.com/v1"

    def __init__(self):
        self._client_id = os.environ["SPOTIFY_CLIENT_ID"]
        self._client_secret = os.environ["SPOTIFY_CLIENT_SECRET"]
        self._refresh_token = os.environ["SPOTIFY_REFRESH_TOKEN"]
        self._access_token = self._refresh_access_token()

    def _refresh_access_token(self) -> str:
        # Refresh Token を使って Access Token を取得する（有効期限1時間）
        resp = requests.post(
            self._TOKEN_URL,
            data={"grant_type": "refresh_token", "refresh_token": self._refresh_token},
            auth=(self._client_id, self._client_secret),
        )
        resp.raise_for_status()
        return resp.json()["access_token"]

    def _get(self, url: str, params: dict = None) -> dict:
        # 429 レートリミット時は Retry-After ヘッダの秒数だけ待ってリトライ
        for _ in range(3):
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

    def get_saved_tracks(self) -> list[dict]:
        # 50件/リクエストでページネーションしながら全件取得
        tracks = []
        url = f"{self._API_BASE}/me/tracks"
        params = {"limit": 50}

        while url:
            data = self._get(url, params)
            tracks.extend(data["items"])
            time.sleep(0.1)
            url = data.get("next")
            params = None  # next URL にはすでにクエリパラメータが含まれている

        return tracks

    def get_audio_features(self, track_ids: list[str]) -> list[dict]:
        # 最大100件/リクエストのためチャンク分割して取得
        features = []
        for i in range(0, len(track_ids), 100):
            chunk = track_ids[i : i + 100]
            data = self._get(f"{self._API_BASE}/audio-features", params={"ids": ",".join(chunk)})
            # 取得できなかったトラック（None）は除外する
            features.extend(f for f in data["audio_features"] if f)
            time.sleep(0.1)
        return features
