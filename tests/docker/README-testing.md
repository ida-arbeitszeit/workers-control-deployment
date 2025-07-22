# Testing the Docker Deployment

The deploym2. Generate self-signed certificates for HTTPS testing:

```bash
# Option 1: Use the provided script (recommended)
./tests/docker/generate-test-certs.sh

# Option 2: Manual generation
mkdir -p docker-deployment/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 
  -keyout docker-deployment/certs/privkey.pem 
  -out docker-deployment/certs/fullchain.pem 
  -subj "/C=US/ST=Test/L=Test/O=Test/OU=Test/CN=localhost" 
  -addext "subjectAltName=DNS:localhost"
```omprehensive automated testing to validate all deployment scenarios.

## Prerequisites

To run the automated tests for Docker deployment scenarios, you need:

### Required Software

* Docker Engine with Compose V2 support
* jq command-line tool for parsing JSON
* curl command-line tool for HTTP requests
* Bash shell (pre-installed on macOS and Linux)
* OpenSSL (for generating self-signed certificates)
* Nix package manager (for building the Docker image)

### Installation on macOS

```bash
brew install docker jq curl openssl nix
```

### Installation on Linux (Debian/Ubuntu)

```bash
apt-get update && apt-get install -y docker.io jq curl openssl
# Install Nix (see https://nixos.org/download.html)
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

### Setup and Configuration

1. Create and configure environment file:

```bash
# Copy the example environment file
cd docker-deployment
cp .env.example .env

# Edit the file with your preferred settings
nano .env
```

2. Generate self-signed certificates for HTTPS testing:

```bash
# Create certificates directory if it doesn't exist
mkdir -p certs

# Generate self-signed certificate valid for 1 year
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/privkey.pem \
  -out certs/fullchain.pem \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost"
```

3. Build and load the Docker image:

```bash
# From the project root directory
# For single-arch build (matches current Linux system architecture)
./docker-deployment/run-deployment.sh build

# For multiarch build (attempts both x86_64 and ARM64, falls back to native architecture if cross-compilation unavailable)
./docker-deployment/run-deployment.sh build-multiarch

# For specific architecture
./docker-deployment/run-deployment.sh build x86_64-linux
./docker-deployment/run-deployment.sh build aarch64-linux
```

**Note on Multiarch Builds:** The multiarch build process is designed to be resilient to cross-compilation limitations. On systems without full cross-compilation support, it will automatically fall back to building for the native architecture only, ensuring the build process always succeeds.

### SSL Certificate Generation for HTTPS Testing

The testing suite includes a script to automatically generate self-signed SSL certificates for HTTPS testing:

**`generate-test-certs.sh`** - Generates self-signed SSL certificates
- Creates `tests/docker/certs/fullchain.pem` (certificate)  
- Creates `tests/docker/certs/privkey.pem` (private key)
- Automatically called by test scripts when HTTPS testing is required
- **For testing purposes only** - do not use in production

The test scripts automatically:
- Generate certificates in `tests/docker/certs/` if they don't exist
- Copy certificates to `docker-deployment/certs/` for deployment
- Clean up copied certificates after testing

To manually generate test certificates:
```bash
cd tests/docker
./generate-test-certs.sh
```

**⚠️ Security Note**: These are self-signed certificates for testing only. Browsers will show security warnings when accessing HTTPS endpoints with these certificates, but the test scripts use `curl -k` to bypass certificate validation.

## Running the Tests

Execute the test script from the project root directory:

```bash
# Make the script executable if needed
chmod +x tests/docker/test-deployments.sh

# Run all tests with single-arch build (default)
./tests/docker/test-deployments.sh

# Run all tests with multiarch build
./tests/docker/test-deployments.sh --multiarch

# Test specific deployment modes
./tests/docker/test-deployments.sh --modes http
./tests/docker/test-deployments.sh --modes https,letsencrypt

# Let's Encrypt testing options
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test staging
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test mock
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test containers-only

# Show help and available options
./tests/docker/test-deployments.sh --help
```

### Test Script Options

* `--multiarch` - Build multiarch Docker images instead of single-arch (falls back to native architecture if cross-compilation unavailable)
* `--modes MODE1,MODE2` - Test specific deployment modes (http, https, letsencrypt)
* `--letsencrypt-test MODE` - Configure Let's Encrypt testing approach:
  
  - `staging` - Use Let's Encrypt staging environment with real domains
  - `mock` - Test with mock domains and /etc/hosts configuration
  - `containers-only` - Test container orchestration without certificate requests

* `--help` - Show usage information and available options

### Test Coverage

The test suite validates:

* **Container Health**: All services start correctly and pass health checks
* **Database Connectivity**: Database migrations and connection functionality
* **HTTP/HTTPS Endpoints**: Application accessibility and SSL configuration
* **Static File Serving**: CSS, JavaScript, and other static assets
* **Flask-Profiler Integration**: Performance monitoring endpoints (when enabled)
* **Let's Encrypt Integration**: Certificate provisioning and renewal (staging/mock modes)
* **Service Restart Resilience**: Application recovery after container restarts

### Automated Build Process

The test script will automatically:

* Check for all required tools and configuration
* Build the Docker image if not already present
* Use single-arch build by default for faster testing
* Support multiarch builds with graceful fallback to native architecture on systems without cross-compilation support
* Support both supported Linux architectures (x86_64 and aarch64)
* Clean up resources after testing is complete

### Failure Diagnostics

When tests fail, the script automatically:

* Collects comprehensive logs from all containers
* Captures Docker system information and resource usage
* Generates detailed failure reports in timestamped archives
* Preserves logs for troubleshooting: `arbeitszeitapp_failure_logs_*.tar.gz`

## Let's Encrypt Testing Modes

The test script supports multiple approaches for testing Let's Encrypt functionality:

### Staging Mode

Uses Let's Encrypt staging environment with real domains (requires valid DNS). This mode requires:

- A real domain name configured in your `.env` file
- DNS A/AAAA records pointing to your server
- Internet connectivity for Let's Encrypt validation

```bash
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test staging
```

### Mock Mode

Tests with mock domains using `/etc/hosts` configuration (safe for development). This mode allows testing Let's Encrypt container orchestration without requiring real domains or internet connectivity.

#### Prerequisites for Mock Mode

Before running mock mode tests, you need to add entries to your `/etc/hosts` file to simulate domain resolution:

```bash
# Add these entries to /etc/hosts (requires sudo)
sudo bash -c 'echo "127.0.0.1 letsencrypt-test.example.com" >> /etc/hosts'
sudo bash -c 'echo "::1 letsencrypt-test.example.com" >> /etc/hosts'
```

**Alternative method using a text editor:**

```bash
# Edit /etc/hosts with your preferred editor
sudo nano /etc/hosts

# Add these lines to the file:
127.0.0.1 letsencrypt-test.example.com
::1 letsencrypt-test.example.com
```

#### Verification

After adding the entries, verify they work correctly:

```bash
# Test domain resolution
ping -c 1 letsencrypt-test.example.com
nslookup letsencrypt-test.example.com

# Should resolve to 127.0.0.1 (localhost)
```

#### Running Mock Mode Tests

```bash
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test mock
```

#### What Mock Mode Tests

- Container orchestration with nginx-proxy and letsencrypt-nginx-proxy-companion
- Service discovery and routing configuration
- Environment variable configuration for Let's Encrypt
- Application accessibility through the nginx proxy
- Certificate request processes (will fail gracefully as expected)

#### Important Notes

- Mock mode will attempt certificate provisioning but certificates will fail to generate (this is expected behavior)
- The test validates that the application remains accessible despite certificate failures
- Certificate provisioning errors are expected and do not indicate test failure
- The test focuses on container orchestration and service configuration rather than actual SSL certificates

#### Cleanup

After testing, you may want to remove the mock entries from `/etc/hosts`:

```bash
# Remove the mock domain entries
sudo sed -i '' '/letsencrypt-test.example.com/d' /etc/hosts

# Or manually edit the file to remove the lines
sudo nano /etc/hosts
```

### Containers-Only Mode

Validates container orchestration without certificate requests. This mode tests the deployment configuration without attempting any certificate provisioning:

```bash
./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test containers-only
```

This comprehensive testing ensures deployment reliability across all supported scenarios.

## Configuration Testing Enhancement

This document describes the enhanced configuration testing capabilities added to the deployment test suite.

## Overview

The deployment tests now include comprehensive configuration scenario testing to validate that profiling and email features work correctly in various enabled/disabled states.

## Enhanced Features

### Main Test Script (`test-deployments.sh`)

The main test script now supports a new `--config-tests` flag that runs additional configuration scenarios:

```bash
# Run all standard tests plus configuration scenarios
./test-deployments.sh --config-tests

# Run configuration tests for specific deployment modes
./test-deployments.sh --modes http,https --config-tests
```

### Standalone Configuration Testing (`configuration-tests.sh`)

A dedicated script for focused configuration testing without running the full deployment suite:

```bash
# Test all configuration scenarios in HTTP mode
./configuration-tests.sh

# Test all scenarios in HTTPS mode
./configuration-tests.sh --mode https

# Test a specific configuration scenario
./configuration-tests.sh --scenario profiling_disabled_email_unconfigured
```

## Configuration Scenarios Tested

The enhanced testing covers these scenarios:

| Scenario | Profiling | Email | Description |
|----------|-----------|-------|-------------|
| `profiling_enabled_email_configured` | ✅ Enabled | ✅ Configured | Full feature set |
| `profiling_disabled_email_configured` | ❌ Disabled | ✅ Configured | Email only |
| `profiling_enabled_email_unconfigured` | ✅ Enabled | ❌ Unconfigured | Profiling only |
| `profiling_disabled_email_unconfigured` | ❌ Disabled | ❌ Unconfigured | Minimal config |

## Test Coverage

### Profiling Configuration Tests

- **Enabled**: Verifies profiling endpoint is accessible with authentication and protected without authentication
- **Disabled**: Verifies profiling endpoint returns 404/not found, even with valid credentials

### Email Configuration Tests

- **Configured**: Checks that email environment variables are present
- **Unconfigured**: Looks for appropriate warning messages in application logs

### Basic Functionality Tests

All configuration scenarios include basic functionality validation to ensure configuration changes don't break core application features.

## Integration with Existing Tests

The configuration tests integrate seamlessly with the existing test framework:

- Uses the same Docker Compose orchestration
- Leverages existing health check and failure log collection mechanisms
- Maintains backward compatibility with existing test workflows
- Supports both HTTP and HTTPS deployment modes

## Usage Examples

### Development Workflow
```bash
# Quick configuration validation during development
./configuration-tests.sh --scenario profiling_enabled_email_configured

# Full regression testing including configuration scenarios
./test-deployments.sh --modes http --config-tests
```

### CI/CD Integration
```bash
# Comprehensive testing in CI environment
./test-deployments.sh --config-tests

# Configuration-specific testing stage
./configuration-tests.sh --mode http
./configuration-tests.sh --mode https
```

## Benefits

1. **Comprehensive Coverage**: Tests all meaningful combinations of profiling and email configuration states
2. **Early Detection**: Catches configuration-related issues before production deployment
3. **Documentation**: Serves as living documentation of supported configuration scenarios
4. **Flexible Testing**: Allows targeted testing of specific scenarios without full test suite overhead
5. **CI/CD Ready**: Integrates cleanly with existing deployment testing workflows

## Implementation Details

The configuration testing uses environment variables to simulate different configuration states:

- **Profiling**: `PROFILING_ENABLED`, `PROFILING_AUTH_ENABLED`, `PROFILING_USERNAME`, `PROFILING_PASSWORD`, `PROFILING_ENDPOINT`
- **Email**: `MAIL_SERVER`, `MAIL_PORT`, `DEFAULT_EMAIL`

Each scenario deploys a fresh instance with the appropriate environment configuration, runs validation tests, and cleans up before proceeding to the next scenario.
