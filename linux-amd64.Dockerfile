ARG BUILDER_REF="docker.io/library/debian:bookworm-slim@sha256:13cb01d584d2c23f475c088c168a48f9a08f033a10460572fbfd10912ec5ba7c"
ARG BASE_REF="ghcr.io/runlix/distroless-runtime-v2-canary:stable@sha256:6f96f11dbb9d8f6e76672e73bbf743dbec36d2e4f6d29250151a48379a8c66dd"
ARG PACKAGE_URL="https://github.com/home-assistant/core/archive/refs/tags/2026.4.0.tar.gz"
ARG GO2RTC_VERSION="1.9.14"

FROM ${BUILDER_REF} AS builder

ARG PACKAGE_URL

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      ca-certificates \
      curl \
      gcc \
      g++ \
      libbz2-dev \
      libffi-dev \
      liblzma-dev \
      libncurses5-dev \
      libncursesw5-dev \
      libpq-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      libtool \
      libxml2-dev \
      libxmlsec1-dev \
      make \
      pkg-config \
      tk-dev \
      xz-utils \
      zlib1g-dev \
 && curl -O https://www.python.org/ftp/python/3.14.2/Python-3.14.2.tar.xz \
 && tar -xf Python-3.14.2.tar.xz \
 && cd Python-3.14.2 \
 && ./configure --enable-optimizations --enable-shared --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig \
 && cd /app \
 && rm -rf Python-3.14.2 Python-3.14.2.tar.xz \
 && /usr/local/bin/python3.14 -m venv /app/venv \
 && /app/venv/bin/pip install --upgrade pip setuptools wheel uv \
 && curl -L -f "${PACKAGE_URL}" -o homeassistant-source.tar.gz \
 && tar -xzf homeassistant-source.tar.gz \
 && cd core-* \
 && /app/venv/bin/uv pip install --python /app/venv/bin/python -r requirements.txt \
 && /app/venv/bin/uv pip install --python /app/venv/bin/python -r requirements_all.txt \
 && /app/venv/bin/pip install --no-cache-dir zlib-ng isal psycopg2 sqlalchemy_utils numpy prettytable==3.12.0 \
 && /app/venv/bin/pip install --no-cache-dir --no-deps . \
 && cd /app \
 && test -f /app/venv/bin/hass \
 && rm -rf homeassistant-source.tar.gz core-* \
 && chown -R 65532:65532 /app/venv

FROM ${BUILDER_REF} AS ha-deps

ARG GO2RTC_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      binutils \
      build-essential \
      ca-certificates \
      curl \
      ffmpeg \
      gcc \
      g++ \
      libc6 \
      libc6-dev \
      libbz2-1.0 \
      libffi8 \
      libgcc-s1 \
      libgmp10 \
      libisl23 \
      liblzma5 \
      libmpc3 \
      libmpfr6 \
      libncurses6 \
      libncursesw6 \
      libpcap-dev \
      libpcap0.8 \
      libpq5 \
      libreadline8 \
      libsqlite3-0 \
      libssl3 \
      libstdc++6 \
      libtk8.6 \
      libturbojpeg0 \
      libxml2 \
      libxmlsec1 \
      zlib1g \
 && curl -L -f "https://github.com/AlexxIT/go2rtc/releases/download/v${GO2RTC_VERSION}/go2rtc_linux_amd64" -o /usr/bin/go2rtc \
 && chmod +x /usr/bin/go2rtc \
 && rm -rf /var/lib/apt/lists/*

FROM ${BASE_REF}

ARG LIB_DIR="x86_64-linux-gnu"

COPY --from=builder --chown=65532:65532 /app/venv /app/venv
COPY --from=builder /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=builder /usr/local/bin/python3.14 /usr/local/bin/python3.14
COPY --from=builder /usr/local/include/python3.14 /usr/local/include/python3.14
COPY --from=builder /usr/local/lib/python3.14 /usr/local/lib/python3.14
COPY --from=builder /usr/local/lib/libpython3.14.so /usr/local/lib/libpython3.14.so
COPY --from=builder /usr/local/lib/libpython3.14.so.1.0 /usr/local/lib/libpython3.14.so.1.0

COPY --from=ha-deps /usr/bin/as /usr/bin/as
COPY --from=ha-deps /usr/bin/c++ /usr/bin/c++
COPY --from=ha-deps /usr/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=ha-deps /usr/bin/ffprobe /usr/bin/ffprobe
COPY --from=ha-deps /usr/bin/g++ /usr/bin/g++
COPY --from=ha-deps /usr/bin/gcc /usr/bin/gcc
COPY --from=ha-deps /usr/bin/go2rtc /usr/bin/go2rtc
COPY --from=ha-deps /usr/bin/ld /usr/bin/ld
COPY --from=ha-deps /usr/bin/objdump /usr/bin/objdump
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-as /usr/bin/x86_64-linux-gnu-as
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-g++ /usr/bin/x86_64-linux-gnu-g++
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-g++-12 /usr/bin/x86_64-linux-gnu-g++-12
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-gcc /usr/bin/x86_64-linux-gnu-gcc
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-gcc-12 /usr/bin/x86_64-linux-gnu-gcc-12
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld /usr/bin/x86_64-linux-gnu-ld
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld.bfd /usr/bin/x86_64-linux-gnu-ld.bfd
COPY --from=ha-deps /usr/bin/x86_64-linux-gnu-ld.gold /usr/bin/x86_64-linux-gnu-ld.gold
COPY --from=ha-deps /usr/include /usr/include
COPY --from=ha-deps /usr/lib/gcc/x86_64-linux-gnu /usr/lib/gcc/x86_64-linux-gnu
COPY --from=ha-deps /usr/lib/${LIB_DIR}/ /usr/lib/${LIB_DIR}/

WORKDIR /config
USER 65532:65532

ENV LD_LIBRARY_PATH="/usr/local/lib"
ENV PATH="/app/venv/bin:/usr/local/bin:$PATH"
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/venv/bin/hass", "--config", "/config"]
