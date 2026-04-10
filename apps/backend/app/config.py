"""Backend configuration for the QuoteApp FastAPI service."""

from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-driven backend settings."""

    livekit_url: Optional[str] = None
    livekit_api_key: Optional[str] = None
    livekit_api_secret: Optional[str] = None

    backend_host: str = "127.0.0.1"
    backend_port: int = 8000

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def missing_livekit_env(self) -> list[str]:
        """Returns required env keys missing for token minting."""

        missing: list[str] = []

        if not self.livekit_url:
            missing.append("LIVEKIT_URL")
        if not self.livekit_api_key:
            missing.append("LIVEKIT_API_KEY")
        if not self.livekit_api_secret:
            missing.append("LIVEKIT_API_SECRET")

        return missing


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Returns memoized settings for app/runtime usage."""

    return Settings()
