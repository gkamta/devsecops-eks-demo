"""Mission API entrypoint."""

from __future__ import annotations

import logging

from fastapi import Depends, FastAPI, Response

from app import __version__
from app.auth import Principal, require_role
from app.config import get_settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

app = FastAPI(
    title="Mission API",
    version=__version__,
    docs_url="/docs",
    redoc_url=None,
)


@app.middleware("http")
async def security_headers(request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


@app.get("/healthz", tags=["ops"])
def healthz() -> dict[str, str]:
    """Liveness/readiness probe. Unauthenticated, leaks nothing sensitive."""
    return {"status": "ok", "version": __version__, "env": get_settings().environment}


@app.get("/api/v1/mission", tags=["mission"])
def mission(principal: Principal = Depends(require_role)) -> dict[str, object]:
    """Protected endpoint: requires a valid Keycloak access token with the required realm role."""
    return {
        "message": f"Welcome, {principal.username or principal.subject}. Access granted.",
        "subject": principal.subject,
        "roles": sorted(principal.roles),
    }
