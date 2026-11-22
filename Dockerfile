# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# Stage 1: build dependencies on a slim image (has pip, compilers not needed
# because all deps ship manylinux wheels).
# In an IL5/air-gapped enclave, point these FROM lines at the mirrored
# registry (e.g. <acct>.dkr.ecr.us-gov-west-1.amazonaws.com/mirror/...) and
# pin by digest (@sha256:...). Iron Bank (registry1.dso.mil) images are the
# DoD-hardened equivalent.
# ---------------------------------------------------------------------------
FROM python:3.15-slim-trixie AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --target=/deps -r requirements.txt

COPY app/ /build/app/
RUN python -m compileall -q /deps /build/app \
 && rm -rf /build/app/tests

# ---------------------------------------------------------------------------
# Stage 2: distroless runtime. No shell, no package manager, runs as the
# built-in non-root user (uid 65532). Python 3.13 matches the builder.
# ---------------------------------------------------------------------------
FROM gcr.io/distroless/python3-debian13:nonroot AS runtime

LABEL org.opencontainers.image.title="mission-api" \
      org.opencontainers.image.description="FastAPI service protected by Keycloak OIDC" \
      org.opencontainers.image.source="https://github.com/OWNER/devsecops-eks-demo" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONPATH=/app/deps:/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY --from=builder --chown=65532:65532 /deps /app/deps
COPY --from=builder --chown=65532:65532 /build/app /app/app

USER 65532:65532
EXPOSE 8000

# No curl in distroless, so use the interpreter for the health probe.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"]

ENTRYPOINT ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header", "--proxy-headers"]
