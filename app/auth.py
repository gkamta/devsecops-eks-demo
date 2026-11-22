"""Keycloak OIDC bearer-token validation.

Validates RS256-signed JWTs against the realm's JWKS: signature, expiry,
issuer, audience, and (optionally) a realm role. Maps to NIST 800-53
IA-2 (identification & authentication) and AC-3/AC-6 (access enforcement,
least privilege).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Protocol

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

log = logging.getLogger(__name__)

bearer_scheme = HTTPBearer(auto_error=False)


class SigningKeyResolver(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> Any: ...


@lru_cache
def _jwks_client(jwks_url: str) -> jwt.PyJWKClient:
    # Keys are cached in-process; Keycloak key rotation is picked up on `kid` miss.
    return jwt.PyJWKClient(jwks_url, cache_keys=True, lifespan=300, timeout=5)


def get_key_resolver(settings: Settings = Depends(get_settings)) -> SigningKeyResolver:
    return _jwks_client(settings.jwks_url)


@dataclass(frozen=True)
class Principal:
    subject: str
    username: str | None
    roles: frozenset[str]
    claims: dict[str, Any]


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def decode_token(token: str, settings: Settings, resolver: SigningKeyResolver) -> dict[str, Any]:
    try:
        signing_key = resolver.get_signing_key_from_jwt(token)
        key = getattr(signing_key, "key", signing_key)
        return jwt.decode(
            token,
            key=key,
            algorithms=settings.allowed_algorithms,  # never accept "none"/HS* from config
            audience=settings.oidc_audience,
            issuer=settings.oidc_issuer,
            options={"require": ["exp", "iat", "iss", "sub", "aud"]},
            leeway=30,
        )
    except jwt.ExpiredSignatureError as exc:
        raise _unauthorized("token expired") from exc
    except jwt.InvalidTokenError as exc:
        log.info("rejected token: %s", type(exc).__name__)
        raise _unauthorized("invalid token") from exc
    except jwt.PyJWKClientError as exc:
        log.warning("unable to resolve signing key: %s", exc)
        raise _unauthorized("invalid token") from exc


def get_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    settings: Settings = Depends(get_settings),
    resolver: SigningKeyResolver = Depends(get_key_resolver),
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized("missing bearer token")
    claims = decode_token(credentials.credentials, settings, resolver)
    roles = frozenset(claims.get("realm_access", {}).get("roles", []))
    return Principal(
        subject=claims["sub"],
        username=claims.get("preferred_username"),
        roles=roles,
        claims=claims,
    )


def require_role(principal: Principal = Depends(get_principal),
                 settings: Settings = Depends(get_settings)) -> Principal:
    if settings.required_role and settings.required_role not in principal.roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="insufficient role")
    return principal
