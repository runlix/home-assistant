# Home Assistant

`home-assistant` publishes the Runlix container image for [Home Assistant Core](https://github.com/home-assistant/core).

The current published image name is:

```text
ghcr.io/runlix/home-assistant
```

Use a versioned stable manifest tag from [release.json](release.json):

```dockerfile
FROM ghcr.io/runlix/home-assistant:<version>-stable
```

The authoritative published tags, digests, and source revision live in [release.json](release.json).

## What's Included

- Home Assistant Core installed into a Python virtual environment
- `ffmpeg` and `ffprobe`
- `go2rtc`
- shared runtime libraries from `distroless-runtime-v2-canary`

The container runs Home Assistant with `/config` as the working configuration directory.

## Branch Layout

`main` owns metadata and automation config:

- `README.md`
- `links.json`
- `release.json`
- `renovate.json`
- `.github/workflows/validate-release-metadata.yml`

`release` owns build and publish inputs:

- `.ci/build.json`
- `.ci/smoke-test.sh`
- `linux-*.Dockerfile`
- `.github/workflows/validate-build.yml`
- `.github/workflows/publish-release.yml`

## Release Flow

Changes merge to `release`, where `Publish Release` builds the versioned `stable` and `debug` multi-arch manifests, attests them, optionally sends Telegram, and opens the sync PR back to `main`.

`main` validates metadata and config-only changes with `Validate Release Metadata`.
