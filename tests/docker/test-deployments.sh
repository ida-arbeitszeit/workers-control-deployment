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
  echo "Mode: Multiarch Docker build enabled"
else
  echo "Mode: Single-arch Docker build (use --multiarch for multiarch)"
fi
echo

check_requirements || exit 1

# Create profiling credentials file
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROFILING_FILE="$script_dir/../../docker-deployment/profiling.json"
cat > "$PROFILING_FILE" << EOF
{
  "PROFILING_AUTH_USER": "testuser", 
  "PROFILING_AUTH_PASSWORD": "testpassword"
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
}

# Trap EXIT and INT to always clean up
trap cleanup EXIT INT

# Wait for a Docker Compose service to report as "healthy"
wait_for_health() {
  local service=$1
  local compose_files=$2
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
    status=$(docker compose $abs_compose_files ps --format json | jq -sr ".[] | select(.Service==\"$service\") | .Health" 2>/dev/null || true)
    echo "DEBUG: status=$status"
    if [[ "$status" == "healthy" ]]; then
      echo "-> '$service' is healthy."
      return 0
    elif [[ "$status" == "unhealthy" ]]; then
      echo "ERROR: '$service' is unhealthy."
      docker compose $abs_compose_files ps
      return 1
    fi
    # If status is empty, null, or none, keep waiting
    sleep 2
  done
  echo "ERROR: '$service' did not become healthy in time."
  docker compose $abs_compose_files ps
  return 1
}

# Run a suite of integration tests against a given URL
run_tests() {
  local url=$1
  local compose_files=$2
  echo "Running integration tests against $url ..."

  # Note: The -k flag is used with curl to allow self-signed or invalid certificates,
  # which is useful for testing the 'https' mode locally.

  echo "1. Checking main page content..."
  if ! curl -fsSLk "$url/" | grep -q "Arbeitszeit"; then
    echo "ERROR: 'Arbeitszeit' keyword not found on main page at $url"
    return 1
  fi
  echo "-> Main page content OK."

  echo "2. Checking login page content..."
  if ! curl -fsSLk "$url/login-member" | grep -q "Arbeitszeit"; then
    echo "ERROR: 'Arbeitszeit' keyword not found on login page at $url/login-member"
    return 1
  fi
  echo "-> Login page content OK."

  echo "3. Checking for static asset..."
  if ! curl -fsSLk "$url/static/main.js" > /dev/null; then
    echo "ERROR: Static file 'main.js' not found at $url/static/main.js"
    return 1
  fi
  echo "-> Static asset OK."

  echo "4. Running database migrations..."
  # Use -T to disable pseudo-tty allocation, which is not needed for this command.
  if ! docker compose $compose_files exec -T arbeitszeitapp alembic-command upgrade head; then
      echo "ERROR: Database migration command failed."
      return 1
  fi
  echo "-> Database migrations OK."

  echo "5. Checking profiling endpoint (unauthenticated)..."
  # We expect this to fail with a non-zero exit code because of the -f flag.
  if curl -fsSLk "$url/profiling" > /dev/null; then
    echo "ERROR: Profiling endpoint should be protected, but was publicly accessible."
    return 1
  fi
  echo "-> Profiling endpoint is protected as expected."

  echo "6. Checking profiling endpoint (authenticated)..."
  # Note: This test assumes a user 'testuser' with password 'testpassword' exists in the database.
  if ! curl -fsSLk -u 'testuser:testpassword' "$url/profiling" > /dev/null; then
    echo "ERROR: Profiling endpoint was not accessible with correct credentials."
    return 1
  fi
  echo "-> Profiling endpoint accessible with credentials."

  echo "7. Restarting application and re-testing..."
  docker compose $compose_files restart arbeitszeitapp
  wait_for_health arbeitszeitapp "$compose_files" # Re-check health after restart
  if ! curl -fsSLk "$url/" | grep -q "Arbeitszeit"; then
    echo "ERROR: Main page content check failed after restarting the application."
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

  # Wait for services to be healthy
  wait_for_health db "$COMPOSE_FILES"
  wait_for_health arbeitszeitapp "$COMPOSE_FILES"

  # Run tests
  run_tests "$url" "$COMPOSE_FILES"

  # Tear down
  echo "Tearing down '$mode' deployment..."
  (cd "$script_dir/../.." && ./run-deployment.sh down "$mode")

  echo "=== Test for '$mode' deployment complete. ==="

done

# Clean up
echo "Cleaning up temporary files..."
rm -f "$PROFILING_FILE"

echo -e "\n\n✅ All deployment scenarios tested successfully."
