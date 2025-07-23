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

# Load environment variables from .env file
load_env() {
  if [[ -f .env ]]; then
    # Export variables from .env file, ignoring comments and empty lines
    set -a
    source .env
    set +a
  fi
}

# Validate configuration for the selected mode
validate_config() {
  local mode="$1"
  
  case "$mode" in
    http)
      # HTTP mode - minimal validation
      if [[ -z "$SERVER_NAME" ]]; then
        echo "[ERROR] SERVER_NAME is required in .env file"
        return 1
      fi
      ;;
    https)
      # HTTPS mode - requires SERVER_NAME and certificates
      if [[ -z "$SERVER_NAME" ]]; then
        echo "[ERROR] SERVER_NAME is required in .env file for HTTPS mode"
        return 1
      fi
      
      if [[ ! -f "certs/fullchain.pem" ]] || [[ ! -f "certs/privkey.pem" ]]; then
        echo "[ERROR] HTTPS mode requires SSL certificates"
        echo "Missing files: certs/fullchain.pem and/or certs/privkey.pem"
        echo ""
        echo "For HTTPS mode, you need to provide your own SSL certificates:"
        echo "1. Place your certificate files in the certs/ directory:"
        echo "   - certs/fullchain.pem (certificate + intermediate chain)"
        echo "   - certs/privkey.pem (private key)"
        echo ""
        echo "2. Or use Let's Encrypt mode instead:"
        echo "   ./run-deployment.sh up letsencrypt"
        return 1
      fi
      ;;
    letsencrypt)
      # Let's Encrypt mode - strict validation
      local errors=0
      
      if [[ -z "$SERVER_NAME" ]]; then
        echo "[ERROR] SERVER_NAME is required in .env file for Let's Encrypt mode"
        errors=1
      elif [[ "$SERVER_NAME" == "localhost" ]] || [[ "$SERVER_NAME" == "127.0.0.1" ]] || [[ "$SERVER_NAME" =~ ^192\.168\. ]] || [[ "$SERVER_NAME" =~ ^10\. ]] || [[ "$SERVER_NAME" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        echo "[ERROR] SERVER_NAME='$SERVER_NAME' is not valid for Let's Encrypt"
        echo "Let's Encrypt requires a publicly accessible domain name."
        echo "You cannot use localhost, IP addresses, or private network addresses."
        errors=1
      elif [[ ! "$SERVER_NAME" =~ \. ]]; then
        echo "[ERROR] SERVER_NAME='$SERVER_NAME' appears to be invalid"
        echo "Let's Encrypt requires a fully qualified domain name (e.g., example.com)"
        errors=1
      fi
      
      if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
        echo "[ERROR] LETSENCRYPT_EMAIL is required in .env file for Let's Encrypt mode"
        errors=1
      elif [[ "$LETSENCRYPT_EMAIL" == "test@example.com" ]] || [[ "$LETSENCRYPT_EMAIL" == "user@example.com" ]] || [[ "$LETSENCRYPT_EMAIL" =~ @example\.(com|org)$ ]]; then
        echo "[ERROR] LETSENCRYPT_EMAIL='$LETSENCRYPT_EMAIL' appears to be a placeholder"
        echo "Let's Encrypt requires a valid email address for certificate notifications."
        errors=1
      elif [[ ! "$LETSENCRYPT_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        echo "[ERROR] LETSENCRYPT_EMAIL='$LETSENCRYPT_EMAIL' is not a valid email address"
        errors=1
      fi
      
      if [[ $errors -eq 1 ]]; then
        echo ""
        echo "To fix the Let's Encrypt configuration:"
        echo "1. Edit the .env file and set:"
        echo "   SERVER_NAME=your-domain.com        # Your actual domain"
        echo "   LETSENCRYPT_EMAIL=you@yourdomain.com  # Your real email"
        echo ""
        echo "2. Ensure your domain points to this server's public IP address"
        echo "3. Ensure ports 80 and 443 are accessible from the internet"
        echo ""
        echo "For local development, consider using 'http' mode instead:"
        echo "   ./run-deployment.sh up http"
        return 1
      fi
      ;;
  esac
  
  return 0
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
    
    # Load environment variables
    load_env
    
    # Validate configuration for the selected mode
    if ! validate_config "$MODE"; then
      exit 1
    fi
    
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
        # Check if arbeitszeitapp image exists before starting
        IMAGE_NAME="${ARBEITSZEITAPP_IMAGE:-arbeitszeitapp:latest}"
        if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
          echo "[ERROR] Docker image '$IMAGE_NAME' not found locally."
          echo ""
          echo "This deployment requires the arbeitszeitapp Docker image to be available."
          echo "You have several options to resolve this:"
          echo ""
          echo "1. BUILD locally (recommended for development):"
          echo "   ./run-deployment.sh build"
          echo ""
          echo "2. BUILD for specific architecture:"
          echo "   ./run-deployment.sh build x86_64-linux    # For Intel/AMD"
          echo "   ./run-deployment.sh build aarch64-linux   # For ARM64"
          echo ""
          echo "3. USE a pre-built image from a registry:"
          echo "   export ARBEITSZEITAPP_IMAGE=registry.example.com/arbeitszeitapp:latest"
          echo "   ./run-deployment.sh up $MODE"
          echo ""
          echo "4. BUILD multiarch image (for production):"
          echo "   ./run-deployment.sh build-multiarch"
          echo ""
          
          # Interactive prompt if terminal is available
          if [[ -t 0 ]]; then
            echo "Would you like to build the image now? [y/N]: "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
              echo "[INFO] Building Docker image for current architecture..."
              if "$0" build; then
                echo "[INFO] Build successful! Starting deployment..."
                echo ""
              else
                echo "[ERROR] Build failed. Please check the error messages above."
                exit 1
              fi
            else
              echo "[INFO] Deployment cancelled. Please build or specify an image first."
              exit 1
            fi
          else
            echo "Note: Running in non-interactive mode. Please choose one of the options above."
            exit 1
          fi
        fi
        
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
    current_arch=""
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
    target_archs=("x86_64-linux" "aarch64-linux")
    built_images=()
    
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
      manifest_images=()
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
        registry_manifest_images=()
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
