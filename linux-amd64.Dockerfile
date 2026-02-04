# Builder image and tag from VERSION.json builder.image and builder.tag
ARG BUILDER_IMAGE=docker.io/library/debian
ARG BUILDER_TAG=bookworm-slim
# Base image and tag from VERSION.json base.image and base.tag
ARG BASE_IMAGE=ghcr.io/runlix/distroless-runtime
ARG BASE_TAG=stable
# Selected digests (build script will set based on target configuration)
# Default to empty string - build script should always provide valid digests
# If empty, FROM will fail (which is desired to enforce digest pinning)
ARG BUILDER_DIGEST=""
ARG BASE_DIGEST=""
# Home Assistant source tarball URL from GitHub releases
ARG PACKAGE_URL=""

# STAGE 1 — download and build Home Assistant from source
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS builder

# Redeclare ARG in this stage so it's available for use in RUN commands
ARG PACKAGE_URL

WORKDIR /app

# Use BuildKit cache mounts to persist apt and pip cache between builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    gcc \
    g++ \
    python3-dev \
    libffi-dev \
    libssl-dev \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /app/venv \
 && /app/venv/bin/pip install --upgrade pip setuptools wheel \
 && curl -L -f "${PACKAGE_URL}" -o homeassistant-source.tar.gz \
 && tar -xzf homeassistant-source.tar.gz \
 && /app/venv/bin/pip install ./core-* \
 && rm -rf homeassistant-source.tar.gz core-*

# STAGE 2 — install Home Assistant runtime dependencies
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS ha-deps

# Use BuildKit cache mounts to persist apt cache between builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libffi8 \
    libssl3 \
    libc6 \
 && rm -rf /var/lib/apt/lists/*

# STAGE 3 — distroless final image
FROM ${BASE_IMAGE}:${BASE_TAG}@${BASE_DIGEST}

# Hardcoded for amd64 - no conditionals needed!
ARG LIB_DIR=x86_64-linux-gnu

# Copy Python virtual environment from builder
COPY --from=builder /app/venv /app/venv

# Copy Python runtime and dependencies
COPY --from=ha-deps /usr/bin/python3.11 /usr/bin/python3.11
COPY --from=ha-deps /usr/bin/python3 /usr/bin/python3

# Copy shared libraries
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libpython3.11.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libffi.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libssl.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libcrypto.so.* /usr/lib/${LIB_DIR}/

# Create config directory
RUN mkdir -p /config && chown 65532:65532 /config

WORKDIR /config
USER 65532:65532

# Set environment variables
ENV PATH="/app/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/venv/bin/hass", "--config", "/config"]
