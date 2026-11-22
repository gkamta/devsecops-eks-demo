from __future__ import annotations

import time
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.auth import get_key_resolver
from app.config import Settings, get_settings
from app.main import app

ISSUER = "https://keycloak.test/realms/devsecops"
AUDIENCE = "mission-api"


class StaticResolver:
    """Stands in for PyJWKClient so tests never hit the network."""

    def __init__(self, public_key):
        self._key = public_key

    def get_signing_key_from_jwt(self, token: str):
        return self._key


@pytest.fixture(scope="session")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(scope="session")
def other_rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        oidc_issuer=ISSUER,
        oidc_jwks_url="",
        oidc_audience=AUDIENCE,
        required_role="mission-reader",
        allowed_algorithms=["RS256"],
        environment="test",
    )


@pytest.fixture
def client(settings, rsa_key):
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_key_resolver] = lambda: StaticResolver(rsa_key.public_key())
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def make_token(rsa_key):
    def _make(key=None, **overrides):
        now = int(time.time())
        claims = {
            "iss": ISSUER,
            "aud": AUDIENCE,
            "sub": str(uuid.uuid4()),
            "iat": now,
            "exp": now + 300,
            "preferred_username": "analyst1",
            "realm_access": {"roles": ["mission-reader"]},
        }
        claims.update(overrides)
        claims = {k: v for k, v in claims.items() if v is not None}
        return jwt.encode(claims, key or rsa_key, algorithm="RS256", headers={"kid": "test"})

    return _make
