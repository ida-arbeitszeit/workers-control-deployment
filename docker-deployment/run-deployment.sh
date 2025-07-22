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
  echo "                  Note: Cross-compilation may not be available on all systems."
  echo "                  Will build for current architecture if cross-compilation fails."
  echo
  echo "IMPORTANT: Building Docker images requires a Linux system."
  echo "If you're on macOS or Windows, use a Linux VM or CI/CD pipeline."
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
  echo "  $0 up letsencrypt                           # Start with Let's Encrypt"
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
    
    # Change to the docker-deployment directory (we're already here)
    cd "$(dirname "$0")"
    
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
    
    # Check if we're running on a supported OS
    if [[ "$(uname -s)" != "Linux" ]]; then
      echo "ERROR: Docker image building is only supported on Linux."
      echo "Detected OS: $(uname -s)-$(uname -m)"
      echo ""
      echo "This deployment requires Linux containers and is designed to run on Linux hosts."
      echo "To build Docker images on other operating systems, please use:"
      echo "- A Linux VM (x86_64 or aarch64)"
      echo "- GitHub Actions or other CI/CD services"
      echo "- A Linux development environment"
      exit 1
    fi
    
    # Default to current system if no architecture specified
    if [ -z "$ARCH" ]; then
      case "$(uname -m)" in
        x86_64)
          ARCH="x86_64-linux"
          ;;
        aarch64|arm64)
          ARCH="aarch64-linux"
          ;;
        *)
          echo "ERROR: Unsupported architecture: $(uname -m)"
          echo "Supported architectures: x86_64, aarch64"
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
    
    # Build the image (go to parent directory for flake.nix)
    if ! (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$ARCH"); then
      echo "ERROR: Failed to build $ARCH image"
      exit 1
    fi
    
    # Load image into Docker
    echo "[INFO] Loading Docker image..."
    docker load < ../result
    
    # Clean up build result
    rm -f ../result
    
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
    
    # Check if we're running on a supported OS
    if [[ "$(uname -s)" != "Linux" ]]; then
      echo "ERROR: Multiarch Docker image building is only supported on Linux."
      echo "Detected OS: $(uname -s)-$(uname -m)"
      echo ""
      echo "This deployment requires Linux containers and is designed to run on Linux hosts."
      echo "To build Docker images on other operating systems, please use:"
      echo "- A Linux VM (x86_64 or aarch64)"
      echo "- GitHub Actions or other CI/CD services"
      echo "- A Linux development environment"
      exit 1
    fi
    
    # Detect current architecture
    local current_arch
    case "$(uname -m)" in
      x86_64)
        current_arch="x86_64-linux"
        ;;
      aarch64|arm64)
        current_arch="aarch64-linux"
        ;;
      *)
        echo "ERROR: Unsupported architecture: $(uname -m)"
        echo "Supported architectures: x86_64, aarch64"
        exit 1
        ;;
    esac
    
    # Define target architectures
    local target_archs=("x86_64-linux" "aarch64-linux")
    local built_images=()
    
    # Build for each architecture, but handle cross-compilation gracefully
    for arch in "${target_archs[@]}"; do
      echo "[INFO] Building $arch image..."
      
      if [[ "$arch" == "$current_arch" ]]; then
        # Native build - should always work
        echo "[INFO] Native build for $arch..."
        if ! (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$arch"); then
          echo "ERROR: Failed to build native $arch image"
          exit 1
        fi
        mv ../result "../result-$arch"
        built_images+=("$arch")
      else
        # Cross-compilation attempt
        echo "[INFO] Attempting cross-compilation for $arch..."
        if (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$arch" 2>/dev/null); then
          echo "[INFO] Cross-compilation successful for $arch"
          mv ../result "../result-$arch"
          built_images+=("$arch")
        else
          echo "[WARN] Cross-compilation failed for $arch, skipping..."
          echo "[WARN] This is normal on systems without cross-compilation support."
          echo "[WARN] Continuing with available architectures..."
        fi
      fi
    done
    
    # Check if we have at least one built image
    if [[ ${#built_images[@]} -eq 0 ]]; then
      echo "ERROR: No images were built successfully"
      exit 1
    fi
    
    echo "[INFO] Successfully built images for: ${built_images[*]}"
    
    # Load images into Docker
    echo "[INFO] Loading Docker images..."
    for arch in "${built_images[@]}"; do
      docker load < "../result-$arch"
      
      # Tag with architecture-specific tags
      case "$arch" in
        x86_64-linux)
          docker tag arbeitszeitapp:latest arbeitszeitapp:latest-amd64
          ;;
        aarch64-linux)
          docker tag arbeitszeitapp:latest arbeitszeitapp:latest-arm64
          ;;
      esac
    done
    
    # Create multiarch manifest if we have multiple architectures
    if [[ ${#built_images[@]} -gt 1 ]]; then
      echo "[INFO] Creating multiarch manifest..."
      local manifest_images=()
      for arch in "${built_images[@]}"; do
        case "$arch" in
          x86_64-linux)
            manifest_images+=("arbeitszeitapp:latest-amd64")
            ;;
          aarch64-linux)
            manifest_images+=("arbeitszeitapp:latest-arm64")
            ;;
        esac
      done
      
      docker manifest create arbeitszeitapp:latest "${manifest_images[@]}"
      
      for arch in "${built_images[@]}"; do
        case "$arch" in
          x86_64-linux)
            docker manifest annotate arbeitszeitapp:latest arbeitszeitapp:latest-amd64 --arch amd64
            ;;
          aarch64-linux)
            docker manifest annotate arbeitszeitapp:latest arbeitszeitapp:latest-arm64 --arch arm64
            ;;
        esac
      done
    else
      echo "[INFO] Single architecture build - no manifest needed"
      # Just tag the single image as latest
      docker tag arbeitszeitapp:latest arbeitszeitapp:latest
    fi
    
    # Clean up build results and architecture-specific tags
    for arch in "${built_images[@]}"; do
      rm -f "../result-$arch"
      case "$arch" in
        x86_64-linux)
          docker rmi arbeitszeitapp:latest-amd64 2>/dev/null || true
          ;;
        aarch64-linux)
          docker rmi arbeitszeitapp:latest-arm64 2>/dev/null || true
          ;;
      esac
    done
    
    if [ -n "$REGISTRY" ]; then
      echo "[INFO] Pushing to registry: $REGISTRY"
      
      # Tag for registry
      docker tag arbeitszeitapp:latest "$REGISTRY"
      
      if [[ ${#built_images[@]} -gt 1 ]]; then
        # Push multiarch manifest
        local registry_manifest_images=()
        for arch in "${built_images[@]}"; do
          case "$arch" in
            x86_64-linux)
              docker tag arbeitszeitapp:latest-amd64 "$REGISTRY-amd64"
              docker push "$REGISTRY-amd64"
              registry_manifest_images+=("$REGISTRY-amd64")
              ;;
            aarch64-linux)
              docker tag arbeitszeitapp:latest-arm64 "$REGISTRY-arm64"
              docker push "$REGISTRY-arm64"
              registry_manifest_images+=("$REGISTRY-arm64")
              ;;
          esac
        done
        
        docker manifest create "$REGISTRY" "${registry_manifest_images[@]}"
        
        for arch in "${built_images[@]}"; do
          case "$arch" in
            x86_64-linux)
              docker manifest annotate "$REGISTRY" "$REGISTRY-amd64" --arch amd64
              ;;
            aarch64-linux)
              docker manifest annotate "$REGISTRY" "$REGISTRY-arm64" --arch arm64
              ;;
          esac
        done
        
        docker manifest push "$REGISTRY"
        echo "[INFO] Successfully pushed multiarch image to $REGISTRY"
      else
        # Push single architecture
        docker push "$REGISTRY"
        echo "[INFO] Successfully pushed single-arch image to $REGISTRY"
      fi
    else
      if [[ ${#built_images[@]} -gt 1 ]]; then
        echo "[INFO] Multiarch manifest created locally as arbeitszeitapp:latest"
        echo "[INFO] Built for architectures: ${built_images[*]}"
      else
        echo "[INFO] Single-arch image created locally as arbeitszeitapp:latest"
        echo "[INFO] Built for architecture: ${built_images[*]}"
      fi
      echo "[INFO] To push to a registry, run:"
      echo "  $0 build-multiarch registry/image:tag"
    fi
    ;;
  *)
    echo "Error: Invalid command '$COMMAND'."
    usage
    ;;
esac
