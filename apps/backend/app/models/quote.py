"""Quote response models for backend quote APIs."""

from pydantic import BaseModel


class Quote(BaseModel):
    """Minimal quote payload consumed by the iOS app."""

    id: str
    text: str
