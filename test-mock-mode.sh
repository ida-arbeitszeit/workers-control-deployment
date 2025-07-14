#!/usr/bin/env bash

# Simple test script to verify mock mode works correctly

set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Set environment variables for mock mode
export SERVER_NAME="test.example.com"
export DEFAULT_EMAIL="test@example.com"
export LETSENCRYPT_EMAIL="test@example.com"

echo "=== Testing Mock Mode Environment Variable Fix ==="
echo "SERVER_NAME: $SERVER_NAME"
echo "DEFAULT_EMAIL: $DEFAULT_EMAIL"
echo "LETSENCRYPT_EMAIL: $LETSENCRYPT_EMAIL"

# Verify docker compose config is correct
echo ""
echo "=== Checking Docker Compose Configuration ==="
docker compose -f docker-deployment/docker-compose.letsencrypt.yml config | grep -E "(SERVER_NAME|VIRTUAL_HOST|LETSENCRYPT_HOST|DEFAULT_EMAIL|LETSENCRYPT_EMAIL)"

# Start deployment
echo ""
echo "=== Starting Deployment ==="
./run-deployment.sh up letsencrypt

# Wait for containers to be ready
echo ""
echo "=== Waiting for Containers ==="
sleep 30

# Check nginx configuration
echo ""
echo "=== Checking nginx-proxy Configuration ==="
docker compose -f docker-deployment/docker-compose.letsencrypt.yml exec nginx-proxy cat /etc/nginx/conf.d/default.conf | grep -A 20 -B 5 "test.example.com"

# Test HTTP connectivity
echo ""
echo "=== Testing HTTP Connectivity ==="
if curl -f -H "Host: test.example.com" http://localhost/ > /dev/null 2>&1; then
    echo "✓ HTTP connectivity successful"
else
    echo "✗ HTTP connectivity failed"
    echo "Response:"
    curl -v -H "Host: test.example.com" http://localhost/ || true
fi

# Clean up
echo ""
echo "=== Cleaning Up ==="
./run-deployment.sh down letsencrypt

echo ""
echo "=== Test Complete ==="
