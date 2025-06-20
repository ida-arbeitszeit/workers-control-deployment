#!/usr/bin/env bash
# run-deployment.sh: Helper script to manage the arbeitszeitapp deployment.

set -e

usage() {
  echo "Usage: $0 {up|down} {http|https|letsencrypt}"
  echo
  echo "Commands:"
  echo "  up      Start the services in the selected mode (in the background)."
  echo "  down    Stop and remove the services for the selected mode."
  echo
  echo "Modes:"
  echo "  http         - HTTP only (no HTTPS)"
  echo "  https        - Manual HTTPS (bring your own certs)"
  echo "  letsencrypt  - Automatic HTTPS via Let's Encrypt"
  exit 1
}

if [ $# -ne 2 ]; then
  usage
fi

COMMAND="$1"
MODE="$2"

# Change to the docker-deployment directory
cd "$(dirname "$0")/docker-deployment"

# Set compose files based on mode
case "$MODE" in
  http)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.override.yml"
    ;;
  https)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.override.yml -f docker-compose.https.yml"
    ;;
  letsencrypt)
    COMPOSE_FILES="-f docker-compose.letsencrypt.yml"
    ;;
  *)
    echo "Error: Invalid mode '$MODE'."
    usage
    ;;
esac

# Execute command
case "$COMMAND" in
  up)
    echo "[INFO] Starting arbeitszeitapp in '$MODE' mode..."
    exec docker compose $COMPOSE_FILES up -d
    ;;
  down)
    echo "[INFO] Stopping arbeitszeitapp in '$MODE' mode..."
    exec docker compose $COMPOSE_FILES down
    ;;
  *)
    echo "Error: Invalid command '$COMMAND'."
    usage
    ;;
esac
