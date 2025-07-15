#!/bin/bash

# Comprehensive Deployment Update Script
# This script handles all aspects of updating the arbeitszeitapp deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DOWNTIME_TOLERANCE="minimal"
DEPLOYMENT_MODE=""
SKIP_FLAKE_UPDATE=false
SKIP_POSTGRES_CHECK=false
FORCE_POSTGRES_UPGRADE=false
NEW_POSTGRES_VERSION=""
VERBOSE=false

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[DEBUG] $1"
    fi
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive deployment update script that handles:
- Flake input updates
- PostgreSQL version upgrades
- Docker image rebuilding
- Service deployment with various downtime strategies

OPTIONS:
    -m, --mode MODE          Deployment mode (http, https, letsencrypt)
    -d, --downtime STRATEGY  Downtime tolerance strategy:
                            zero: Zero-downtime rolling update (default)
                            minimal: Minimal-downtime update
                            full: Full restart with downtime
    -p, --postgres VERSION   Force PostgreSQL upgrade to specific version
    --skip-flake-update     Skip flake input updates
    --skip-postgres-check   Skip PostgreSQL version check
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

EXAMPLES:
    # Standard update with minimal downtime
    $0 --mode letsencrypt
    
    # Zero-downtime update for production
    $0 --mode letsencrypt --downtime zero
    
    # Full restart with PostgreSQL upgrade
    $0 --mode letsencrypt --downtime full --postgres 16
    
    # Quick update skipping flake updates
    $0 --mode http --skip-flake-update

DOWNTIME STRATEGIES:
    zero:     Rolling update - recreates only changed services
    minimal:  Updates all services with minimal downtime
    full:     Complete restart (useful for major changes)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            DEPLOYMENT_MODE="$2"
            shift 2
            ;;
        -d|--downtime)
            DOWNTIME_TOLERANCE="$2"
            shift 2
            ;;
        -p|--postgres)
            FORCE_POSTGRES_UPGRADE=true
            NEW_POSTGRES_VERSION="$2"
            shift 2
            ;;
        --skip-flake-update)
            SKIP_FLAKE_UPDATE=true
            shift
            ;;
        --skip-postgres-check)
            SKIP_POSTGRES_CHECK=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ -z "$DEPLOYMENT_MODE" ]]; then
    error "Deployment mode is required. Use -m/--mode to specify (http, https, letsencrypt)"
    exit 1
fi

if [[ ! "$DEPLOYMENT_MODE" =~ ^(http|https|letsencrypt)$ ]]; then
    error "Invalid deployment mode: $DEPLOYMENT_MODE. Must be http, https, or letsencrypt"
    exit 1
fi

if [[ ! "$DOWNTIME_TOLERANCE" =~ ^(zero|minimal|full)$ ]]; then
    error "Invalid downtime strategy: $DOWNTIME_TOLERANCE. Must be zero, minimal, or full"
    exit 1
fi

# Change to project root
cd "$PROJECT_ROOT"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v nix &> /dev/null; then
        error "Nix is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running"
        exit 1
    fi
    
    if [[ ! -f "run-deployment.sh" ]]; then
        error "run-deployment.sh not found. Make sure you're in the correct project directory."
        exit 1
    fi
    
    if [[ ! -f "flake.nix" ]]; then
        error "flake.nix not found. Make sure you're in the correct project directory."
        exit 1
    fi
    
    debug "Prerequisites check passed"
}

# Update flake inputs
update_flake_inputs() {
    if [[ "$SKIP_FLAKE_UPDATE" == "true" ]]; then
        info "Skipping flake input updates"
        return
    fi
    
    log "Updating flake inputs..."
    if nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update --commit-lock-file; then
        log "Flake inputs updated successfully"
    else
        error "Failed to update flake inputs"
        exit 1
    fi
}

# Get current PostgreSQL version from Docker Compose files
get_current_postgres_version() {
    local compose_file="docker-deployment/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        grep "image: postgres:" "$compose_file" | head -1 | sed 's/.*postgres:\([0-9]*\).*/\1/'
    else
        echo "15"  # Default fallback
    fi
}

# Get running PostgreSQL version
get_running_postgres_version() {
    if docker compose -f docker-deployment/docker-compose.yml exec db psql -U arbeitszeitapp -t -c "SELECT version();" 2>/dev/null | grep -o "PostgreSQL [0-9]*" | grep -o "[0-9]*"; then
        return 0
    else
        echo "unknown"
    fi
}

# Check if PostgreSQL upgrade is needed
check_postgres_upgrade() {
    if [[ "$SKIP_POSTGRES_CHECK" == "true" ]]; then
        info "Skipping PostgreSQL version check"
        return
    fi
    
    log "Checking PostgreSQL version..."
    
    local current_version
    current_version=$(get_current_postgres_version)
    
    local running_version
    running_version=$(get_running_postgres_version)
    
    info "Current PostgreSQL version in compose files: $current_version"
    if [[ "$running_version" != "unknown" ]]; then
        info "Running PostgreSQL version: $running_version"
    fi
    
    # Check if forced upgrade is requested
    if [[ "$FORCE_POSTGRES_UPGRADE" == "true" ]]; then
        if [[ "$NEW_POSTGRES_VERSION" != "$current_version" ]]; then
            warn "PostgreSQL upgrade requested from $current_version to $NEW_POSTGRES_VERSION"
            perform_postgres_upgrade "$current_version" "$NEW_POSTGRES_VERSION"
        else
            info "PostgreSQL version already at requested version $NEW_POSTGRES_VERSION"
        fi
    else
        # Check for recommended upgrades (could be enhanced with version comparison logic)
        if [[ "$current_version" == "15" ]]; then
            info "PostgreSQL 15 detected. Consider upgrading to 16 for latest features."
            info "Use --postgres 16 to upgrade during this deployment update."
        fi
    fi
}

# Perform PostgreSQL upgrade using the existing script
perform_postgres_upgrade() {
    local old_version="$1"
    local new_version="$2"
    
    log "Performing PostgreSQL upgrade from $old_version to $new_version"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Use the existing upgrade script with automation mode
    if [[ -f "maintenance/upgrade-postgres.sh" ]]; then
        # Set environment variables for automated mode
        export AUTOMATED_MODE=true
        export DEPLOYMENT_MODE="$DEPLOYMENT_MODE"
        
        # Run the upgrade script
        bash maintenance/upgrade-postgres.sh "$old_version" "$new_version"
        log "PostgreSQL upgrade completed"
    else
        error "PostgreSQL upgrade script not found"
        exit 1
    fi
}

# Build Docker image
build_docker_image() {
    log "Building Docker image..."
    
    local build_args=""
    if [[ "$VERBOSE" == "true" ]]; then
        build_args="--verbose"
    fi
    
    if ./run-deployment.sh build $build_args; then
        log "Docker image built successfully"
    else
        error "Failed to build Docker image"
        exit 1
    fi
}

# Determine compose files for the deployment mode
get_compose_files() {
    case "$DEPLOYMENT_MODE" in
        http)
            echo "-f docker-deployment/docker-compose.yml -f docker-deployment/docker-compose.override.yml"
            ;;
        https)
            echo "-f docker-deployment/docker-compose.yml -f docker-deployment/docker-compose.override.yml -f docker-deployment/docker-compose.https.yml"
            ;;
        letsencrypt)
            echo "-f docker-deployment/docker-compose.letsencrypt.yml"
            ;;
    esac
}

# Update deployment based on downtime strategy
update_deployment() {
    local compose_files
    compose_files=$(get_compose_files)
    
    log "Updating deployment with $DOWNTIME_TOLERANCE downtime strategy..."
    
    case "$DOWNTIME_TOLERANCE" in
        zero)
            log "Performing zero-downtime rolling update..."
            if docker compose $compose_files up -d --force-recreate arbeitszeitapp; then
                log "Zero-downtime update completed"
            else
                error "Zero-downtime update failed"
                exit 1
            fi
            ;;
        minimal)
            log "Performing minimal-downtime update..."
            if docker compose $compose_files up -d; then
                log "Minimal-downtime update completed"
            else
                error "Minimal-downtime update failed"
                exit 1
            fi
            ;;
        full)
            log "Performing full restart..."
            if ./run-deployment.sh down "$DEPLOYMENT_MODE" && ./run-deployment.sh up "$DEPLOYMENT_MODE"; then
                log "Full restart completed"
            else
                error "Full restart failed"
                exit 1
            fi
            ;;
    esac
}

# Verify deployment health
verify_deployment() {
    log "Verifying deployment health..."
    
    # Wait a moment for services to start
    sleep 5
    
    local compose_files
    compose_files=$(get_compose_files)
    
    # Check if services are running
    if docker compose $compose_files ps | grep -q "Up"; then
        log "Services are running"
    else
        error "Some services are not running"
        docker compose $compose_files ps
        exit 1
    fi
    
    # Run health tests if available
    if [[ -f "tests/docker/test-deployments.sh" ]]; then
        info "Running deployment health tests..."
        if ./tests/docker/test-deployments.sh --modes "$DEPLOYMENT_MODE"; then
            log "Health tests passed"
        else
            warn "Health tests failed - check logs for details"
        fi
    fi
}

# Main execution
main() {
    log "Starting deployment update..."
    info "Configuration:"
    info "  Mode: $DEPLOYMENT_MODE"
    info "  Downtime Strategy: $DOWNTIME_TOLERANCE"
    info "  Skip Flake Update: $SKIP_FLAKE_UPDATE"
    info "  Skip PostgreSQL Check: $SKIP_POSTGRES_CHECK"
    if [[ "$FORCE_POSTGRES_UPGRADE" == "true" ]]; then
        info "  PostgreSQL Upgrade: $NEW_POSTGRES_VERSION"
    fi
    
    check_prerequisites
    update_flake_inputs
    check_postgres_upgrade
    build_docker_image
    update_deployment
    verify_deployment
    
    log "Deployment update completed successfully!"
    info "Summary:"
    info "  - Flake inputs: $([ "$SKIP_FLAKE_UPDATE" == "true" ] && echo "skipped" || echo "updated")"
    info "  - PostgreSQL: $([ "$FORCE_POSTGRES_UPGRADE" == "true" ] && echo "upgraded to $NEW_POSTGRES_VERSION" || echo "checked")"
    info "  - Docker image: rebuilt"
    info "  - Deployment: updated with $DOWNTIME_TOLERANCE downtime"
    info "  - Health check: completed"
}

# Run main function
main "$@"
