#!/bin/bash
# ============================================================
# Docker Host Connectivity Test (Linux)
# ============================================================
#
# Prerequisites:
#   1. Docker Engine installed and running
#      - Install: https://docs.docker.com/engine/install/
#      - Verify: docker info
#      - If permission denied: sudo usermod -aG docker $USER
#        then log out and back in
#   2. Docker Compose V2 plugin installed
#      - Install: sudo apt install docker-compose-plugin (Ubuntu/Debian)
#      - Verify: docker compose version
#   3. Python 3 installed
#      - Install: sudo apt install python3 (Ubuntu/Debian)
#              or sudo dnf install python3 (Fedora/RHEL)
#      - Verify: python3 --version
#   4. curl installed
#      - Install: sudo apt install curl
#      - Verify: curl --version
#   5. Port 8000 must be available
#      - Check: ss -tlnp | grep :8000
#   6. host.docker.internal is NOT automatic on Linux
#      - This script uses --add-host=host.docker.internal:host-gateway
#      - Requires Docker Engine 20.10+ for host-gateway support
#      - Verify: docker --version (must be >= 20.10)
#   7. Firewall may need to allow Docker subnet
#      - If tests fail, try:
#        sudo iptables -A INPUT -i docker0 -p tcp --dport 8000 -j ACCEPT
#      - Or with firewalld:
#        sudo firewall-cmd --zone=docker --add-port=8000/tcp
#   8. If using --network=host (Test 4), the HTTP server binds
#      to 0.0.0.0 or 127.0.0.1 — both are reachable in host mode
#
# Usage:
#   cd docker-host-test
#   bash test-docker-host-linux.sh
#
# ============================================================
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
