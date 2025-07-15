#!/bin/bash

# PostgreSQL Major Version Upgrade Script for Docker Deployment
# This script helps upgrade PostgreSQL from one major version to another

set -euo pipefail

# Configuration
OLD_VERSION="${1:-15}"
NEW_VERSION="${2:-16}"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Determine the correct project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if we can find the required files
if [[ ! -f "$PROJECT_ROOT/run-deployment.sh" ]]; then
    error "Cannot find run-deployment.sh. Make sure you're in the correct project structure."
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/docker-deployment/docker-compose.yml" ]]; then
    error "Cannot find docker-deployment/docker-compose.yml. Make sure you're in the correct project structure."
    exit 1
fi

# Change to project root for consistent paths
cd "$PROJECT_ROOT"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    error "Docker is not running"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Working from project root: $PROJECT_ROOT"
log "Starting PostgreSQL upgrade from version $OLD_VERSION to $NEW_VERSION"

# Step 1: Backup current database
log "Step 1: Creating database backup"
if docker compose -f docker-deployment/docker-compose.yml exec db pg_dump -U arbeitszeitapp arbeitszeitapp > "$BACKUP_DIR/backup_${TIMESTAMP}.sql"; then
    log "Database backup created: $BACKUP_DIR/backup_${TIMESTAMP}.sql"
else
    error "Failed to create database backup"
    exit 1
fi

# Step 2: Stop deployment
log "Step 2: Stopping deployment"
if ./run-deployment.sh down http 2>/dev/null || ./run-deployment.sh down https 2>/dev/null || ./run-deployment.sh down letsencrypt 2>/dev/null; then
    log "Deployment stopped"
else
    warn "Could not stop deployment (it might not be running)"
fi

# Step 3: Update Docker Compose files
log "Step 3: Updating PostgreSQL version in Docker Compose files"
for file in docker-deployment/docker-compose.yml docker-deployment/docker-compose.https.yml docker-deployment/docker-compose.letsencrypt.yml; do
    if [[ -f "$file" ]]; then
        sed -i.bak "s/postgres:${OLD_VERSION}-alpine/postgres:${NEW_VERSION}-alpine/g" "$file"
        log "Updated $file"
    fi
done

# Step 4: Remove old volume
log "Step 4: Removing old PostgreSQL volume"
warn "This will delete your current database data!"

# Check if we're running in automated mode (via update-deployment.sh)
if [[ "${AUTOMATED_MODE:-false}" == "true" ]]; then
    log "Running in automated mode - proceeding with volume removal"
else
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Upgrade cancelled"
        exit 1
    fi
fi

if docker volume rm docker-deployment_postgres-data 2>/dev/null; then
    log "Old PostgreSQL volume removed"
else
    warn "Could not remove old volume (it might not exist)"
fi

# Step 5: Start deployment
log "Step 5: Starting deployment with new PostgreSQL version"

# Check if deployment mode is provided as environment variable (for automation)
if [[ -n "${DEPLOYMENT_MODE:-}" ]]; then
    mode="$DEPLOYMENT_MODE"
    log "Using deployment mode from environment: $mode"
else
    read -p "Which deployment mode? (http/https/letsencrypt) " -r mode
fi
if ./run-deployment.sh up "$mode"; then
    log "Deployment started with PostgreSQL $NEW_VERSION"
else
    error "Failed to start deployment"
    exit 1
fi

# Step 6: Wait for database to be ready
log "Step 6: Waiting for database to be ready"
sleep 10
while ! docker compose -f docker-deployment/docker-compose.yml exec db pg_isready -U arbeitszeitapp >/dev/null 2>&1; do
    log "Waiting for database..."
    sleep 5
done

# Step 7: Restore backup
log "Step 7: Restoring database backup"
if docker compose -f docker-deployment/docker-compose.yml exec -T db psql -U arbeitszeitapp -d arbeitszeitapp < "$BACKUP_DIR/backup_${TIMESTAMP}.sql"; then
    log "Database backup restored successfully"
else
    error "Failed to restore database backup"
    exit 1
fi

# Step 8: Verify upgrade
log "Step 8: Verifying upgrade"
NEW_DB_VERSION=$(docker compose -f docker-deployment/docker-compose.yml exec db psql -U arbeitszeitapp -t -c "SELECT version();" | head -1)
log "New PostgreSQL version: $NEW_DB_VERSION"

log "PostgreSQL upgrade completed successfully!"
log "Backup available at: $BACKUP_DIR/backup_${TIMESTAMP}.sql"
log "Docker Compose file backups available with .bak extension"
