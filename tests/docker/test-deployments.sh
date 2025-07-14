#!/usr/bin/env bash
# test-deployments.sh: Automated test for all deployment scenarios
#
# Usage: ./test-deployments.sh [--multiarch] [--help]
#
# Options:
#   --multiarch    Build multiarch Docker images instead of single-arch
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
while [[ $# -gt 0 ]]; do
  case $1 in
    --multiarch)
      MULTIARCH_BUILD=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--multiarch] [--help]"
      echo
      echo "Options:"
      echo "  --multiarch    Build multiarch Docker images instead of single-arch"
      echo "  --help         Show this help message"
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
  
  # Check multiarch build capability
  if [[ "$MULTIARCH_BUILD" == "true" ]]; then
    local current_system
    current_system="$(nix eval --impure --raw --expr 'builtins.currentSystem')"
    echo "Current system: $current_system"
    
    # Check if we're on a system that can do multiarch builds
    if [[ "$current_system" == *"darwin"* ]]; then
      echo "WARNING: Multiarch builds on macOS require Nix cross-compilation to be configured."
      echo "To enable cross-compilation:"
      echo "1. Add yourself to trusted users: echo 'trusted-users = root \$USER' | sudo tee -a /etc/nix/nix.conf"
      echo "2. Add Linux platforms: echo 'extra-platforms = x86_64-linux aarch64-linux' | sudo tee -a /etc/nix/nix.conf"
      echo "3. Restart Nix daemon: sudo launchctl kickstart -k system/org.nixos.nix-daemon"
      echo "Alternatively, run this test in a Linux VM for full multiarch testing."
      echo "Falling back to single-arch build for current system..."
      MULTIARCH_BUILD=false
    elif [[ "$current_system" == "aarch64-linux" ]]; then
      # Check if cross-compilation is configured
      if ! nix show-config | grep -q "extra-platforms.*x86_64-linux" 2>/dev/null; then
        echo "WARNING: Cross-compilation not configured. Cannot build x86_64-linux on aarch64-linux."
        echo "To enable cross-compilation, either:"
        echo "  1. Use --extra-platforms: ./run-deployment.sh build-multiarch --extra-platforms x86_64-linux"
        echo "  2. Or add 'extra-platforms = x86_64-linux aarch64-linux' to /etc/nix/nix.conf"
        echo "Falling back to single-arch build for current system..."
        MULTIARCH_BUILD=false
      fi
    elif [[ "$current_system" == "x86_64-linux" ]]; then
      # Check if cross-compilation is configured
      if ! nix show-config | grep -q "extra-platforms.*aarch64-linux" 2>/dev/null; then
        echo "WARNING: Cross-compilation not configured. Cannot build aarch64-linux on x86_64-linux."
        echo "To enable cross-compilation, either:"
        echo "  1. Use --extra-platforms: ./run-deployment.sh build-multiarch --extra-platforms aarch64-linux"
        echo "  2. Or add 'extra-platforms = x86_64-linux aarch64-linux' to /etc/nix/nix.conf"
        echo "Falling back to single-arch build for current system..."
        MULTIARCH_BUILD=false
      fi
    fi
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
      if ! (cd "$script_dir/../.." && ./run-deployment.sh build-multiarch); then
        echo "ERROR: multiarch build failed. Please check your Docker and Nix setup."
        return 1
      fi
    else
      echo "Building single-arch Docker image..."
      if ! (cd "$script_dir/../.." && ./run-deployment.sh build); then
        echo "ERROR: single-arch build failed."
        echo "See error messages above for troubleshooting guidance."
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

# Create profiling credentials file
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROFILING_FILE="$script_dir/../../profiling.json"
cat > "$PROFILING_FILE" << EOF
{
  "enabled": true,
  "storage": {
    "engine": "sqlite"
  },
  "basicAuth": {
    "enabled": true,
    "username": "testuser",
    "password": "testpassword"
  },
  "ignore": [
    "^/static/.*"
  ],
  "endpointRoot": "profiling"
}
EOF
echo "-> Created $PROFILING_FILE with test credentials"

# List of deployment modes to test
deployment_modes=(http https letsencrypt)

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
  # Remove profiling credentials file
  rm -f "$script_dir/../../docker-deployment/profiling.json"
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
  
  # 1. Docker Compose service status
  echo "--- Docker Compose Service Status ---" > "$log_dir/compose_status.log"
  docker compose $compose_files ps >> "$log_dir/compose_status.log" 2>&1 || true
  
  # 2. Individual container logs
  echo "Collecting container logs..."
  local services=("db" "arbeitszeitapp" "nginx" "nginx-proxy" "letsencrypt-nginx-proxy-companion")
  for service in "${services[@]}"; do
    echo "Getting logs for service: $service"
    docker compose $compose_files logs "$service" > "$log_dir/${service}_logs.log" 2>&1 || true
  done
  
  # 3. Container inspection details
  echo "--- Container Details ---" > "$log_dir/container_details.log"
  docker compose $compose_files ps --format json | jq '.' >> "$log_dir/container_details.log" 2>&1 || true
  
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
  docker compose $compose_files config | grep -A 20 "networks:" >> "$log_dir/network_info.log" 2>&1 || true
  
  # 7. Environment and configuration
  echo "--- Environment Variables ---" > "$log_dir/environment.log"
  env | grep -E "(DOCKER|COMPOSE|DATABASE|SERVER)" >> "$log_dir/environment.log" 2>&1 || true
  
  # 8. Compose configuration
  echo "--- Docker Compose Configuration ---" > "$log_dir/compose_config.log"
  docker compose $compose_files config >> "$log_dir/compose_config.log" 2>&1 || true
  
  # 9. Health check details for the failed service
  if [[ "$failed_service" != "unknown" ]]; then
    echo "--- Health Check Details for $failed_service ---" > "$log_dir/${failed_service}_health.log"
    docker compose $compose_files ps --format json | jq -r 'try (.[] | select(.Service=="'$failed_service'")) catch "No service found"' >> "$log_dir/${failed_service}_health.log" 2>&1 || true
    
    # Try to get detailed container inspect for the failed service
    local container_id
    container_id=$(docker compose $compose_files ps -q "$failed_service" 2>/dev/null || true)
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

# --- Main Execution Loop ---

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
      COMPOSE_FILES="-f ../docker-deployment/docker-compose.yml -f ../docker-deployment/docker-compose.override.yml -f ../docker-deployment/docker-compose.https.yml"
      url="https://localhost"
      ;;
    letsencrypt)
      COMPOSE_FILES="-f ../docker-deployment/docker-compose.letsencrypt.yml"
      url="https://localhost"
      ;;
  esac

  # Start deployment
  (cd "$script_dir/../.." && ./run-deployment.sh up "$mode")

  # Wait for application to be healthy (db health is already ensured by depends_on)
  wait_for_health arbeitszeitapp "$COMPOSE_FILES" "$mode"

  # Run tests
  run_tests "$url" "$COMPOSE_FILES" "$mode"

  # Tear down
  echo "Tearing down '$mode' deployment..."
  (cd "$script_dir/../.." && ./run-deployment.sh down "$mode")

  echo "=== Test for '$mode' deployment complete. ==="

done

# Clean up
echo "Cleaning up temporary files..."
rm -f "$PROFILING_FILE"

echo -e "\n\n✅ All deployment scenarios tested successfully."
