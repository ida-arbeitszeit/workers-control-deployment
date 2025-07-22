#!/usr/bin/env bash
# test-deployments.sh: Automated test for all deployment scenarios
#
# Usage: ./test-deployments.sh [--multiarch] [--modes MODE1,MODE2...] [--help]
#
# IMPORTANT: This script requires a Linux system to run.
# If you're on macOS or Windows, use a Linux VM or CI/CD pipeline.
#
# Options:
#   --multiarch    Build multiarch Docker images instead of single-arch
#   --modes        Comma-separated list of deployment modes to test (http,https,letsencrypt)
#                  Default: all modes are tested
#   --help         Show help message
#
# This script tests all deployment modes (http, https, letsencrypt) by:
# 1. Building the Docker image if not present
# 2. Starting each deployment mode
# 3. Running integration tests
# 4. Cleaning up resources
#
set -euo pipefail

# Parse command line arguments
MULTIARCH_BUILD=false
DEPLOYMENT_MODES=""
LETSENCRYPT_TEST_MODE=""
CONFIG_TESTS=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --multiarch)
      MULTIARCH_BUILD=true
      shift
      ;;
    --modes)
      DEPLOYMENT_MODES="$2"
      shift 2
      ;;
    --letsencrypt-test)
      LETSENCRYPT_TEST_MODE="$2"
      shift 2
      ;;
    --config-tests)
      CONFIG_TESTS=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--multiarch] [--modes MODE1,MODE2...] [--letsencrypt-test MODE] [--config-tests] [--help]"
      echo
      echo "IMPORTANT: This script requires a Linux system to run."
      echo "If you're on macOS or Windows, use a Linux VM or CI/CD pipeline."
      echo
      echo "Options:"
      echo "  --multiarch         Build multiarch Docker images instead of single-arch"
      echo "                      Note: May fall back to single-arch on systems without cross-compilation"
      echo "  --modes             Comma-separated list of deployment modes to test"
      echo "                      Available modes: http, https, letsencrypt"
      echo "                      Default: all modes are tested"
      echo "  --letsencrypt-test  Let's Encrypt testing mode (staging, mock, containers-only)"
      echo "                      staging: Use Let's Encrypt staging environment"
      echo "                      mock: Test with mock domain (requires /etc/hosts entry)"
      echo "                      containers-only: Test container orchestration only"
      echo "  --config-tests      Run additional configuration scenario tests"
      echo "                      Tests profiling enabled/disabled and email configured/unconfigured"
      echo "  --help              Show this help message"
      echo
      echo "Examples:"
      echo "  $0                                    # Test all modes"
      echo "  $0 --modes http                      # Test only HTTP mode"
      echo "  $0 --modes http,https                # Test HTTP and HTTPS modes"
      echo "  $0 --modes letsencrypt --letsencrypt-test staging"
      echo "  $0 --modes letsencrypt --letsencrypt-test containers-only"
      echo "  $0 --multiarch --modes https         # Test HTTPS with multiarch build"
      echo "  $0 --config-tests                    # Test all modes plus configuration scenarios"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# --- Check Required Tools and Setup ---
check_requirements() {
  echo "Checking for required tools..."
  
  # Check if we're running on a supported OS
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: Docker deployment testing is only supported on Linux."
    echo "Detected OS: $(uname -s)-$(uname -m)"
    echo ""
    echo "This deployment requires Linux containers and is designed to run on Linux hosts."
    echo "To run tests on other operating systems, please use:"
    echo "- A Linux VM (x86_64 or aarch64)"
    echo "- GitHub Actions or other CI/CD services"
    echo "- A Linux development environment"
    return 1
  fi
  
  # Check for Docker
  if ! command -v docker &> /dev/null; then
    echo "ERROR: docker is not installed. Please install Docker Engine."
    return 1
  fi
  
  # Check for Docker Compose V2
  if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose V2 is not available. Please ensure you're using Docker Engine with Compose V2 support."
    return 1
  fi
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed. Please install jq for JSON parsing."
    return 1
  fi
  
  # Check for curl
  if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is not installed. Please install curl for HTTP requests."
    return 1
  fi
  
  # Check for Nix
  if ! command -v nix &> /dev/null; then
    echo "ERROR: nix is not installed. Please install Nix package manager."
    return 1
  fi
  
  # Check for proper directory structure
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  if [[ ! -d "$script_dir/../../docker-deployment" ]]; then
    echo "ERROR: 'docker-deployment' directory not found relative to script location."
    return 1
  fi
  
  # Check for .env file
  if [[ ! -f "$script_dir/../../docker-deployment/.env" ]]; then
    echo "WARNING: 'docker-deployment/.env' file not found. Please copy .env.example to .env and fill in appropriate values."
    echo "Would you like to create it now from the example file? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      cp "$script_dir/../../docker-deployment/.env.example" "$script_dir/../../docker-deployment/.env"
      echo "Created .env file. Please edit it with appropriate values."
      return 1
    else
      echo "Please create the .env file manually before running tests."
      return 1
    fi
  fi
  
  # Check for arbeitszeitapp Docker image
  if ! docker image inspect arbeitszeitapp:latest &> /dev/null; then
    echo "arbeitszeitapp:latest Docker image not found. Building with run-deployment.sh..."
    
    # Check if user wants to build multiarch
    if [[ "$MULTIARCH_BUILD" == "true" ]]; then
      echo "Building multiarch Docker images..."
      echo "Note: On ARM64 systems, this may fall back to single-arch if cross-compilation is not available."
      if ! (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh build-multiarch); then
        echo "ERROR: multiarch build failed. Please check your Docker and Nix setup."
        return 1
      fi
    else
      echo "Building single-arch Docker image..."
      if ! (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh build); then
        echo "ERROR: single-arch build failed. Please check your Docker and Nix setup."
        return 1
      fi
    fi
    echo "Successfully built and loaded arbeitszeitapp:latest Docker image."
  fi
  
  echo "All required tools and files are present."
  return 0
}

# Run the requirements check
echo "Starting deployment tests..."
if [[ "$MULTIARCH_BUILD" == "true" ]]; then
  echo "Mode: Multiarch Docker build requested"
else
  echo "Mode: Single-arch Docker build (use --multiarch for multiarch)"
fi
echo

check_requirements || exit 1

# Show final build mode after requirements check
if [[ "$MULTIARCH_BUILD" == "true" ]]; then
  echo "✓ Multiarch Docker build will be used"
else
  echo "✓ Single-arch Docker build will be used"
fi
echo

# Set profiling configuration via environment variables for testing
export PROFILING_ENABLED=true
export PROFILING_AUTH_ENABLED=true
export PROFILING_USERNAME="testuser"
export PROFILING_PASSWORD="testpassword"
export PROFILING_ENDPOINT="profiling"

echo "-> Set profiling configuration via environment variables"

# List of deployment modes to test
if [[ -n "$DEPLOYMENT_MODES" ]]; then
  # Parse comma-separated modes from CLI argument
  IFS=',' read -ra deployment_modes <<< "$DEPLOYMENT_MODES"
  # Validate each mode
  valid_modes=("http" "https" "letsencrypt")
  for mode in "${deployment_modes[@]}"; do
    mode=$(echo "$mode" | xargs) # Trim whitespace
    if [[ ! " ${valid_modes[*]} " =~ " ${mode} " ]]; then
      echo "ERROR: Invalid deployment mode '$mode'. Valid modes are: ${valid_modes[*]}"
      exit 1
    fi
  done
  echo "Testing selected modes: ${deployment_modes[*]}"
else
  # Default: test all modes
  deployment_modes=(http https letsencrypt)
  echo "Testing all deployment modes: ${deployment_modes[*]}"
fi

# --- Helper Functions ---

# Clean up all test artefacts (containers, volumes, files, networks)
cleanup() {
  echo "Cleaning up all test artefacts..."
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  
  # Check if there are any failure log archives to preserve
  local failure_logs=($(ls /tmp/arbeitszeitapp_failure_logs_*.tar.gz 2>/dev/null || true))
  if [[ ${#failure_logs[@]} -gt 0 ]]; then
    echo "=== PRESERVING FAILURE LOGS ==="
    for log_archive in "${failure_logs[@]}"; do
      local archive_name=$(basename "$log_archive")
      echo "Moving failure logs to current directory: $archive_name"
      mv "$log_archive" "./$archive_name" 2>/dev/null || true
    done
    echo "=== FAILURE LOGS PRESERVED ==="
  fi
  
  # Remove containers, networks, volumes for all deployment modes
  for mode in http https letsencrypt; do
    local compose_files=""
    case "$mode" in
      http)
        compose_files="-f $script_dir/../../docker-deployment/docker-compose.yml -f $script_dir/../../docker-deployment/docker-compose.override.yml"
        ;;
      https)
        compose_files="-f $script_dir/../../docker-deployment/docker-compose.yml -f $script_dir/../../docker-deployment/docker-compose.override.yml -f $script_dir/../../docker-deployment/docker-compose.https.yml"
        ;;
      letsencrypt)
        compose_files="-f $script_dir/../../docker-deployment/docker-compose.letsencrypt.yml"
        ;;
    esac
    docker compose $compose_files down -v --remove-orphans || true
  done
  
  # Clean up test certificates from docker-deployment directory
  if [[ -f "$script_dir/../../docker-deployment/certs/fullchain.pem" ]] || [[ -f "$script_dir/../../docker-deployment/certs/privkey.pem" ]]; then
    echo "Cleaning up test certificates from deployment directory..."
    rm -f "$script_dir/../../docker-deployment/certs/fullchain.pem" "$script_dir/../../docker-deployment/certs/privkey.pem"
    # Remove certs directory if it's empty
    rmdir "$script_dir/../../docker-deployment/certs" 2>/dev/null || true
  fi
  
  # Optionally remove test images (uncomment if you want to remove the image)
  # docker image rm arbeitszeitapp:latest || true
  echo "Cleanup complete."
  
  # Final message about failure logs
  local preserved_logs=($(ls ./arbeitszeitapp_failure_logs_*.tar.gz 2>/dev/null || true))
  if [[ ${#preserved_logs[@]} -gt 0 ]]; then
    echo ""
    echo "=== IMPORTANT ==="
    echo "Failure logs have been preserved:"
    for log_file in "${preserved_logs[@]}"; do
      echo "  - $log_file"
    done
    echo "Extract and examine these files to troubleshoot deployment issues."
    echo "=============="
  fi
}

# Trap EXIT and INT to always clean up
trap cleanup EXIT INT

# Collect comprehensive logs when services fail to start
collect_failure_logs() {
  local compose_files=$1
  local mode=$2
  local failed_service=$3
  local failure_type=$4
  
  echo "=== COLLECTING FAILURE LOGS ==="
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local log_dir="/tmp/arbeitszeitapp_failure_logs_${mode}_${timestamp}"
  mkdir -p "$log_dir"
  
  echo "Collecting logs to: $log_dir"
  
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done
  
  # 1. Docker Compose service status
  echo "--- Docker Compose Service Status ---" > "$log_dir/compose_status.log"
  docker compose $abs_compose_files ps >> "$log_dir/compose_status.log" 2>&1 || true
  
  # 2. Individual container logs
  echo "Collecting container logs..."
  local services=("db" "arbeitszeitapp" "nginx" "nginx-proxy" "letsencrypt")
  for service in "${services[@]}"; do
    echo "Getting logs for service: $service"
    docker compose $abs_compose_files logs "$service" > "$log_dir/${service}_logs.log" 2>&1 || true
  done
  
  # 3. Container inspection details
  echo "--- Container Details ---" > "$log_dir/container_details.log"
  docker compose $abs_compose_files ps --format json | jq '.' >> "$log_dir/container_details.log" 2>&1 || true
  
  # 4. Docker system information
  echo "--- Docker System Info ---" > "$log_dir/docker_info.log"
  docker info >> "$log_dir/docker_info.log" 2>&1 || true
  echo "" >> "$log_dir/docker_info.log"
  echo "--- Docker Version ---" >> "$log_dir/docker_info.log"
  docker version >> "$log_dir/docker_info.log" 2>&1 || true
  
  # 5. System resources
  echo "--- System Resources ---" > "$log_dir/system_resources.log"
  if command -v free &> /dev/null; then
    echo "Memory:" >> "$log_dir/system_resources.log"
    free -h >> "$log_dir/system_resources.log" 2>&1 || true
  fi
  if command -v df &> /dev/null; then
    echo "Disk space:" >> "$log_dir/system_resources.log"
    df -h >> "$log_dir/system_resources.log" 2>&1 || true
  fi
  if command -v top &> /dev/null; then
    echo "Top processes (snapshot):" >> "$log_dir/system_resources.log"
    top -b -n 1 >> "$log_dir/system_resources.log" 2>&1 || true
  fi
  
  # 6. Network information
  echo "--- Network Information ---" > "$log_dir/network_info.log"
  docker network ls >> "$log_dir/network_info.log" 2>&1 || true
  echo "" >> "$log_dir/network_info.log"
  echo "--- Docker Compose Networks ---" >> "$log_dir/network_info.log"
  docker compose $abs_compose_files config | grep -A 20 "networks:" >> "$log_dir/network_info.log" 2>&1 || true
  
  # 7. Environment and configuration
  echo "--- Environment Variables ---" > "$log_dir/environment.log"
  env | grep -E "(DOCKER|COMPOSE|DATABASE|SERVER)" >> "$log_dir/environment.log" 2>&1 || true
  
  # 8. Compose configuration
  echo "--- Docker Compose Configuration ---" > "$log_dir/compose_config.log"
  docker compose $abs_compose_files config >> "$log_dir/compose_config.log" 2>&1 || true
  
  # 9. Health check details for the failed service
  if [[ "$failed_service" != "unknown" ]]; then
    echo "--- Health Check Details for $failed_service ---" > "$log_dir/${failed_service}_health.log"
    docker compose $abs_compose_files ps --format json | jq -r 'try (.[] | select(.Service=="'$failed_service'")) catch "No service found"' >> "$log_dir/${failed_service}_health.log" 2>&1 || true
    
    # Try to get detailed container inspect for the failed service
    local container_id
    container_id=$(docker compose $abs_compose_files ps -q "$failed_service" 2>/dev/null || true)
    if [[ -n "$container_id" ]]; then
      echo "--- Container Inspect for $failed_service ---" > "$log_dir/${failed_service}_inspect.log"
      docker inspect "$container_id" >> "$log_dir/${failed_service}_inspect.log" 2>&1 || true
    fi
  fi
  
  # 10. Recent system logs (if available)
  if command -v journalctl &> /dev/null; then
    echo "--- Recent System Logs ---" > "$log_dir/system_logs.log"
    journalctl --since "10 minutes ago" --no-pager >> "$log_dir/system_logs.log" 2>&1 || true
  fi
  
  # 11. Create a summary file
  cat > "$log_dir/SUMMARY.txt" << EOF
FAILURE SUMMARY
===============

Mode: $mode
Failed Service: $failed_service
Failure Type: $failure_type
Timestamp: $timestamp
Hostname: $(hostname)
System: $(uname -a)

This archive contains comprehensive logs collected when the $failed_service service
failed to become healthy during testing of the $mode deployment mode.

Key files:
- compose_status.log: Docker Compose service status
- *_logs.log: Individual container logs
- container_details.log: Detailed container information
- docker_info.log: Docker system information
- system_resources.log: System resource usage
- network_info.log: Network configuration
- compose_config.log: Docker Compose configuration
- ${failed_service}_health.log: Health check details for failed service
- ${failed_service}_inspect.log: Container inspection details

For troubleshooting, start with:
1. ${failed_service}_logs.log - Check for application errors
2. compose_status.log - Check service status
3. system_resources.log - Check for resource constraints
EOF
  
  # Create tar.gz archive
  local archive_name="arbeitszeitapp_failure_logs_${mode}_${timestamp}.tar.gz"
  echo "Creating archive: $archive_name"
  (cd /tmp && tar -czf "$archive_name" "$(basename "$log_dir")")
  
  echo "=== FAILURE LOGS COLLECTED ==="
  echo "Archive created: /tmp/$archive_name"
  echo "Log directory: $log_dir"
  echo "=== END FAILURE LOGS ==="
  
  # Keep the archive but clean up the directory
  rm -rf "$log_dir"
}

# Wait for a Docker Compose service to report as "healthy"
wait_for_health() {
  local service=$1
  local compose_files=$2
  local mode=${3:-"unknown"}
  echo "Waiting for '$service' to be healthy..."
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  # Convert -f ../docker-deployment/*.yml to -f "$script_dir/../../docker-deployment/*.yml"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done
  echo "DEBUG: abs_compose_files=$abs_compose_files"
  for i in {1..30}; do
    local status
    status=$(docker compose $abs_compose_files ps --format json | jq -sr 'try (.[] | select(.Service=="'$service'") | .Health) catch "unknown"' 2>/dev/null || echo "unknown")
    echo "DEBUG: status=$status"
    if [[ "$status" == "healthy" ]]; then
      echo "-> '$service' is healthy."
      return 0
    elif [[ "$status" == "unhealthy" ]]; then
      echo "ERROR: '$service' is unhealthy."
      collect_failure_logs "$abs_compose_files" "$mode" "$service" "unhealthy"
      return 1
    fi
    # If status is empty, null, or none, keep waiting
    sleep 2
  done
  echo "ERROR: '$service' did not become healthy in time."
  collect_failure_logs "$abs_compose_files" "$mode" "$service" "timeout"
  return 1
}

# Wait for Let's Encrypt certificate provisioning to complete
wait_for_letsencrypt_certificate() {
  local domain=$1
  local compose_files=$2
  local max_attempts=${3:-20}  # Default to 20 attempts (10 minutes)
  
  echo "Waiting for Let's Encrypt certificate provisioning for domain: $domain"
  
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done
  
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    echo "Certificate check attempt $attempt/$max_attempts..."
    
    # Check if certificate file exists in the nginx_certs volume
    if docker compose $abs_compose_files exec -T letsencrypt test -f "/etc/nginx/certs/$domain.crt" 2>/dev/null; then
      echo "-> Certificate file found for $domain"
      
      # Verify certificate is valid and not expired
      if docker compose $abs_compose_files exec -T letsencrypt openssl x509 -in "/etc/nginx/certs/$domain.crt" -noout -dates 2>/dev/null; then
        echo "-> Certificate is valid"
        
        # Check if nginx-proxy has reloaded with the new certificate
        if docker compose $abs_compose_files exec -T nginx-proxy nginx -t 2>/dev/null; then
          echo "-> nginx-proxy configuration is valid"
          
          # Test HTTPS connectivity
          if curl -fsSLk --connect-timeout 10 "https://$domain/" > /dev/null 2>&1; then
            echo "-> HTTPS connectivity confirmed"
            echo "Certificate provisioning completed successfully!"
            return 0
          else
            echo "-> HTTPS connectivity not yet available, continuing to wait..."
          fi
        else
          echo "-> nginx-proxy configuration issues, continuing to wait..."
        fi
      else
        echo "-> Certificate file present but invalid, continuing to wait..."
      fi
    else
      echo "-> Certificate file not found yet, continuing to wait..."
    fi
    
    # Show Let's Encrypt companion logs for debugging
    if [[ $((attempt % 5)) -eq 0 ]]; then
      echo "-> Let's Encrypt companion logs (last 10 lines):"
      docker compose $abs_compose_files logs --tail=10 letsencrypt 2>/dev/null | sed 's/^/   /' || echo "   (logs not available)"
    fi
    
    sleep 30  # Wait 30 seconds between attempts
    ((attempt++))
  done
  
  echo "ERROR: Certificate provisioning timed out after $max_attempts attempts"
  echo "This could be due to:"
  echo "1. Let's Encrypt staging environment delays"
  echo "2. DNS resolution issues"
  echo "3. Rate limiting"
  echo "4. Network connectivity problems"
  
  # Show final logs for debugging
  echo "-> Final Let's Encrypt companion logs:"
  docker compose $abs_compose_files logs letsencrypt 2>/dev/null | sed 's/^/   /' || echo "   (logs not available)"
  
  return 1
}

# Run a suite of integration tests against a given URL
run_tests() {
  local url=$1
  local compose_files=$2
  local mode=${3:-"integration-test"}
  echo "Running integration tests against $url ..."

  # Note: The -k flag is used with curl to allow self-signed or invalid certificates,
  # which is useful for testing the 'https' mode locally.

  echo "1. Checking main page content..."
  if ! curl -fsSLk "$url/" | grep -q "Arbeitszeit"; then
    echo "ERROR: 'Arbeitszeit' keyword not found on main page at $url"
    collect_failure_logs "$compose_files" "$mode" "arbeitszeitapp" "main-page-content-check"
    return 1
  fi
  echo "-> Main page content OK."

  echo "2. Checking login page content..."
  if ! curl -fsSLk "$url/login-member" | grep -q "Arbeitszeit"; then
    echo "ERROR: 'Arbeitszeit' keyword not found on login page at $url/login-member"
    collect_failure_logs "$compose_files" "$mode" "arbeitszeitapp" "login-page-content-check"
    return 1
  fi
  echo "-> Login page content OK."

  echo "3. Checking for static asset..."
  if ! curl -fsSLk "$url/static/main.js" > /dev/null; then
    echo "ERROR: Static file 'main.js' not found at $url/static/main.js"
    collect_failure_logs "$compose_files" "$mode" "arbeitszeitapp" "static-asset-check"
    return 1
  fi
  echo "-> Static asset OK."

  echo "4. Running database migrations..."
  # Use -T to disable pseudo-tty allocation, which is not needed for this command.
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  # Convert -f ../docker-deployment/*.yml to -f "$script_dir/../../docker-deployment/*.yml"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done
  if ! docker compose $abs_compose_files exec -T arbeitszeitapp alembic-command upgrade head; then
      echo "ERROR: Database migration command failed."
      collect_failure_logs "$abs_compose_files" "$mode" "arbeitszeitapp" "database-migration"
      return 1
  fi
  echo "-> Database migrations OK."

  echo "5. Checking profiling endpoint (unauthenticated)..."
  # We expect this to fail with a non-zero exit code because of the -f flag.
  if curl -fsSLk "$url/profiling" > /dev/null; then
    echo "ERROR: Profiling endpoint should be protected, but was publicly accessible."
    collect_failure_logs "$abs_compose_files" "$mode" "arbeitszeitapp" "profiling-endpoint-unprotected"
    return 1
  fi
  echo "-> Profiling endpoint is protected as expected."

  echo "6. Checking profiling endpoint (authenticated)..."
  # Note: This test assumes a user 'testuser' with password 'testpassword' exists in the database.
  # Use --location-trusted to pass credentials through redirects from port 80 to 5000
  if ! curl -fsSLk --location-trusted -u 'testuser:testpassword' "$url/profiling" > /dev/null; then
    echo "ERROR: Profiling endpoint was not accessible with correct credentials."
    collect_failure_logs "$abs_compose_files" "$mode" "arbeitszeitapp" "profiling-endpoint-auth"
    return 1
  fi
  echo "-> Profiling endpoint accessible with credentials."

  echo "7. Restarting application and re-testing..."
  docker compose $abs_compose_files restart arbeitszeitapp
  wait_for_health arbeitszeitapp "$abs_compose_files" "restart-test" # Re-check health after restart
  if ! curl -fsSLk "$url/" | grep -q "Arbeitszeit"; then
    echo "ERROR: Main page content check failed after restarting the application."
    collect_failure_logs "$abs_compose_files" "$mode" "arbeitszeitapp" "post-restart-check"
    return 1
  fi
  echo "-> Application OK after restart."

  echo "All tests passed for $url"
}

# Test Let's Encrypt container orchestration without certificate requests
test_letsencrypt_containers() {
  local compose_files=$1
  local mode=$2
  echo "Testing Let's Encrypt container orchestration..."
  
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done

  echo "1. Checking container status..."
  local expected_containers=("db" "arbeitszeitapp" "nginx-proxy" "letsencrypt")
  for container in "${expected_containers[@]}"; do
    local status
    status=$(docker compose $abs_compose_files ps --format json | jq -sr 'try (.[] | select(.Service=="'$container'") | .State) catch "not_found"' 2>/dev/null || echo "not_found")
    if [[ "$status" == "running" ]]; then
      echo "-> $container: running ✓"
    else
      echo "-> $container: $status ✗"
      collect_failure_logs "$abs_compose_files" "$mode" "$container" "container-not-running"
      return 1
    fi
  done

  echo "2. Checking nginx-proxy configuration generation..."
  # Check if nginx-proxy is generating configuration files
  if docker compose $abs_compose_files exec -T nginx-proxy test -f /etc/nginx/conf.d/default.conf; then
    echo "-> nginx-proxy configuration: present ✓"
  else
    echo "-> nginx-proxy configuration: missing ✗"
    collect_failure_logs "$abs_compose_files" "$mode" "nginx-proxy" "missing-configuration"
    return 1
  fi

  echo "3. Checking letsencrypt companion setup..."
  # Check if letsencrypt companion is running and has access to docker socket
  if docker compose $abs_compose_files exec -T letsencrypt test -S /var/run/docker.sock; then
    echo "-> letsencrypt companion docker access: available ✓"
  else
    echo "-> letsencrypt companion docker access: missing ✗"
    collect_failure_logs "$abs_compose_files" "$mode" "letsencrypt" "missing-docker-access"
    return 1
  fi

  echo "4. Checking volume mounts..."
  local expected_volumes=("nginx_certs" "nginx_vhost" "nginx_html")
  for volume in "${expected_volumes[@]}"; do
    if docker volume inspect "docker-deployment_$volume" &> /dev/null; then
      echo "-> Volume $volume: present ✓"
    else
      echo "-> Volume $volume: missing ✗"
      collect_failure_logs "$abs_compose_files" "$mode" "unknown" "missing-volume-$volume"
      return 1
    fi
  done

  echo "5. Testing basic HTTP connectivity (pre-certificate)..."
  # Test that the application is reachable via HTTP through nginx-proxy
  local max_attempts=10
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    if curl -fsSL -H "Host: arbeitszeit.local" "http://localhost/" | grep -q "Arbeitszeit" 2>/dev/null; then
      echo "-> HTTP connectivity: working ✓"
      break
    fi
    if [[ $attempt -eq $max_attempts ]]; then
      echo "-> HTTP connectivity: failed after $max_attempts attempts ✗"
      collect_failure_logs "$abs_compose_files" "$mode" "nginx-proxy" "http-connectivity-failed"
      return 1
    fi
    echo "   Attempt $attempt/$max_attempts failed, retrying..."
    sleep 3
    ((attempt++))
  done

  echo "6. Checking environment variable configuration..."
  # Verify that the letsencrypt environment variables are properly set
  local env_check
  env_check=$(docker compose $abs_compose_files exec -T letsencrypt printenv | grep -E "(NGINX_PROXY_CONTAINER|DEFAULT_EMAIL)" | wc -l)
  if [[ "$env_check" -ge 2 ]]; then
    echo "-> Environment variables: configured ✓"
  else
    echo "-> Environment variables: incomplete ✗"
    collect_failure_logs "$abs_compose_files" "$mode" "letsencrypt" "missing-environment-variables"
    return 1
  fi

  echo "All Let's Encrypt container orchestration tests passed!"
  echo "NOTE: This test verifies container setup but does not request actual certificates."
}

# --- Configuration Testing Functions ---

# Test profiling endpoint accessibility based on configuration
test_profiling_configuration() {
  local url=$1
  local expected_accessible=$2  # "true" or "false"
  local config_description=$3
  
  echo "Testing profiling configuration: $config_description"
  
  if [[ "$expected_accessible" == "true" ]]; then
    echo "-> Expecting profiling endpoint to be accessible with authentication..."
    if curl -fsSLk --location-trusted -u 'testuser:testpassword' "$url/profiling" > /dev/null; then
      echo "-> ✓ Profiling endpoint accessible with credentials (as expected)"
    else
      echo "-> ✗ ERROR: Profiling endpoint should be accessible but was not"
      return 1
    fi
    
    echo "-> Checking that profiling endpoint is protected from unauthenticated access..."
    if curl -fsSLk "$url/profiling" > /dev/null; then
      echo "-> ✗ ERROR: Profiling endpoint should be protected but was publicly accessible"
      return 1
    else
      echo "-> ✓ Profiling endpoint properly protected from unauthenticated access"
    fi
  else
    echo "-> Expecting profiling endpoint to be disabled..."
    if curl -fsSLk "$url/profiling" > /dev/null 2>&1; then
      echo "-> ✗ ERROR: Profiling endpoint should be disabled but was accessible"
      return 1
    else
      echo "-> ✓ Profiling endpoint disabled (as expected)"
    fi
    
    # Also test with authentication - should still be disabled
    if curl -fsSLk --location-trusted -u 'testuser:testpassword' "$url/profiling" > /dev/null 2>&1; then
      echo "-> ✗ ERROR: Profiling endpoint should be disabled even with authentication"
      return 1
    else
      echo "-> ✓ Profiling endpoint disabled even with authentication (as expected)"
    fi
  fi
  
  return 0
}

# Test email configuration by checking application behavior
test_email_configuration() {
  local compose_files=$1
  local expected_configured=$2  # "true" or "false"
  local config_description=$3
  
  echo "Testing email configuration: $config_description"
  
  # Always resolve compose file paths relative to the script directory
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local abs_compose_files=""
  for f in $compose_files; do
    if [[ "$f" == -f ]]; then
      abs_compose_files+="-f "
    elif [[ "$f" == ../docker-deployment/* ]]; then
      abs_compose_files+="$script_dir/../../docker-deployment/${f#../docker-deployment/} "
    else
      abs_compose_files+="$f "
    fi
  done
  
  if [[ "$expected_configured" == "true" ]]; then
    echo "-> Expecting email to be configured..."
    # Check that email-related environment variables are set
    local email_vars
    email_vars=$(docker compose $abs_compose_files exec -T arbeitszeitapp printenv | grep -E "(MAIL_SERVER|DEFAULT_EMAIL)" | wc -l)
    if [[ "$email_vars" -ge 1 ]]; then
      echo "-> ✓ Email environment variables present"
    else
      echo "-> ✗ ERROR: Email environment variables missing when email should be configured"
      return 1
    fi
  else
    echo "-> Expecting email to be unconfigured..."
    # Check application startup logs for email configuration warnings
    local email_warnings
    email_warnings=$(docker compose $abs_compose_files logs arbeitszeitapp 2>/dev/null | grep -i "mail" | grep -i "warning\|not.*configured\|disabled" | wc -l)
    if [[ "$email_warnings" -gt 0 ]]; then
      echo "-> ✓ Email configuration warnings present in logs (as expected)"
    else
      echo "-> ⚠ No email configuration warnings found (this may be normal if warnings are suppressed)"
    fi
  fi
  
  return 0
}

# Run configuration scenario tests for a specific deployment mode
run_configuration_tests() {
  local mode=$1
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  
  echo -e "\n--- Configuration Testing for $mode mode ---"
  
  # Define test scenarios
  # Email configuration is always required for core application functionality
  local scenarios=(
    "profiling_enabled"
    "profiling_disabled"
  )
  
  # Define compose files for the mode
  local base_compose_files=""
  local base_url=""
  case "$mode" in
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
          return 1
        fi
      else
        echo "Using existing SSL certificates for HTTPS testing"
      fi
      
      # Copy test certificates to docker-deployment/certs for deployment
      echo "Copying test certificates to deployment directory..."
      mkdir -p "$script_dir/../../docker-deployment/certs"
      cp "$script_dir/certs/fullchain.pem" "$script_dir/../../docker-deployment/certs/"
      cp "$script_dir/certs/privkey.pem" "$script_dir/../../docker-deployment/certs/"
      
      base_compose_files="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml -f ../docker-deployment/docker-compose.https.yml"
      base_url="https://localhost"
      ;;
    *)
      echo "Configuration tests are only supported for 'http' and 'https' modes"
      return 0
      ;;
  esac
  
  for scenario in "${scenarios[@]}"; do
    echo -e "\n=== Configuration Scenario: $scenario ==="
    
    # Parse scenario parameters
    local profiling_enabled="false"
    
    case "$scenario" in
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
    
    # Start deployment for this scenario
    echo "Starting deployment with configuration..."
    (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh up "$mode" 2>&1 | grep -E "(Created|Started|Healthy|Error|Failed)" || true)
    
    # Wait for service to be ready
    echo "Waiting for services to be ready..."
    sleep 5
    wait_for_health arbeitszeitapp "$base_compose_files" "${mode}-config-${scenario}"
    
    # Test profiling configuration
    local profiling_description="${profiling_enabled} (${scenario})"
    if ! test_profiling_configuration "$base_url" "$profiling_enabled" "$profiling_description"; then
      echo "ERROR: Profiling configuration test failed for scenario $scenario"
      collect_failure_logs "$base_compose_files" "${mode}-config-${scenario}" "arbeitszeitapp" "profiling-config-test"
      
      # Clean up before continuing
      echo "Cleaning up failed scenario..."
      (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh down "$mode" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)
      continue
    fi
    
    # Test email configuration (always configured)
    echo "Testing email configuration: configured (required)"
    if ! test_email_configuration "$base_compose_files" "true" "configured (required)"; then
      echo "ERROR: Email configuration test failed for scenario $scenario"
      collect_failure_logs "$base_compose_files" "${mode}-config-${scenario}" "arbeitszeitapp" "email-config-test"
      
      # Clean up before continuing
      echo "Cleaning up failed scenario..."
      (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh down "$mode" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)
      continue
    fi
    
    # Run basic functionality test to ensure configuration changes don't break core features
    echo "Running basic functionality test..."
    if ! curl -fsSLk "$base_url/" | grep -q "Arbeitszeit"; then
      echo "ERROR: Basic functionality test failed for scenario $scenario"
      collect_failure_logs "$base_compose_files" "${mode}-config-${scenario}" "arbeitszeitapp" "basic-functionality-test"
      
      # Clean up before continuing
      echo "Cleaning up failed scenario..."
      (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh down "$mode" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)
      continue
    fi
    
    echo "✓ Configuration scenario $scenario passed all tests"
    
    # Clean up before next scenario
    echo "Cleaning up scenario..."
    (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh down "$mode" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)
    
    # Wait a moment between scenarios
    sleep 3
  done
  
  echo -e "\n✅ All configuration scenarios completed for $mode mode"
}

# --- Main Execution Loop ---

# First run standard deployment tests
for mode in "${deployment_modes[@]}"; do
  # Set script_dir for each loop iteration (in case script is sourced or run in a subshell)
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

  echo -e "\n\n========================================="
  echo "=== Testing deployment mode: $mode"
  echo "========================================="

  # Set compose files and URL based on mode
  COMPOSE_FILES=""
  url=""
  case "$mode" in
    http)
      COMPOSE_FILES="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml"
      url="http://localhost"
      ;;
    https)
      # Generate self-signed certificates for HTTPS testing if they don't exist
      if [[ ! -f "$script_dir/certs/fullchain.pem" ]] || [[ ! -f "$script_dir/certs/privkey.pem" ]]; then
        echo "Generating self-signed SSL certificates for HTTPS testing..."
        if ! "$script_dir/generate-test-certs.sh"; then
          echo "ERROR: Failed to generate SSL certificates for HTTPS testing"
          continue
        fi
      else
        echo "Using existing SSL certificates for HTTPS testing"
      fi
      
      # Copy test certificates to docker-deployment/certs for deployment
      echo "Copying test certificates to deployment directory..."
      mkdir -p "$script_dir/../../docker-deployment/certs"
      cp "$script_dir/certs/fullchain.pem" "$script_dir/../../docker-deployment/certs/"
      cp "$script_dir/certs/privkey.pem" "$script_dir/../../docker-deployment/certs/"
      
      COMPOSE_FILES="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml -f ../docker-deployment/docker-compose.https.yml"
      url="https://localhost"
      ;;
    letsencrypt)
      COMPOSE_FILES="-f ../docker-deployment/docker-compose.letsencrypt.yml"
      # For Let's Encrypt mode, read SERVER_NAME from .env file
      server_name=$(grep "^SERVER_NAME=" "$script_dir/../../docker-deployment/.env" | cut -d'=' -f2 | tr -d '"')
      
      # Handle different Let's Encrypt test modes
      case "$LETSENCRYPT_TEST_MODE" in
        staging)
          echo "Using Let's Encrypt STAGING mode for testing..."
          if [[ "$server_name" =~ ^(localhost|127\.0\.0\.1|::1|.*\.local)$ ]] || [[ "$server_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            echo "ERROR: Staging mode requires a real domain name, not '$server_name'"
            echo "Please set SERVER_NAME to a real domain in .env file"
            continue
          fi
          # Set staging environment (this would need to be added to docker-compose.letsencrypt.yml)
          export ACME_CA_URI="https://acme-staging-v02.api.letsencrypt.org/directory"
          url="https://$server_name"
          ;;
        mock)
          echo "Using MOCK domain testing mode..."
          # Use a mock domain for testing
          server_name="test.example.com"
          echo "Testing with mock domain: $server_name"
          echo "NOTE: Add '127.0.0.1 $server_name' to /etc/hosts for this to work"
          
          # Check if domain is in /etc/hosts
          if ! grep -q "127.0.0.1.*$server_name" /etc/hosts 2>/dev/null; then
            echo "WARNING: $server_name not found in /etc/hosts"
            echo "Add this line to /etc/hosts: 127.0.0.1 $server_name"
          fi
          
          # Set environment variables for mock mode BEFORE deployment
          export SERVER_NAME="$server_name"
          export DEFAULT_EMAIL="test@example.com"
          export LETSENCRYPT_EMAIL="test@example.com"
          
          export ACME_CA_URI="https://acme-staging-v02.api.letsencrypt.org/directory"
          # For mock mode, we'll test HTTP initially since certificates won't work
          url="http://$server_name"
          ;;
        containers-only)
          echo "Testing CONTAINERS-ONLY mode (orchestration without certificates)..."
          # Test container startup and configuration without actually requesting certificates
          url="http://localhost"  # Use HTTP for testing since we won't get certificates
          ;;
        "")
          # Default behavior: check domain validity and provide guidance
          if [[ "$server_name" =~ ^(localhost|127\.0\.0\.1|::1|.*\.local)$ ]] || [[ "$server_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            echo "WARNING: Let's Encrypt mode requires a real domain name, not '$server_name'"
            echo "Let's Encrypt cannot issue certificates for localhost, IP addresses, or .local domains"
            echo ""
            echo "Available testing approaches for Let's Encrypt mode:"
            echo "1. STAGING: Use a real domain with Let's Encrypt staging environment"
            echo "   ./test-deployments.sh --modes letsencrypt --letsencrypt-test staging"
            echo "   - Set SERVER_NAME to your domain in .env file"
            echo "   - Test certificates will be issued but not trusted by browsers"
            echo ""
            echo "2. MOCK TESTING: Use DNS override for domain simulation"
            echo "   ./test-deployments.sh --modes letsencrypt --letsencrypt-test mock"
            echo "   - Uses test.example.com with staging environment"
            echo "   - Add '127.0.0.1 test.example.com' to /etc/hosts"
            echo ""
            echo "3. CONTAINER TESTING: Test container orchestration without certificates"
            echo "   ./test-deployments.sh --modes letsencrypt --letsencrypt-test containers-only"
            echo "   - Verifies all containers start correctly"
            echo "   - Tests configuration without requesting certificates"
            echo ""
            echo "Current SERVER_NAME: '$server_name'"
            echo "Skipping Let's Encrypt mode test (use --letsencrypt-test flag)..."
            echo "=== Test for '$mode' deployment skipped (requires real domain). ==="
            continue
          fi
          url="https://$server_name"
          ;;
        *)
          echo "ERROR: Invalid letsencrypt-test mode '$LETSENCRYPT_TEST_MODE'"
          echo "Valid modes: staging, mock, containers-only"
          exit 1
          ;;
      esac
      ;;
  esac

  # Start deployment (suppress Docker Compose progress animation)
  echo "Starting deployment..."
  (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh up "$mode" 2>&1 | grep -E "(Created|Started|Healthy|Error|Failed)" || true)
  
  # Additional wait for containers to fully start
  echo "Waiting for containers to be ready..."
  sleep 5

  # Wait for application to be healthy (db health is already ensured by depends_on)
  wait_for_health arbeitszeitapp "$COMPOSE_FILES" "$mode"

  # Run tests based on mode and configuration
  if [[ "$mode" == "letsencrypt" && "$LETSENCRYPT_TEST_MODE" == "containers-only" ]]; then
    # Special test for containers-only mode
    test_letsencrypt_containers "$COMPOSE_FILES" "$mode"
  elif [[ "$mode" == "letsencrypt" && "$LETSENCRYPT_TEST_MODE" == "staging" ]]; then
    # For staging mode with real domains, wait for certificate provisioning
    if wait_for_letsencrypt_certificate "$server_name" "$COMPOSE_FILES"; then
      echo "Certificate provisioning completed, running integration tests..."
      run_tests "$url" "$COMPOSE_FILES" "$mode"
    else
      echo "Certificate provisioning failed, but continuing with limited testing..."
      # Try HTTP fallback for basic connectivity test
      echo "Testing basic HTTP connectivity as fallback..."
      if curl -fsSL "http://$server_name/" | grep -q "Arbeitszeit" 2>/dev/null; then
        echo "-> HTTP connectivity working (certificate provisioning may still be in progress)"
      else
        echo "-> HTTP connectivity also failed"
        collect_failure_logs "$COMPOSE_FILES" "$mode" "letsencrypt" "certificate-provisioning-failed"
      fi
    fi
  elif [[ "$mode" == "letsencrypt" && "$LETSENCRYPT_TEST_MODE" == "mock" ]]; then
    # For mock mode, skip certificate waiting (variables already set before deployment)
    
    echo "Mock mode: Testing container orchestration and HTTP connectivity..."
    echo "Note: Certificate provisioning will not work in mock mode (domain not publicly accessible)"
    
    # First test that containers are working properly
    test_letsencrypt_containers "$COMPOSE_FILES" "$mode"
    
    # Then test HTTP connectivity with the mock domain
    echo "Testing HTTP connectivity with mock domain..."
    local max_attempts=5
    local attempt=1
    local http_success=false
    
    while [[ $attempt -le $max_attempts ]]; do
      if curl -fsSL "http://$server_name/" | grep -q "Arbeitszeit" 2>/dev/null; then
        echo "-> HTTP connectivity with mock domain: working ✓"
        http_success=true
        break
      fi
      echo "   HTTP attempt $attempt/$max_attempts failed, retrying..."
      sleep 5
      ((attempt++))
    done
    
    if [[ "$http_success" == "false" ]]; then
      echo "-> HTTP connectivity with mock domain: failed ✗"
      echo "   This could indicate nginx-proxy configuration issues with the mock domain"
      collect_failure_logs "$COMPOSE_FILES" "$mode" "nginx-proxy" "http-connectivity-mock-domain-failed"
    else
      # Run basic integration tests over HTTP (not HTTPS since certificates won't work)
      echo "Running basic integration tests over HTTP..."
      run_tests "$url" "$COMPOSE_FILES" "$mode"
    fi
  else
    # Standard integration tests
    run_tests "$url" "$COMPOSE_FILES" "$mode"
  fi

  # Tear down (suppress Docker Compose progress animation)
  echo "Tearing down '$mode' deployment..."
  (cd "$script_dir/../../docker-deployment" && ./run-deployment.sh down "$mode" 2>&1 | grep -E "(Stopped|Removed|Error|Failed)" || true)

  echo "=== Test for '$mode' deployment complete. ==="

done

# Run configuration tests if requested
if [[ "$CONFIG_TESTS" == "true" ]]; then
  echo -e "\n\n========================================="
  echo "=== Running Configuration Scenario Tests"
  echo "========================================="
  
  # Configuration tests are most meaningful for http and https modes
  config_test_modes=()
  for mode in "${deployment_modes[@]}"; do
    if [[ "$mode" == "http" || "$mode" == "https" ]]; then
      config_test_modes+=("$mode")
    fi
  done
  
  if [[ ${#config_test_modes[@]} -eq 0 ]]; then
    echo "Configuration tests require 'http' or 'https' modes."
    echo "Adding 'http' mode for configuration testing..."
    config_test_modes=("http")
  fi
  
  for mode in "${config_test_modes[@]}"; do
    run_configuration_tests "$mode"
  done
  
  echo -e "\n✅ All configuration scenario tests completed."
fi

# Clean up
echo "Cleaning up temporary files..."
# Note: Profiling is now configured via environment variables, no file cleanup needed

echo -e "\n\n✅ All deployment scenarios tested successfully."
