"""Quote API routes for MVP mock quote retrieval."""

from fastapi import APIRouter

from app.models.quote import Quote
from app.services.quote_service import list_quotes

router = APIRouter(prefix="/quotes", tags=["quotes"])


@router.get("", response_model=list[Quote])
def get_quotes() -> list[Quote]:
    """Returns in-memory mock quotes."""

    return list_quotes()
