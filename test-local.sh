#!/usr/bin/env bash
set -euo pipefail

# Test script for Heroku buildpack
# This simulates the Heroku build environment locally

echo "🧪 Testing Heroku Buildpack Locally"
echo "===================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Setup test directories
TEST_DIR="/tmp/heroku-buildpack-test"
BUILD_DIR="${TEST_DIR}/build"
CACHE_DIR="${TEST_DIR}/cache"
ENV_DIR="${TEST_DIR}/env"

echo ""
echo "📁 Setting up test directories..."
rm -rf "${TEST_DIR}"
mkdir -p "${BUILD_DIR}" "${CACHE_DIR}" "${ENV_DIR}"

# Set test environment variables
export OP_SERVICE_ACCOUNT_TOKEN="${OP_SERVICE_ACCOUNT_TOKEN:-}"
export SOURCE_VERSION="${SOURCE_VERSION:-$(git rev-parse HEAD 2>/dev/null || echo 'test-commit-sha')}"

echo ""
echo "🔑 Checking 1Password CLI access..."
if ! command -v op &> /dev/null; then
    echo -e "${YELLOW}⚠️  1Password CLI not found - will be installed by buildpack${NC}"
else
    echo -e "${GREEN}✓ 1Password CLI found${NC}"
    
    # Test token retrieval
    if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
        echo -e "${RED}✗ OP_SERVICE_ACCOUNT_TOKEN not set${NC}"
        echo "   Set it with: export OP_SERVICE_ACCOUNT_TOKEN='your-token'"
        exit 1
    fi
    
    TOKEN_LENGTH=$(op read "op://CI-CD/NPM Read Token/password" 2>/dev/null | wc -c | tr -d ' ')
    if [ "${TOKEN_LENGTH}" -gt 0 ]; then
        echo -e "${GREEN}✓ Token retrieved successfully (${TOKEN_LENGTH} chars)${NC}"
    else
        echo -e "${RED}✗ Failed to retrieve token from 1Password${NC}"
        exit 1
    fi
fi

echo ""
echo "🔨 Running compile script..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/bin/compile" "${BUILD_DIR}" "${CACHE_DIR}" "${ENV_DIR}"

echo ""
echo "🔍 Verifying outputs..."

# Check .npmrc
if [ -f "${BUILD_DIR}/.npmrc" ]; then
    echo -e "${GREEN}✓ .npmrc created${NC}"
    echo "   Content preview:"
    head -c 50 "${BUILD_DIR}/.npmrc" | sed 's/\(.\{40\}\).*/\1.../'
    echo ""
else
    echo -e "${RED}✗ .npmrc not created${NC}"
    exit 1
fi

# Check Datadog profile
if [ -f "${BUILD_DIR}/.profile.d/datadog.sh" ]; then
    echo -e "${GREEN}✓ Datadog profile script created${NC}"
    cat "${BUILD_DIR}/.profile.d/datadog.sh"
else
    echo -e "${RED}✗ Datadog profile script not created${NC}"
    exit 1
fi

echo ""
echo "📦 Testing npm authentication..."

# Create a minimal package.json that requires private package
TEST_PACKAGE_DIR="${TEST_DIR}/npm-test"
mkdir -p "${TEST_PACKAGE_DIR}"
cd "${TEST_PACKAGE_DIR}"

# Copy .npmrc from build dir
cp "${BUILD_DIR}/.npmrc" "${TEST_PACKAGE_DIR}/.npmrc"

# Create minimal package.json with a private dependency
cat > package.json <<EOF
{
  "name": "npm-auth-test",
  "version": "1.0.0",
  "dependencies": {
    "@withdouble/turbo": "^2.0.0"
  }
}
EOF

echo "   Testing npm install with private package..."
if npm install --dry-run 2>&1 | grep -q "404\|Not found\|unauthorized"; then
    echo -e "${RED}✗ npm authentication failed${NC}"
    echo "   This might be expected if the token is invalid or package doesn't exist"
    npm install --dry-run 2>&1 | head -20
    exit 1
else
    echo -e "${GREEN}✓ npm authentication successful${NC}"
fi

echo ""
echo -e "${GREEN}✅ All tests passed!${NC}"
echo ""
echo "💡 To test a full build, try:"
echo "   1. Push to a test Heroku app:"
echo "      heroku create test-app-name"
echo "      heroku buildpacks:set --index 1 https://github.com/withDouble/buildpack"
echo "      heroku config:set OP_SERVICE_ACCOUNT_TOKEN='your-token'"
echo "      git push heroku main"
echo ""
echo "   2. Or use Docker to simulate Heroku environment:"
echo "      docker run -it --rm -v \$(pwd):/app ubuntu:24.04 bash"
echo "      # Then run the compile script inside"

