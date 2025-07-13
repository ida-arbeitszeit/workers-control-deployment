#!/usr/bin/env bash
# run-deployment.sh: Helper script to manage the arbeitszeitapp deployment.
# Development: quick local build
# ./run-deployment.sh build

# # CI: build and push specific architecture
# ./run-deployment.sh build x86_64-linux "$REGISTRY/app:$VERSION-amd64"
# ./run-deployment.sh build aarch64-linux "$REGISTRY/app:$VERSION-arm64"

# # Release: build and push multiarch
# ./run-deployment.sh build-multiarch "$REGISTRY/app:$VERSION"

set -e

usage() {
  echo "Usage: $0 {up|down|build|build-multiarch} {mode|arch|registry}"
  echo
  echo "Commands:"
  echo "  up              Start the services in the selected mode (in the background)."
  echo "  down            Stop and remove the services for the selected mode."
  echo "  build           Build single-arch Docker image and optionally push."
  echo "  build-multiarch Build and optionally push multiarch Docker image."
  echo
  echo "Modes (for up/down):"
  echo "  http         - HTTP only (no HTTPS)"
  echo "  https        - Manual HTTPS (bring your own certs)"
  echo "  letsencrypt  - Automatic HTTPS via Let's Encrypt"
  echo
  echo "Architecture (for build):"
  echo "  x86_64-linux or aarch64-linux (default: current system architecture)"
  echo "  Add optional registry/image:tag to push (e.g., 'x86_64-linux docker.io/myuser/app:latest')"
  echo
  echo "Registry (for build-multiarch):"
  echo "  Optional registry/image:tag to push to (e.g., 'docker.io/myuser/arbeitszeitapp:latest')"
  echo "  If omitted, builds locally without pushing."
  echo
  echo "Examples:"
  echo "  $0 build                                    # Build for current architecture"
  echo "  $0 build x86_64-linux                      # Build for x86_64"
  echo "  $0 build aarch64-linux docker.io/user/app:v1.0  # Build ARM64 and push"
  echo "  $0 build-multiarch                         # Build multiarch locally"
  echo "  $0 build-multiarch docker.io/user/app:v1.0 # Build multiarch and push"
  exit 1
}

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  usage
fi

COMMAND="$1"
ARG2="${2:-}"
ARG3="${3:-}"

# Execute command
case "$COMMAND" in
  up|down)
    if [ -z "$ARG2" ]; then
      echo "Error: Mode required for '$COMMAND' command."
      usage
    fi
    MODE="$ARG2"
    
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
    
    case "$COMMAND" in
      up)
        echo "[INFO] Starting arbeitszeitapp in '$MODE' mode..."
        exec docker compose $COMPOSE_FILES up -d
        ;;
      down)
        echo "[INFO] Stopping arbeitszeitapp in '$MODE' mode..."
        exec docker compose $COMPOSE_FILES down
        ;;
    esac
    ;;
  build)
    # Parse arguments for build command
    ARCH="$ARG2"
    REGISTRY="$ARG3"
    
    # Default to current system if no architecture specified
    if [ -z "$ARCH" ]; then
      case "$(uname -m)" in
        x86_64)
          ARCH="x86_64-linux"
          ;;
        arm64|aarch64)
          ARCH="aarch64-linux"
          ;;
        *)
          echo "ERROR: Could not detect architecture. Please specify x86_64-linux or aarch64-linux"
          exit 1
          ;;
      esac
    fi
    
    # Validate architecture
    case "$ARCH" in
      x86_64-linux|aarch64-linux)
        ;;
      *)
        echo "ERROR: Invalid architecture '$ARCH'. Use x86_64-linux or aarch64-linux"
        exit 1
        ;;
    esac
    
    echo "[INFO] Building Docker image for $ARCH..."
    
    # Build the image
    if ! nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$ARCH"; then
      echo "ERROR: Failed to build $ARCH image"
      exit 1
    fi
    
    # Load image into Docker
    echo "[INFO] Loading Docker image..."
    docker load < result
    
    # Clean up build result
    rm -f result
    
    if [ -n "$REGISTRY" ]; then
      echo "[INFO] Pushing to registry: $REGISTRY"
      
      # Tag for registry
      docker tag arbeitszeitapp:latest "$REGISTRY"
      
      # Push image
      docker push "$REGISTRY"
      echo "[INFO] Successfully pushed $ARCH image to $REGISTRY"
    else
      echo "[INFO] Docker image built successfully as arbeitszeitapp:latest ($ARCH)"
      echo "[INFO] To push to a registry, run:"
      echo "  $0 build $ARCH registry/image:tag"
    fi
    ;;
  build-multiarch)
    REGISTRY="$ARG2"
    
    echo "[INFO] Building multiarch Docker image..."
    
    # Build for each architecture
    echo "[INFO] Building x86_64-linux image..."
    if ! nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system x86_64-linux; then
      echo "ERROR: Failed to build x86_64-linux image"
      exit 1
    fi
    mv result result-x86_64-linux
    
    echo "[INFO] Building aarch64-linux image..."
    if ! nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system aarch64-linux; then
      echo "ERROR: Failed to build aarch64-linux image"
      exit 1
    fi
    mv result result-aarch64-linux
    
    # Load images into Docker
    echo "[INFO] Loading Docker images..."
    docker load < result-x86_64-linux
    docker load < result-aarch64-linux
    
    # Tag images with architecture-specific tags
    docker tag arbeitszeitapp:latest arbeitszeitapp:latest-amd64
    docker tag arbeitszeitapp:latest arbeitszeitapp:latest-arm64
    
    # Create multiarch manifest
    echo "[INFO] Creating multiarch manifest..."
    docker manifest create arbeitszeitapp:latest \
      arbeitszeitapp:latest-amd64 \
      arbeitszeitapp:latest-arm64
    
    docker manifest annotate arbeitszeitapp:latest arbeitszeitapp:latest-amd64 --arch amd64
    docker manifest annotate arbeitszeitapp:latest arbeitszeitapp:latest-arm64 --arch arm64
    
    # Clean up architecture-specific tags and build results
    rm -f result-x86_64-linux result-aarch64-linux
    docker rmi arbeitszeitapp:latest-amd64 arbeitszeitapp:latest-arm64 2>/dev/null || true
    
    if [ -n "$REGISTRY" ]; then
      echo "[INFO] Pushing to registry: $REGISTRY"
      
      # Tag for registry
      docker tag arbeitszeitapp:latest "$REGISTRY"
      docker manifest create "$REGISTRY" \
        arbeitszeitapp:latest-amd64 \
        arbeitszeitapp:latest-arm64
      
      docker manifest annotate "$REGISTRY" arbeitszeitapp:latest-amd64 --arch amd64
      docker manifest annotate "$REGISTRY" arbeitszeitapp:latest-arm64 --arch arm64
      
      # Push manifest
      docker manifest push "$REGISTRY"
      echo "[INFO] Successfully pushed multiarch image to $REGISTRY"
    else
      echo "[INFO] Multiarch manifest created locally as arbeitszeitapp:latest"
      echo "[INFO] To push to a registry, run:"
      echo "  $0 build-multiarch registry/image:tag"
    fi
    ;;
  *)
    echo "Error: Invalid command '$COMMAND'."
    usage
    ;;
esac
