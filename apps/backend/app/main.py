"""FastAPI entrypoint for QuoteApp backend MVP."""

from fastapi import FastAPI

from app.routes.quotes import router as quotes_router
from app.routes.token import router as token_router

app = FastAPI(title="QuoteApp Backend", version="0.1.0")

app.include_router(quotes_router)
app.include_router(token_router)


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    """Simple health check endpoint."""

    return {"status": "ok", "service": "quoteapp-backend"}
