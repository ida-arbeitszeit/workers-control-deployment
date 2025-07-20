# Configuration Testing Enhancement

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
