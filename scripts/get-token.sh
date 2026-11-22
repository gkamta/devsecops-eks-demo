#!/usr/bin/env bash
# Fetch an access token from the local Keycloak (docker compose) for a test user.
# Usage: scripts/get-token.sh [username] [password]
# Local demo only: uses the resource-owner password grant for convenience.
# Real users authenticate with the authorization-code + PKCE flow (CAC/PIV via an IdP).
set -euo pipefail
USER_NAME="${1:-analyst1}"
PASSWORD="${2:-Analyst#Demo2026}"
KC="${KC_URL:-http://localhost:8080}"

curl -fsS -X POST "${KC}/realms/devsecops/protocol/openid-connect/token" \
  -d grant_type=password \
  -d client_id=mission-cli \
  -d scope=openid \
  --data-urlencode "username=${USER_NAME}" \
  --data-urlencode "password=${PASSWORD}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
