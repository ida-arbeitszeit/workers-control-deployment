#!/usr/bin/env bash
# configuration-tests.sh: Standalone configuration scenario testing
#
# Usage: ./configuration-tests.sh [--mode MODE] [--scenario SCENARIO] [--help]
#
# This script provides focused testing for specific configuration scenarios
# without running the full deployment test suite.
#
# Options:
#   --mode      Deployment mode to test (http, https) - default: http
#   --scenario  Specific scenario to test, or 'all' for all scenarios
#               Available scenarios:
#               - profiling_enabled
#               - profiling_disabled
#   --help      Show help message
#
set -euo pipefail

# Parse command line arguments
MODE="http"
SCENARIO="all"
while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--mode MODE] [--scenario SCENARIO] [--help]"
      echo
      echo "This script provides focused testing for specific configuration scenarios"
      echo "without running the full deployment test suite."
      echo
      echo "Options:"
      echo "  --mode      Deployment mode to test (http, https) - default: http"
      echo "  --scenario  Specific scenario to test, or 'all' for all scenarios"
      echo "              Available scenarios:"
      echo "              - profiling_enabled"
      echo "              - profiling_disabled"
      echo "  --help      Show this help message"
      echo
      echo "Examples:"
      echo "  $0                                                    # Test all scenarios in HTTP mode"
      echo "  $0 --mode https                                      # Test all scenarios in HTTPS mode"
      echo "  $0 --scenario profiling_enabled                     # Test specific scenario"
      echo "  $0 --mode https --scenario profiling_disabled"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate mode
if [[ "$MODE" != "http" && "$MODE" != "https" ]]; then
  echo "ERROR: Invalid mode '$MODE'. Supported modes: http, https"
  exit 1
fi

# Validate scenario
valid_scenarios=("all" "profiling_enabled" "profiling_disabled")
if [[ ! " ${valid_scenarios[*]} " =~ " ${SCENARIO} " ]]; then
  echo "ERROR: Invalid scenario '$SCENARIO'. Valid scenarios: ${valid_scenarios[*]}"
  exit 1
fi

# Get script directory
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Check if main test script exists and source its functions
if [[ ! -f "$script_dir/test-deployments.sh" ]]; then
  echo "ERROR: test-deployments.sh not found. This script requires the main test script."
  exit 1
fi

echo "Sourcing functions from test-deployments.sh..."
# Source only the functions we need, not the entire script execution
source <(grep -A 1000 "^# --- Helper Functions ---" "$script_dir/test-deployments.sh" | grep -B 1000 "^# --- Main Execution Loop ---" | head -n -1)

echo "Starting configuration testing..."
echo "Mode: $MODE"
echo "Scenario: $SCENARIO"
echo

# Run configuration tests
if [[ "$SCENARIO" == "all" ]]; then
  # Run all scenarios
  run_configuration_tests "$MODE"
else
  # Run specific scenario
  echo "=== Testing specific scenario: $SCENARIO ==="
  
  # Define compose files and URL for the mode
  base_compose_files=""
  base_url=""
  case "$MODE" in
    http)
      base_compose_files="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml"
      base_url="http://localhost"
      ;;
    https)
      # Generate self-signed certificates for HTTPS testing if they don't exist
      if [[ ! -f "$script_dir/certs/fullchain.pem" ]] || [[ ! -f "$script_dir/certs/privkey.pem" ]]; then
        echo "Generating self-signed SSL certificates for HTTPS testing..."
        if ! "$script_dir/generate-test-certs.sh"; then
          echo "ERROR: Failed to generate SSL certificates for HTTPS testing"
          exit 1
        fi
      else
        echo "Using existing SSL certificates for HTTPS testing"
      fi
      
      # Copy test certificates to docker-deployment/certs for deployment
      echo "Copying test certificates to deployment directory..."
      mkdir -p "$script_dir/../docker-deployment/certs"
      cp "$script_dir/certs/fullchain.pem" "$script_dir/../docker-deployment/certs/"
      cp "$script_dir/certs/privkey.pem" "$script_dir/../docker-deployment/certs/"
      
      base_compose_files="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml -f ../docker-deployment/docker-compose.https.yml"
      base_url="https://localhost"
      ;;
  esac
  
  # Parse scenario parameters
  profiling_enabled="false"
  
  case "$SCENARIO" in
    *profiling_enabled*) profiling_enabled="true" ;;
    *profiling_disabled*) profiling_enabled="false" ;;
  esac
  
  # Set environment variables for this scenario
  echo "Configuring environment for scenario..."
  
  # Email is always configured since it's required for core functionality
  export MAIL_SERVER="localhost"
  export MAIL_PORT="587"
  export DEFAULT_EMAIL="test@example.com"
  echo "-> Email: CONFIGURED (required for core functionality)"
  
  if [[ "$profiling_enabled" == "true" ]]; then
    export PROFILING_ENABLED=true
    export PROFILING_AUTH_ENABLED=true
    export PROFILING_USERNAME="testuser"
    export PROFILING_PASSWORD="testpassword"
    export PROFILING_ENDPOINT="profiling"
    echo "-> Profiling: ENABLED with authentication"
  else
    export PROFILING_ENABLED=false
    unset PROFILING_AUTH_ENABLED PROFILING_USERNAME PROFILING_PASSWORD PROFILING_ENDPOINT
    echo "-> Profiling: DISABLED"
  fi
  
  # Set up cleanup trap
  cleanup_single_scenario() {
    echo "Cleaning up scenario..."
    (cd "$script_dir/../.." && ./run-deployment.sh down "$MODE" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)
    
    # Clean up test certificates from docker-deployment directory
    if [[ -f "$script_dir/../docker-deployment/certs/fullchain.pem" ]] || [[ -f "$script_dir/../docker-deployment/certs/privkey.pem" ]]; then
      echo "Cleaning up test certificates from deployment directory..."
      rm -f "$script_dir/../docker-deployment/certs/fullchain.pem" "$script_dir/../docker-deployment/certs/privkey.pem"
      # Remove certs directory if it's empty
      rmdir "$script_dir/../docker-deployment/certs" 2>/dev/null || true
    fi
  }
  trap cleanup_single_scenario EXIT INT
  
  # Start deployment for this scenario
  echo "Starting deployment with configuration..."
  (cd "$script_dir/../.." && ./run-deployment.sh up "$MODE" 2>&1 | grep -E "(Created|Started|Healthy|Error|Failed)" || true)
  
  # Wait for service to be ready
  echo "Waiting for services to be ready..."
  sleep 5
  wait_for_health arbeitszeitapp "$base_compose_files" "${MODE}-config-${SCENARIO}"
  
  # Test profiling configuration
  profiling_description="${profiling_enabled} (${SCENARIO})"
  if ! test_profiling_configuration "$base_url" "$profiling_enabled" "$profiling_description"; then
    echo "ERROR: Profiling configuration test failed for scenario $SCENARIO"
    collect_failure_logs "$base_compose_files" "${MODE}-config-${SCENARIO}" "arbeitszeitapp" "profiling-config-test"
    exit 1
  fi
  
  # Test email configuration (always configured)
  echo "Testing email configuration: configured (required)"
  if ! test_email_configuration "$base_compose_files" "true" "configured (required)"; then
    echo "ERROR: Email configuration test failed for scenario $SCENARIO"
    collect_failure_logs "$base_compose_files" "${MODE}-config-${SCENARIO}" "arbeitszeitapp" "email-config-test"
    exit 1
  fi
  
  # Run basic functionality test
  echo "Running basic functionality test..."
  if ! curl -fsSLk "$base_url/" | grep -q "Arbeitszeit"; then
    echo "ERROR: Basic functionality test failed for scenario $SCENARIO"
    collect_failure_logs "$base_compose_files" "${MODE}-config-${SCENARIO}" "arbeitszeitapp" "basic-functionality-test"
    exit 1
  fi
  
  echo "✅ Configuration scenario $SCENARIO passed all tests"
fi

echo -e "\n✅ Configuration testing completed successfully."
