"""Marked token models used in mock practice analysis responses."""

from pydantic import BaseModel, Field


class MarkedToken(BaseModel):
    """A single token that should be highlighted for additional practice."""

    text: str = Field(min_length=1)
    normalized_text: str = Field(min_length=1)
