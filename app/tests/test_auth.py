import time

import jwt
import pytest

from app.config import Settings

URL = "/api/v1/mission"


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_missing_token_is_401(client):
    resp = client.get(URL)
    assert resp.status_code == 401
    assert resp.headers["WWW-Authenticate"] == "Bearer"


def test_valid_token_with_role_is_200(client, make_token):
    resp = client.get(URL, headers=auth(make_token()))
    assert resp.status_code == 200
    body = resp.json()
    assert "analyst1" in body["message"]
    assert body["roles"] == ["mission-reader"]


def test_missing_role_is_403(client, make_token):
    token = make_token(realm_access={"roles": ["offline_access"]})
    assert client.get(URL, headers=auth(token)).status_code == 403


def test_expired_token_is_401(client, make_token):
    now = int(time.time())
    token = make_token(iat=now - 3600, exp=now - 600)
    resp = client.get(URL, headers=auth(token))
    assert resp.status_code == 401
    assert resp.json()["detail"] == "token expired"


@pytest.mark.parametrize(
    "overrides",
    [
        {"iss": "https://evil.example/realms/devsecops"},
        {"aud": "some-other-client"},
        {"sub": None},
    ],
)
def test_bad_claims_are_401(client, make_token, overrides):
    assert client.get(URL, headers=auth(make_token(**overrides))).status_code == 401


def test_wrong_signing_key_is_401(client, make_token, other_rsa_key):
    token = make_token(key=other_rsa_key)
    assert client.get(URL, headers=auth(token)).status_code == 401


def test_hs256_alg_confusion_rejected(client):
    now = int(time.time())
    token = jwt.encode(
        {"iss": "x", "aud": "mission-api", "sub": "a", "iat": now, "exp": now + 60},
        "shared-secret-attack-0123456789abcdef",
        algorithm="HS256",
    )
    assert client.get(URL, headers=auth(token)).status_code == 401


def test_garbage_token_is_401(client):
    assert client.get(URL, headers=auth("not.a.jwt")).status_code == 401


def test_jwks_url_derived_from_issuer():
    s = Settings(oidc_issuer="http://kc:8080/realms/r/", oidc_jwks_url="")
    assert s.jwks_url == "http://kc:8080/realms/r/protocol/openid-connect/certs"
    s2 = Settings(oidc_jwks_url="http://internal/certs")
    assert s2.jwks_url == "http://internal/certs"
