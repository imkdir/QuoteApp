"""Quote API routes for QuoteApp practice selection."""

from fastapi import APIRouter

from app.models.quote import Quote
from app.services.quote_service import list_quotes

router = APIRouter(prefix="/quotes", tags=["quotes"])


@router.get("", response_model=list[Quote])
def get_quotes() -> list[Quote]:
    """Returns the in-memory quote catalog."""

    return list_quotes()
