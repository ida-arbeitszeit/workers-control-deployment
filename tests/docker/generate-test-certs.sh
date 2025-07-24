#!/usr/bin/env bash
# generate-test-certs.sh: Generate self-signed SSL certificates for HTTPS testing
#
# This script creates self-signed SSL certificates for testing HTTPS deployments.
# These certificates are only suitable for testing and should NOT be used in production.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CERTS_DIR="$SCRIPT_DIR/certs"

echo "Generating self-signed SSL certificates for HTTPS testing..."

# Create certs directory if it doesn't exist
mkdir -p "$CERTS_DIR"

# Generate private key
echo "1. Generating private key..."
openssl genrsa -out "$CERTS_DIR/privkey.pem" 2048

# Generate certificate signing request
echo "2. Generating certificate signing request..."
openssl req -new -key "$CERTS_DIR/privkey.pem" -out "$CERTS_DIR/cert.csr" -subj "/C=US/ST=Test/L=Test/O=Test/OU=Test/CN=localhost"

# Generate self-signed certificate
echo "3. Generating self-signed certificate..."
openssl x509 -req -days 365 -in "$CERTS_DIR/cert.csr" -signkey "$CERTS_DIR/privkey.pem" -out "$CERTS_DIR/fullchain.pem"

# Clean up CSR file
rm "$CERTS_DIR/cert.csr"

# Set appropriate permissions
chmod 600 "$CERTS_DIR/privkey.pem"
chmod 644 "$CERTS_DIR/fullchain.pem"

echo "✓ Self-signed SSL certificates generated successfully!"
echo "  Certificate: $CERTS_DIR/fullchain.pem"
echo "  Private key: $CERTS_DIR/privkey.pem"
echo ""
echo "⚠️  WARNING: These are self-signed certificates for testing only."
echo "   Do NOT use these certificates in production environments."
echo ""
echo "For HTTPS testing, curl will need the -k flag to accept self-signed certificates."
