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

# STAGE 1 — build Python 3.13 and Home Assistant from source
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS builder

# Redeclare ARG in this stage so it's available for use in RUN commands
ARG PACKAGE_URL

WORKDIR /app

# Build Python 3.13 from source and install Home Assistant
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gcc \
    g++ \
    make \
    libffi-dev \
    libssl-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    liblzma-dev \
    zlib1g-dev \
 && curl -O https://www.python.org/ftp/python/3.13.2/Python-3.13.2.tar.xz \
 && tar -xf Python-3.13.2.tar.xz \
 && cd Python-3.13.2 \
 && ./configure --enable-optimizations --enable-shared --prefix=/usr/local \
 && make -j$(nproc) \
 && make install \
 && ldconfig \
 && cd /app \
 && rm -rf Python-3.13.2 Python-3.13.2.tar.xz \
 && /usr/local/bin/python3.13 -m venv /app/venv \
 && /app/venv/bin/pip install --upgrade pip setuptools wheel \
 && curl -L -f "${PACKAGE_URL}" -o homeassistant-source.tar.gz \
 && tar -xzf homeassistant-source.tar.gz \
 && cd core-* \
 && /app/venv/bin/pip install --no-cache-dir . \
 && cd /app \
 && test -f /app/venv/bin/hass || (echo "ERROR: hass binary not found after installation" && exit 1) \
 && rm -rf homeassistant-source.tar.gz core-*

# STAGE 2 — install runtime dependencies (shared libs for Python 3.13)
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS ha-deps

# Use BuildKit cache mounts to persist apt cache between builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libffi8 \
    libssl3 \
    libbz2-1.0 \
    libreadline8 \
    libsqlite3-0 \
    libncurses6 \
    libncursesw6 \
    libtk8.6 \
    libxml2 \
    libxmlsec1 \
    liblzma5 \
    zlib1g \
    libc6 \
 && rm -rf /var/lib/apt/lists/*

# STAGE 3 — distroless final image
FROM ${BASE_IMAGE}:${BASE_TAG}@${BASE_DIGEST}

# Hardcoded for amd64 - no conditionals needed!
ARG LIB_DIR=x86_64-linux-gnu

# Copy Python virtual environment from builder
COPY --from=builder /app/venv /app/venv

# Copy Python 3.13 binaries from builder
COPY --from=builder /usr/local/bin/python3.13 /usr/bin/python3.13
COPY --from=builder /usr/local/bin/python3 /usr/bin/python3

# Copy Python 3.13 standard library
COPY --from=builder /usr/local/lib/python3.13 /usr/local/lib/python3.13

# Copy Python 3.13 shared library and symlinks
COPY --from=builder /usr/local/lib/libpython3.13.so* /usr/local/lib/

# Copy runtime dependencies for Python
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libffi.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libssl.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libcrypto.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libbz2.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libreadline.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libsqlite3.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libncurses.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libncursesw.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libtk8.6.so /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libxml2.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libxmlsec1.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/liblzma.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /usr/lib/${LIB_DIR}/libz.so.* /usr/lib/${LIB_DIR}/
COPY --from=ha-deps /lib/${LIB_DIR}/libtinfo.so.* /lib/${LIB_DIR}/

WORKDIR /config
USER 65532:65532

# Set environment variables
ENV PATH="/app/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

ENTRYPOINT ["/app/venv/bin/hass", "--config", "/config"]
