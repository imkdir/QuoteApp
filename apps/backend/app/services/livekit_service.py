"""LiveKit token helpers for QuoteApp backend."""

from dataclasses import dataclass
from typing import Optional

from app.config import Settings


class LiveKitConfigError(Exception):
    """Raised when required LiveKit env values are missing."""

    def __init__(self, missing_env: list[str]) -> None:
        super().__init__("Missing LiveKit environment variables")
        self.missing_env = missing_env


@dataclass
class LiveKitTokenResult:
    """Minimal token payload returned to API callers."""

    token: str
    url: str


class LiveKitTokenNotReadyError(Exception):
    """Raised when token minting cannot be completed yet."""


def create_room_token(
    *,
    settings: Settings,
    identity: str,
    room: str,
    name: Optional[str] = None,
) -> LiveKitTokenResult:
    """Mints a LiveKit room token when credentials and package are available."""

    missing_env = settings.missing_livekit_env
    if missing_env:
        raise LiveKitConfigError(missing_env)

    try:
        from livekit import api
    except Exception as exc:  # pragma: no cover - dependency/runtime guard
        raise LiveKitTokenNotReadyError(
            "livekit-api package is not available in this environment"
        ) from exc

    try:
        access_token = api.AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
        access_token = access_token.with_identity(identity)

        if name:
            access_token = access_token.with_name(name)

        access_token = access_token.with_grants(
            api.VideoGrants(room_join=True, room=room)
        )

        return LiveKitTokenResult(
            token=access_token.to_jwt(),
            url=settings.livekit_url or "",
        )
    except Exception as exc:
        raise LiveKitTokenNotReadyError(
            f"LiveKit token minting is not ready: {exc}"
        ) from exc
