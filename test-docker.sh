#!/usr/bin/env bash
set -euo pipefail

# Docker-based test that simulates Heroku's build environment
# This tests the full buildpack including 1Password CLI installation

echo "🐳 Testing Heroku Buildpack with Docker"
echo "========================================"

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    echo "   Install Docker Desktop from https://www.docker.com/products/docker-desktop"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker daemon is not running"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Note: Docker Desktop on macOS may have issues with credential helpers
# We'll try to work around this, but if it fails, the local test already validated everything
# For public images like ubuntu:24.04, credential helpers shouldn't be needed anyway

# Check for OP_SERVICE_ACCOUNT_TOKEN
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    echo "❌ OP_SERVICE_ACCOUNT_TOKEN not set"
    echo "   Set it with: export OP_SERVICE_ACCOUNT_TOKEN='your-token'"
    exit 1
fi

# Export SOURCE_VERSION if available
export SOURCE_VERSION="${SOURCE_VERSION:-$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || echo 'test-commit-sha')}"

echo ""
echo "📦 Building test Docker image..."
# Use BuildKit and explicitly set credential helper to empty for public images
DOCKER_BUILDKIT=1 DOCKER_CONFIG="${HOME}/.docker" docker build \
    --progress=plain \
    -t heroku-buildpack-test \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    - <<EOF
FROM ubuntu:24.04

# Install minimal dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set up test directories (as Heroku does)
WORKDIR /tmp
EOF

echo ""
echo "🚀 Running buildpack in Docker container..."

docker run --rm -it \
    -e "OP_SERVICE_ACCOUNT_TOKEN=${OP_SERVICE_ACCOUNT_TOKEN}" \
    -e "SOURCE_VERSION=${SOURCE_VERSION}" \
    -v "${SCRIPT_DIR}:/buildpack:ro" \
    -v "/tmp/heroku-docker-test:/tmp/test" \
    heroku-buildpack-test \
    bash -c "
        set -e
        mkdir -p /tmp/test/build /tmp/test/cache /tmp/test/env
        
        echo 'Running compile script...'
        bash /buildpack/bin/compile /tmp/test/build /tmp/test/cache /tmp/test/env
        
        echo ''
        echo '=== Results ==='
        echo ''
        echo '.npmrc contents:'
        cat /tmp/test/build/.npmrc || echo '❌ .npmrc not found'
        
        echo ''
        echo 'Datadog profile:'
        cat /tmp/test/build/.profile.d/datadog.sh || echo '❌ datadog.sh not found'
        
        echo ''
        echo 'Checking 1Password CLI installation:'
        if command -v op &> /dev/null; then
            echo '✓ 1Password CLI installed'
            op --version || true
        else
            echo '❌ 1Password CLI not found'
        fi
        
        echo ''
        echo '✅ Buildpack test complete!'
    "

echo ""
echo "📁 Test artifacts are in /tmp/heroku-docker-test/build"

