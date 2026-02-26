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
# go2rtc version expected by Home Assistant integration
ARG GO2RTC_VERSION="1.9.14"

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
    autoconf \
    automake \
    curl \
    gcc \
    g++ \
    libtool \
    make \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libpq-dev \
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
 && /app/venv/bin/pip install --upgrade pip setuptools wheel uv \
 && curl -L -f "${PACKAGE_URL}" -o homeassistant-source.tar.gz \
 && tar -xzf homeassistant-source.tar.gz \
 && cd core-* \
 && /app/venv/bin/uv pip install --python /app/venv/bin/python -r requirements.txt \
 && /app/venv/bin/uv pip install --python /app/venv/bin/python -r requirements_all.txt \
 && /app/venv/bin/pip install --no-cache-dir zlib-ng isal psycopg2 sqlalchemy_utils numpy \
 && /app/venv/bin/pip install --no-cache-dir --no-deps . \
 && cd /app \
 && test -f /app/venv/bin/hass || (echo "ERROR: hass binary not found after installation" && exit 1) \
 && rm -rf homeassistant-source.tar.gz core-* \
 && chown -R 65532:65532 /app/venv

# STAGE 2 — install runtime dependencies (shared libs for Python 3.13)
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS ha-deps

ARG GO2RTC_VERSION

# Use BuildKit cache mounts to persist apt cache between builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    binutils \
    build-essential \
    curl \
    ffmpeg \
    gcc \
    g++ \
    libc6-dev \
    libffi8 \
    libgcc-s1 \
    libgmp10 \
    libisl23 \
    libmpc3 \
    libmpfr6 \
    libssl3 \
    libstdc++6 \
    libturbojpeg0 \
    libbz2-1.0 \
    libpcap-dev \
    libreadline8 \
    libpcap0.8 \
    libsqlite3-0 \
    libpq5 \
    libncurses6 \
    libncursesw6 \
    libtk8.6 \
    libxml2 \
    libxmlsec1 \
    liblzma5 \
    zlib1g \
    libc6 \
 && curl -L -f "https://github.com/AlexxIT/go2rtc/releases/download/v${GO2RTC_VERSION}/go2rtc_linux_amd64" -o /usr/bin/go2rtc \
 && chmod +x /usr/bin/go2rtc \
 && rm -rf /var/lib/apt/lists/*

# STAGE 3 — distroless final image
FROM ${BASE_IMAGE}:${BASE_TAG}@${BASE_DIGEST}

# Hardcoded for amd64 - no conditionals needed!
ARG LIB_DIR=x86_64-linux-gnu

# Copy Python virtual environment from builder
COPY --from=builder --chown=65532:65532 /app/venv /app/venv

# Copy Python 3.13 binaries from builder (must match venv creation path)
COPY --from=builder /usr/local/bin/python3.13 /usr/local/bin/python3.13
COPY --from=builder /usr/local/bin/python3 /usr/local/bin/python3

# Copy Python 3.13 standard library
COPY --from=builder /usr/local/lib/python3.13 /usr/local/lib/python3.13
COPY --from=builder /usr/local/include/python3.13 /usr/local/include/python3.13

# Copy Python 3.13 shared library and symlinks
COPY --from=builder /usr/local/lib/libpython3.13.so /usr/local/lib/libpython3.13.so
COPY --from=builder /usr/local/lib/libpython3.13.so.1.0 /usr/local/lib/libpython3.13.so.1.0

# Copy runtime dependencies for Python
COPY --from=ha-deps /usr/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=ha-deps /usr/bin/ffprobe /usr/bin/ffprobe
COPY --from=ha-deps /usr/bin/go2rtc /usr/bin/go2rtc
COPY --from=ha-deps /usr/bin/c++ /usr/bin/c++
COPY --from=ha-deps /usr/bin/as /usr/bin/as
COPY --from=ha-deps /usr/bin/gcc /usr/bin/gcc
COPY --from=ha-deps /usr/bin/g++ /usr/bin/g++
COPY --from=ha-deps /usr/bin/ld /usr/bin/ld
COPY --from=ha-deps /usr/bin/objdump /usr/bin/objdump
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-as /usr/bin/x86_64-linux-gnu-as
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-gcc /usr/bin/x86_64-linux-gnu-gcc
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-gcc-12 /usr/bin/x86_64-linux-gnu-gcc-12
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-g++ /usr/bin/x86_64-linux-gnu-g++
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-g++-12 /usr/bin/x86_64-linux-gnu-g++-12
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld /usr/bin/x86_64-linux-gnu-ld
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld.bfd /usr/bin/x86_64-linux-gnu-ld.bfd
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld.gold /usr/bin/x86_64-linux-gnu-ld.gold
COPY --from=ha-deps /usr/lib/gcc/x86_64-linux-gnu /usr/lib/gcc/x86_64-linux-gnu
COPY --from=ha-deps /usr/include /usr/include
COPY --from=ha-deps /usr/lib/${LIB_DIR}/ /usr/lib/${LIB_DIR}/

WORKDIR /config
USER 65532:65532

# Set environment variables
ENV PATH="/app/venv/bin:/usr/local/bin:$PATH"
ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

ENTRYPOINT ["/app/venv/bin/hass", "--config", "/config"]
