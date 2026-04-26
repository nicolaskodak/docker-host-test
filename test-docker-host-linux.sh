#!/bin/bash
set -e

echo "=== Docker Host Connectivity Test (Linux) ==="
echo ""

# Step 1: Check Docker is running
if ! docker info &>/dev/null; then
  echo "❌ Docker is not running. Please start Docker first."
  echo "   Try: sudo systemctl start docker"
  exit 1
fi
echo "✅ Docker is running"

# Step 2: Make sure index.html exists
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f index.html ]; then
  echo "hello from host" > index.html
fi

# Step 3: Start HTTP server in background
echo "📡 Starting HTTP server on port 8000..."
python3 -m http.server 8000 &
SERVER_PID=$!
sleep 1

if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo "❌ Failed to start HTTP server. Port 8000 might be in use."
  exit 1
fi
echo "✅ HTTP server started (PID: $SERVER_PID)"

# Cleanup function
cleanup() {
  echo ""
  echo "🧹 Stopping HTTP server (PID: $SERVER_PID)..."
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  echo "✅ Cleanup done"
}
trap cleanup EXIT

# Step 4: Test from host first
echo ""
echo "--- Test 1: curl from host (localhost:8000) ---"
HOST_RESULT=$(curl -s http://localhost:8000/ 2>/dev/null) || true
if [ "$HOST_RESULT" = "hello from host" ]; then
  echo "✅ Host test passed: $HOST_RESULT"
else
  echo "❌ Host test failed. Got: $HOST_RESULT"
  exit 1
fi

# Step 5: Test from Docker container
# Linux 原生 Docker 需要 --add-host 才能使用 host.docker.internal
echo ""
echo "--- Test 2: curl from Docker container via host.docker.internal ---"
DOCKER_RESULT=$(docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  curlimages/curl:latest -s http://host.docker.internal:8000/ 2>/dev/null) || true
if [ "$DOCKER_RESULT" = "hello from host" ]; then
  echo "✅ Docker container → host test passed: $DOCKER_RESULT"
else
  echo "❌ Docker container → host test failed. Got: $DOCKER_RESULT"
  echo "   Tip: make sure firewall allows container subnet to reach port 8000"
  echo "   Try: sudo iptables -A INPUT -i docker0 -p tcp --dport 8000 -j ACCEPT"
fi

# Step 6: Test with Docker Compose
echo ""
echo "--- Test 3: Docker Compose test ---"
if [ -f docker-compose.yml ]; then
  COMPOSE_RESULT=$(docker compose run --rm test 2>/dev/null | tr -d '\r') || true
  if [ "$COMPOSE_RESULT" = "hello from host" ]; then
    echo "✅ Docker Compose → host test passed: $COMPOSE_RESULT"
  else
    echo "❌ Docker Compose → host test failed. Got: $COMPOSE_RESULT"
  fi
else
  echo "⚠️  docker-compose.yml not found, skipping"
fi

# Step 7: Test with host network mode (Linux alternative)
echo ""
echo "--- Test 4: curl from Docker container via host network mode ---"
HOSTNET_RESULT=$(docker run --rm \
  --network=host \
  curlimages/curl:latest -s http://localhost:8000/ 2>/dev/null) || true
if [ "$HOSTNET_RESULT" = "hello from host" ]; then
  echo "✅ Host network mode test passed: $HOSTNET_RESULT"
else
  echo "❌ Host network mode test failed. Got: $HOSTNET_RESULT"
fi

echo ""
echo "=== All tests complete ==="
