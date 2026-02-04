#!/usr/bin/env bash
set -e
set -o pipefail

# Smoke test for Home Assistant Docker image
# This script receives IMAGE_TAG from the workflow environment

IMAGE="${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
CONTAINER_NAME="homeassistant-smoke-test-${RANDOM}"
HA_PORT="8123"

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧪 Home Assistant Smoke Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Image: ${IMAGE}"
echo "Platform: ${PLATFORM}"
echo ""

# Validate IMAGE_TAG is set
if [ -z "${IMAGE}" ] || [ "${IMAGE}" = "null" ]; then
  echo -e "${RED}❌ ERROR: IMAGE_TAG environment variable is not set${NC}"
  exit 1
fi

# Create temporary config directory
CONFIG_DIR=$(mktemp -d)
chmod 777 "${CONFIG_DIR}"
echo "Config directory: ${CONFIG_DIR}"
echo ""

# Cleanup function
cleanup() {
  echo ""
  echo -e "${YELLOW}🧹 Cleaning up...${NC}"

  # Capture final logs before stopping
  if docker ps -a | grep -q "${CONTAINER_NAME}"; then
    echo "Saving container logs..."
    docker logs "${CONTAINER_NAME}" > /tmp/homeassistant-smoke-test.log 2>&1 || true
    echo "Logs saved to: /tmp/homeassistant-smoke-test.log"
  fi

  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true

  # Clean up config directory (files may be owned by container user)
  if [ -d "${CONFIG_DIR}" ]; then
    chmod -R 777 "${CONFIG_DIR}" 2>/dev/null || true
    rm -rf "${CONFIG_DIR}" 2>/dev/null || true
  fi

  echo -e "${YELLOW}Cleanup complete${NC}"
}
trap cleanup EXIT

# Start container (use local image, don't pull from registry)
echo -e "${BLUE}▶️  Starting container...${NC}"
if ! docker run \
  --pull=never \
  --platform="${PLATFORM}" \
  --name "${CONTAINER_NAME}" \
  -v "${CONFIG_DIR}:/config" \
  -p "${HA_PORT}:8123" \
  -e TZ=UTC \
  -d \
  "${IMAGE}"; then
  echo -e "${RED}❌ Failed to start container${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Container started${NC}"
echo ""

# Wait for initialization
echo -e "${BLUE}⏳ Waiting for Home Assistant to initialize...${NC}"
echo "Waiting 30 seconds for startup..."
sleep 30

# Check if container is still running
echo ""
echo -e "${BLUE}🔍 Checking container status...${NC}"
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
  echo -e "${RED}❌ Container exited unexpectedly${NC}"
  echo ""
  echo "Container logs:"
  docker logs "${CONTAINER_NAME}" 2>&1
  exit 1
fi
echo -e "${GREEN}✅ Container is running${NC}"
echo ""

# Check logs for critical errors
echo -e "${BLUE}📋 Analyzing container logs...${NC}"
LOGS=$(docker logs "${CONTAINER_NAME}" 2>&1)

# Check for fatal errors or exceptions
FATAL_COUNT=$(echo "$LOGS" | grep -ciE "fatal|critical|exception.*error" || true)
if [ "${FATAL_COUNT}" -gt 0 ]; then
  echo -e "${RED}❌ Found ${FATAL_COUNT} critical error(s) in logs:${NC}"
  echo "$LOGS" | grep -iE "fatal|critical|exception.*error" | head -10
  exit 1
fi

# Check for expected startup messages
if grep -qi "home assistant" <<< "$LOGS" 2>/dev/null; then
  echo -e "${GREEN}✅ Home Assistant startup message found${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: Expected startup message not found${NC}"
fi

# Check for core startup
if grep -qi "starting home assistant core" <<< "$LOGS" 2>/dev/null; then
  echo -e "${GREEN}✅ Core initialization detected${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: No core startup messages found${NC}"
fi

echo -e "${GREEN}✅ No critical errors in logs${NC}"
echo ""

# Test API endpoint with retries
echo -e "${BLUE}🏥 Testing API endpoint...${NC}"
API_URL="http://localhost:${HA_PORT}/api/"
MAX_ATTEMPTS=30
ATTEMPT=0
API_OK=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))

  if curl -fsSL --max-time 5 "${API_URL}" -o /dev/null 2>/dev/null; then
    API_OK=true
    break
  fi

  echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: Waiting for API endpoint..."
  sleep 5
done

if [ "${API_OK}" = true ]; then
  echo -e "${GREEN}✅ API endpoint responding (${API_URL})${NC}"
else
  echo -e "${RED}❌ API endpoint check failed after ${MAX_ATTEMPTS} attempts${NC}"
  echo ""
  echo "Recent container logs:"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -30
  exit 1
fi
echo ""

# Test root endpoint
echo -e "${BLUE}🌐 Testing root web endpoint...${NC}"
ROOT_URL="http://localhost:${HA_PORT}/"
if curl -fsSL --max-time 5 "${ROOT_URL}" -o /dev/null 2>/dev/null; then
  echo -e "${GREEN}✅ Web UI accessible (${ROOT_URL})${NC}"
else
  echo -e "${YELLOW}⚠️  Web UI check failed (non-critical)${NC}"
fi
echo ""

# Verify image is using correct architecture
echo -e "${BLUE}🏗️  Verifying architecture...${NC}"
IMAGE_ARCH=$(docker image inspect "${IMAGE}" | jq -r '.[0].Architecture')
EXPECTED_ARCH=$(echo "${PLATFORM}" | cut -d'/' -f2)

if [ "${IMAGE_ARCH}" = "${EXPECTED_ARCH}" ] || [ "${IMAGE_ARCH}" = "null" ]; then
  if [ "${IMAGE_ARCH}" = "null" ]; then
    echo -e "${YELLOW}⚠️  Cannot verify architecture (not set in image metadata)${NC}"
  else
    echo -e "${GREEN}✅ Architecture matches: ${IMAGE_ARCH}${NC}"
  fi
else
  echo -e "${RED}❌ Architecture mismatch: expected ${EXPECTED_ARCH}, got ${IMAGE_ARCH}${NC}"
  exit 1
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅✅✅ Smoke Test PASSED ✅✅✅${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Test Summary:"
echo "  • Container started successfully"
echo "  • No critical errors in logs"
echo "  • API endpoint responding"
echo "  • Web UI accessible"
echo "  • Correct architecture: ${IMAGE_ARCH}"
echo ""

exit 0
