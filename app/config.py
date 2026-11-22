"""Runtime configuration, loaded from environment variables (12-factor)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache


def _split(value: str) -> list[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


@dataclass(frozen=True)
class Settings:
    # Issuer that appears in the token's `iss` claim (what clients see).
    oidc_issuer: str = field(
        default_factory=lambda: os.getenv(
            "OIDC_ISSUER", "http://localhost:8080/realms/devsecops"
        )
    )
    # JWKS URL the API uses to fetch signing keys. Can differ from the issuer
    # host (e.g. in-cluster service DNS or a VPC endpoint in an air-gapped enclave).
    oidc_jwks_url: str = field(default_factory=lambda: os.getenv("OIDC_JWKS_URL", ""))
    oidc_audience: str = field(default_factory=lambda: os.getenv("OIDC_AUDIENCE", "mission-api"))
    required_role: str = field(
        default_factory=lambda: os.getenv("REQUIRED_ROLE", "mission-reader")
    )
    allowed_algorithms: list[str] = field(
        default_factory=lambda: _split(os.getenv("OIDC_ALGORITHMS", "RS256"))
    )
    environment: str = field(default_factory=lambda: os.getenv("APP_ENV", "local"))

    @property
    def jwks_url(self) -> str:
        return self.oidc_jwks_url or f"{self.oidc_issuer.rstrip('/')}/protocol/openid-connect/certs"


@lru_cache
def get_settings() -> Settings:
    return Settings()
