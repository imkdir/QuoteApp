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
    tutor_tts_provider: str = "auto"
    tutor_tts_model: Optional[str] = None
    tutor_tts_voice: Optional[str] = None
    tutor_tts_openai_model: str = "gpt-4o-mini-tts"
    tutor_tts_openai_voice: str = "alloy"
    tutor_tts_gemini_model: str = "gemini-2.5-flash-preview-tts"
    tutor_tts_gemini_voice: str = "Kore"
    tutor_tts_speed: float = 1.0
    tutor_tts_timeout_seconds: float = 30.0
    openai_api_key: Optional[str] = None
    openai_base_url: str = "https://api.openai.com/v1"
    gemini_api_key: Optional[str] = None
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"

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

    @property
    def tutor_tts_provider_normalized(self) -> str:
        """Returns normalized tutor TTS provider id."""

        return self.tutor_tts_provider.strip().lower()

    @property
    def tutor_tts_speed_clamped(self) -> float:
        """Returns a restrained quote-reading speed multiplier."""

        return max(0.85, min(1.15, self.tutor_tts_speed))

    @property
    def tutor_tts_timeout_seconds_clamped(self) -> float:
        """Returns safe network timeout bounds for backend TTS calls."""

        return max(5.0, min(120.0, self.tutor_tts_timeout_seconds))

    @property
    def openai_base_url_normalized(self) -> str:
        """Returns OpenAI base URL without trailing slash."""

        return self.openai_base_url.rstrip("/")

    @property
    def gemini_base_url_normalized(self) -> str:
        """Returns Gemini base URL without trailing slash."""

        return self.gemini_base_url.rstrip("/")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Returns memoized settings for app/runtime usage."""

    return Settings()
