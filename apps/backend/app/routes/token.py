"""LiveKit token API route for QuoteApp."""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
from typing import Optional

from app.config import get_settings
from app.services.livekit_service import (
    LiveKitConfigError,
    LiveKitTokenNotReadyError,
    create_room_token,
)

router = APIRouter(prefix="/livekit", tags=["livekit"])


class LiveKitTokenRequest(BaseModel):
    """Minimal request payload for minting a room token."""

    identity: str = Field(min_length=1, max_length=128)
    room: str = Field(min_length=1, max_length=128)
    name: Optional[str] = Field(default=None, max_length=128)


class LiveKitTokenResponse(BaseModel):
    """Token response shape for iOS consumption."""

    token: str
    url: str
    identity: str
    room: str


@router.post("/token", response_model=LiveKitTokenResponse)
def create_livekit_token(payload: LiveKitTokenRequest) -> LiveKitTokenResponse:
    """Returns a LiveKit JWT when config and package are ready."""

    settings = get_settings()

    try:
        token_result = create_room_token(
            settings=settings,
            identity=payload.identity,
            room=payload.room,
            name=payload.name,
        )
    except LiveKitConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "missing_livekit_config",
                "message": "Missing required LiveKit environment variables.",
                "missing_env": exc.missing_env,
            },
        ) from exc
    except LiveKitTokenNotReadyError as exc:
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail={
                "code": "token_not_ready",
                "message": str(exc),
            },
        ) from exc

    return LiveKitTokenResponse(
        token=token_result.token,
        url=token_result.url,
        identity=payload.identity,
        room=payload.room,
    )
