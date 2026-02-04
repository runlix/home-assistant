# Home Assistant CI Configuration

This directory contains configuration and scripts for the CI/CD pipeline.

## Files

### docker-matrix.json

Defines the build matrix for multi-architecture Docker images. See the [schema documentation](https://github.com/runlix/build-workflow/blob/main/schema/docker-matrix-schema.json) for details.

**Variants:**
- `latest-amd64` - Stable build for AMD64
- `latest-arm64` - Stable build for ARM64
- `debug-amd64` - Debug build for AMD64 (includes debugging tools)
- `debug-arm64` - Debug build for ARM64 (includes debugging tools)

### smoke-test.sh

Automated smoke test script that validates built Docker images before they are released.

**What it tests:**
- ✅ Container starts successfully
- ✅ No critical errors in logs
- ✅ API endpoint responds (`/api/`)
- ✅ Web UI is accessible
- ✅ Correct architecture is used
- ✅ Home Assistant core starts properly

**Environment Variables:**
- `IMAGE_TAG` (required) - The Docker image tag to test (set by workflow)
- `PLATFORM` (optional) - Platform to test, defaults to `linux/amd64`

**Usage:**

The smoke test is automatically executed by the GitHub Actions workflow after each image is built. You can also run it locally:

```bash
# Export the image tag you want to test
export IMAGE_TAG="ghcr.io/runlix/home-assistant:pr-123-2025.1.6-stable-amd64-abc1234"

# Run the smoke test
.ci/smoke-test.sh
```

**Exit Codes:**
- `0` - All tests passed
- `1` - One or more tests failed

**Customization:**

You can customize the smoke test by editing `.ci/smoke-test.sh`. Some common customizations:

- **Change initialization wait time** (currently 30 seconds):
  ```bash
  sleep 30  # Change to longer if Home Assistant takes time to start
  ```

- **Add additional endpoint tests**:
  ```bash
  # Test API config endpoint
  if curl -fsSL "http://localhost:${HA_PORT}/api/config" -o /dev/null; then
    echo "✅ API config endpoint responding"
  fi
  ```

- **Change timeout values**:
  ```bash
  MAX_ATTEMPTS=30  # Number of API check attempts
  sleep 5          # Delay between attempts
  ```

## Testing Changes

Before committing changes to this configuration:

1. **Validate JSON syntax**:
   ```bash
   jq . docker-matrix.json
   ```

2. **Validate against schema**:
   ```bash
   curl -sL https://raw.githubusercontent.com/runlix/build-workflow/main/schema/docker-matrix-schema.json \
     > /tmp/schema.json
   ajv validate -s /tmp/schema.json -d docker-matrix.json
   ```

3. **Test smoke test locally** (requires Docker):
   ```bash
   # Build or pull an image
   docker pull ghcr.io/runlix/home-assistant:latest

   # Run the smoke test
   export IMAGE_TAG="ghcr.io/runlix/home-assistant:latest"
   .ci/smoke-test.sh
   ```

## Workflow Integration

The build workflow automatically:

1. **On Pull Requests**: Builds all variants and runs smoke tests
2. **On Merges to Release Branch**: Rebuilds all images and runs smoke tests
3. **After Tests Pass**: Creates multi-arch manifests and pushes to registry

See [build-workflow documentation](https://github.com/runlix/build-workflow/tree/main/docs) for more details.
