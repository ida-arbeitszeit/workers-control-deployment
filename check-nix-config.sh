#!/bin/bash

# Check Nix configuration for cross-compilation support
# This script helps diagnose macOS cross-compilation issues

echo "=== Nix Cross-Compilation Configuration Check ==="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "This script is designed for macOS. You appear to be running on: $OSTYPE"
  echo "Cross-compilation may not be needed on your platform."
  exit 0
fi

# Check if Nix is installed
if ! command -v nix &> /dev/null; then
  echo "❌ Nix is not installed or not in PATH"
  echo "Please install Nix first: https://nixos.org/download.html"
  exit 1
fi

echo "✅ Nix is installed"

# Check current configuration
echo ""
echo "=== Current Nix Configuration ==="

# Check trusted-users
echo ""
echo "Checking trusted-users configuration..."
if nix --extra-experimental-features nix-command config show | grep -q "trusted-users.*$USER"; then
  echo "✅ Current user ($USER) is in trusted-users"
else
  echo "❌ Current user ($USER) is NOT in trusted-users"
  echo "   Run: echo 'trusted-users = root \$USER' | sudo tee -a /etc/nix/nix.conf"
fi

# Check extra-platforms
echo ""
echo "Checking extra-platforms configuration..."
if nix --extra-experimental-features nix-command config show | grep -q "extra-platforms.*linux"; then
  echo "✅ Linux platforms are enabled:"
  nix --extra-experimental-features nix-command config show | grep "extra-platforms" | head -1
else
  echo "❌ Linux platforms are NOT enabled"
  echo "   Run: echo 'extra-platforms = x86_64-linux aarch64-linux' | sudo tee -a /etc/nix/nix.conf"
fi

# Check experimental features
echo ""
echo "Checking experimental features..."
if nix --extra-experimental-features nix-command config show | grep -q "experimental-features.*nix-command"; then
  echo "✅ Nix command experimental feature is enabled"
else
  echo "⚠️  Nix command experimental feature is not enabled"
  echo "   This may cause issues with flake commands"
fi

if nix --extra-experimental-features nix-command config show | grep -q "experimental-features.*flakes"; then
  echo "✅ Flakes experimental feature is enabled"
else
  echo "⚠️  Flakes experimental feature is not enabled"
  echo "   This may cause issues with flake commands"
fi

# Test cross-compilation capability
echo ""
echo "=== Testing Cross-Compilation ==="
echo ""
echo "Testing if cross-compilation to Linux is possible..."

# Simple test: try to evaluate a Linux derivation
if nix --extra-experimental-features nix-command eval --impure --expr 'builtins.currentSystem' --system aarch64-linux &>/dev/null; then
  echo "✅ Cross-compilation to aarch64-linux appears to work"
else
  echo "❌ Cross-compilation to aarch64-linux failed"
  echo "   This may indicate configuration issues"
fi

if nix --extra-experimental-features nix-command eval --impure --expr 'builtins.currentSystem' --system x86_64-linux &>/dev/null; then
  echo "✅ Cross-compilation to x86_64-linux appears to work"
else
  echo "❌ Cross-compilation to x86_64-linux failed"
  echo "   This may indicate configuration issues"
fi

# Check Docker
echo ""
echo "=== Docker Configuration ==="
if command -v docker &> /dev/null; then
  echo "✅ Docker is installed"
  if docker info &>/dev/null; then
    echo "✅ Docker daemon is running"
  else
    echo "❌ Docker daemon is not running"
    echo "   Please start Docker Desktop"
  fi
else
  echo "❌ Docker is not installed"
  echo "   Please install Docker Desktop for Mac"
fi

echo ""
echo "=== Summary ==="
echo ""
echo "IMPORTANT: Even with proper configuration, cross-compilation from macOS to Linux"
echo "may fail with 'Undefined error: 0' due to fundamental limitations in Nix's"
echo "cross-compilation support on macOS. This is a known issue that affects even"
echo "simple derivations and is not related to your specific code."
echo ""
echo "If any configuration issues were found above, follow these steps:"
echo ""
echo "1. Configure Nix for cross-compilation:"
echo "   echo 'trusted-users = root \$USER' | sudo tee -a /etc/nix/nix.conf"
echo "   echo 'extra-platforms = x86_64-linux aarch64-linux' | sudo tee -a /etc/nix/nix.conf"
echo ""
echo "2. Restart Nix daemon:"
echo "   sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist"
echo "   sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist"
echo ""
echo "3. Verify configuration:"
echo "   nix --extra-experimental-features nix-command config show | grep -E '(trusted-users|extra-platforms)'"
echo ""
echo "4. Try building the Docker image:"
echo "   ./run-deployment.sh build-docker"
echo ""
echo "For more help, see README.rst 'macOS Considerations' section."
