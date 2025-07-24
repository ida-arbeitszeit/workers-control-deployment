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
  echo "Usage: $0 {up|down|build|build-multiarch|tag-latest|push-multiarch} [options] {mode|arch|registry}"
  echo
  echo "Commands:"
  echo "  up              Start the services in the selected mode (in the background)."
  echo "  down            Stop and remove the services for the selected mode."
  echo "  build           Build single-arch Docker image and optionally push."
  echo "  build-multiarch Build multiarch Docker images locally (keeps arch-specific tags)."
  echo "                  Note: Cross-compilation may not be available on all systems."
  echo "                  Will build for current architecture if cross-compilation fails."
  echo "  tag-latest      Tag a specific architecture as 'latest' for deployment."
  echo "  push-multiarch  Create multiarch manifest and push to registry."
  echo
  echo "Options:"
  echo "  --force         Force rebuild by removing existing images and clearing caches"
  echo "  --rebuild       Alias for --force (for up command only)"
  echo "  --tag-latest    Also tag the built images for deployment (build-multiarch only)"
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
  echo "Architecture (for tag-latest):"
  echo "  x86_64 or aarch64 - which architecture to tag as 'latest'"
  echo
  echo "Registry (for build-multiarch and push-multiarch):"
  echo "  Optional registry/image:tag to push to (e.g., 'docker.io/myuser/arbeitszeitapp:latest')"
  echo "  If omitted, builds locally without pushing."
  echo
  echo "Examples:"
  echo "  $0 up letsencrypt                           # Start with Let's Encrypt"
  echo "  $0 up http --rebuild                        # Force rebuild then start"
  echo "  $0 build                                    # Build for current architecture"
  echo "  $0 build --force                            # Force rebuild (remove existing image)"
  echo "  $0 build x86_64-linux                      # Build for x86_64"
  echo "  $0 build --force x86_64-linux              # Force rebuild for x86_64"
  echo "  $0 build aarch64-linux docker.io/user/app:v1.0  # Build ARM64 and push"
  echo "  $0 build-multiarch                         # Build multiarch locally (no latest tag)"
  echo "  $0 build-multiarch --tag-latest            # Build multiarch and tag native arch as latest"
  echo "  $0 build-multiarch --force                 # Force multiarch rebuild"
  echo "  $0 tag-latest aarch64                      # Tag ARM64 version as latest for deployment"
  echo "  $0 tag-latest x86_64                       # Tag x86_64 version as latest for deployment"
  echo "  $0 push-multiarch docker.io/user/app:v1.0  # Create manifest and push to registry"
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

# Check if required tools are installed for build operations
check_build_dependencies() {
  local missing_tools=()

  # Check for Nix
  if ! command -v nix >/dev/null 2>&1; then
    missing_tools+=("nix")
  fi

  # Check for Docker
  if ! command -v docker >/dev/null 2>&1; then
    missing_tools+=("docker")
  fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo "[ERROR] Missing required tools for building Docker images:"
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    echo ""
    echo "To build Docker images, you need:"
    echo ""
    echo "1. NIX PACKAGE MANAGER:"
    echo "   - Install: curl -L https://nixos.org/nix/install | sh"
    echo "   - Or use NixOS: https://nixos.org/download.html"
    echo "   - Restart shell after installation"
    echo ""
    echo "2. DOCKER:"
    echo "   - Install Docker Engine: https://docs.docker.com/engine/install/"
    echo "   - Ensure Docker daemon is running"
    echo "   - Add user to docker group: sudo usermod -aG docker \$USER"
    echo ""
    echo "3. ALTERNATIVE: Use pre-built images from a registry:"
    echo "   export ARBEITSZEITAPP_IMAGE=registry.example.com/arbeitszeitapp:latest"
    echo "   ./run-deployment.sh up [mode]"
    echo ""
    echo "4. ALTERNATIVE: Use CI/CD pipeline for building:"
    echo "   - GitHub Actions can build images with all dependencies pre-installed"
    echo "   - Push built images to a container registry"
    echo ""
    return 1
  fi

  return 0
}

# Update Nix flake lock file to prevent narHash mismatches
update_flake_lock() {
  echo "[INFO] Updating Nix flake lock file..."

  # Change to parent directory where flake.nix is located
  if ! (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update); then
    echo "[WARN] Failed to update flake lock file"
    echo "[WARN] This may cause build issues if source code has changed"
    echo "[WARN] You can manually run: nix flake update"
    echo ""
    # Don't fail here, as the build might still work
  else
    echo "[INFO] Flake lock file updated successfully"
  fi
}

# Force rebuild cleanup: remove existing images and clear build caches
force_rebuild_cleanup() {
  local image_name="${ARBEITSZEITAPP_IMAGE:-arbeitszeitapp:latest}"

  echo "[INFO] Force rebuild requested - cleaning up existing artifacts..."

  # Remove existing Docker image
  if docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "[INFO] Removing existing Docker image: $image_name"
    docker rmi "$image_name" 2>/dev/null || true
  fi

  # Remove architecture-specific images that might exist from multiarch builds
  for tag in latest-amd64 latest-arm64; do
    if docker image inspect "arbeitszeitapp:$tag" >/dev/null 2>&1; then
      echo "[INFO] Removing existing Docker image: arbeitszeitapp:$tag"
      docker rmi "arbeitszeitapp:$tag" 2>/dev/null || true
    fi
  done

  # Clear Nix build results
  echo "[INFO] Clearing Nix build cache..."
  rm -f ../result ../result-* 2>/dev/null || true

  # Run nix-collect-garbage to clean up build dependencies (optional, but helps with space)
  if command -v nix-collect-garbage >/dev/null 2>&1; then
    echo "[INFO] Running garbage collection to free up space..."
    nix-collect-garbage 2>/dev/null || true
  fi

  echo "[INFO] Force rebuild cleanup complete"
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

if [ $# -lt 1 ] || [ $# -gt 4 ]; then
  usage
fi

COMMAND="$1"
FORCE_REBUILD=false
TAG_LATEST=false
ARG2=""
ARG3=""

# Parse arguments and flags
shift
while [[ $# -gt 0 ]]; do
  case $1 in
  --force | --rebuild)
    FORCE_REBUILD=true
    shift
    ;;
  --tag-latest)
    TAG_LATEST=true
    shift
    ;;
  *)
    if [[ -z "$ARG2" ]]; then
      ARG2="$1"
    elif [[ -z "$ARG3" ]]; then
      ARG3="$1"
    else
      echo "Error: Too many arguments."
      usage
    fi
    shift
    ;;
  esac
done

# Execute command
case "$COMMAND" in
up | down)
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
    # Handle force rebuild flag
    if [[ "$FORCE_REBUILD" == "true" ]]; then
      echo "[INFO] Force rebuild requested for up command..."
      force_rebuild_cleanup
      echo "[INFO] Building Docker image for current architecture..."
      if ! "$0" build; then
        echo "[ERROR] Force rebuild failed. Please check the error messages above."
        exit 1
      fi
      echo "[INFO] Force rebuild successful! Starting deployment..."
      echo ""
    fi

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
    exec docker compose "$COMPOSE_FILES" up -d
    ;;
  down)
    echo "[INFO] Stopping arbeitszeitapp in '$MODE' mode..."
    exec docker compose "$COMPOSE_FILES" down
    ;;
  esac
  ;;
build)
  # Parse arguments for build command
  ARCH="$ARG2"
  REGISTRY="$ARG3"

  # Check if required build tools are available
  if ! check_build_dependencies; then
    exit 1
  fi

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
    aarch64 | arm64)
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
  x86_64-linux | aarch64-linux) ;;
  *)
    echo "ERROR: Invalid architecture '$ARCH'. Use x86_64-linux or aarch64-linux"
    exit 1
    ;;
  esac

  # Check for cross-compilation restrictions
  current_system_arch=""
  case "$(uname -m)" in
  x86_64)
    current_system_arch="x86_64-linux"
    ;;
  aarch64 | arm64)
    current_system_arch="aarch64-linux"
    ;;
  esac

  if [[ "$ARCH" != "$current_system_arch" ]]; then
    echo "[WARN] Cross-compilation attempt detected:"
    echo "  Current system: $current_system_arch"
    echo "  Target architecture: $ARCH"
    echo ""

    # Check if user is trusted for cross-compilation
    if nix show-config 2>/dev/null | grep -q "trusted-users.*$(whoami)" || [[ "$(whoami)" == "root" ]]; then
      echo "[INFO] User is trusted for cross-compilation, attempting build..."
    else
      echo "[ERROR] Cross-compilation failed: Nix user '$(whoami)' is not trusted"
      echo ""
      echo "This happens when Nix is configured with restricted users for security."
      echo "Cross-compilation requires either:"
      echo ""
      echo "1. TRUSTED USER: Add your user to nix.settings.trusted-users"
      echo "   - Edit /etc/nix/nix.conf and add: trusted-users = root $(whoami)"
      echo "   - Restart the nix-daemon: sudo systemctl restart nix-daemon"
      echo ""
      echo "2. NATIVE BUILD: Build on the target architecture"
      echo "   - For x86_64: Use an Intel/AMD Linux system"
      echo "   - For aarch64: Use an ARM64 Linux system"
      echo ""
      echo "3. CI/CD PIPELINE: Use GitHub Actions or similar service"
      echo "   - Multi-arch builds work well in containerized CI environments"
      echo ""
      echo "4. BUILD FOR CURRENT ARCH: Build for your current system instead"
      echo "   ./run-deployment.sh build $current_system_arch"
      echo ""
      echo "For local development, building for your current architecture is usually sufficient."
      exit 1
    fi
  fi

  echo "[INFO] Building Docker image for $ARCH..."

  # Handle force rebuild flag
  if [[ "$FORCE_REBUILD" == "true" ]]; then
    force_rebuild_cleanup
  fi

  # Update flake lock file to prevent narHash mismatches
  update_flake_lock

  # Build the image (go to parent directory for flake.nix)
  echo "[INFO] Starting Nix build process..."
  if [[ "$ARCH" != "$current_system_arch" ]]; then
    echo "[INFO] Cross-compilation detected - this may take 10-30 minutes..."
  else
    echo "[INFO] Native build - this may take 5-15 minutes..."
  fi
  echo "[INFO] You can monitor detailed progress in another terminal with:"
  echo "         tail -f ~/.cache/nix/log/* 2>/dev/null || echo 'No detailed logs available'"
  echo ""

  if ! (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$ARCH" --print-build-logs 2>&1 | while IFS= read -r line; do
    case "$line" in
    *"building "* | *"copying "* | *"fetching "* | *"downloading "* | *"warning: "* | *"error: "*)
      echo "[$ARCH] $line"
      ;;
    *"store paths deleted"* | *"store paths downloaded"* | *"built"*)
      echo "[$ARCH] $line"
      ;;
    *)
      # Show occasional progress dots for long builds
      if [[ $((RANDOM % 80)) -eq 0 ]]; then
        echo -n "."
      fi
      ;;
    esac
  done) then
    echo ""
    echo "ERROR: Failed to build $ARCH image"
    exit 1
  fi
  echo ""

  # Load image into Docker
  echo "[INFO] Loading Docker image..."
  docker load <../result

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
  # build-multiarch no longer accepts registry argument - use push-multiarch instead
  if [ -n "$ARG2" ]; then
    echo "Error: build-multiarch no longer accepts registry arguments."
    echo "To build and push multiarch images:"
    echo "  $0 build-multiarch [--tag-latest]"
    echo "  $0 push-multiarch registry/image:tag"
    exit 1
  fi

  echo "[INFO] Building multiarch Docker image..."

  # Check if required build tools are available
  if ! check_build_dependencies; then
    exit 1
  fi

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
  aarch64 | arm64)
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

  # Handle force rebuild flag
  if [[ "$FORCE_REBUILD" == "true" ]]; then
    force_rebuild_cleanup
  fi

  # Update flake lock file to prevent narHash mismatches
  update_flake_lock

  # Build for each architecture, but handle cross-compilation gracefully
  for arch in "${target_archs[@]}"; do
    echo "[INFO] Building $arch image..."

    if [[ "$arch" == "$current_arch" ]]; then
      # Native build - should always work
      echo "[INFO] Native build for $arch..."
      echo "[INFO] Building application image (this may take 5-15 minutes)..."
      if ! (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$arch" --print-build-logs 2>&1 | while IFS= read -r line; do
        case "$line" in
        *"building "* | *"copying "* | *"fetching "* | *"downloading "* | *"warning: "* | *"error: "*)
          echo "[$arch] $line"
          ;;
        *"store paths deleted"* | *"store paths downloaded"* | *"built"*)
          echo "[$arch] $line"
          ;;
        *)
          # Show occasional progress dots
          if [[ $((RANDOM % 100)) -eq 0 ]]; then
            echo -n "."
          fi
          ;;
        esac
      done) then
        echo ""
        echo "ERROR: Failed to build native $arch image"
        exit 1
      fi
      echo ""
      mv ../result "../result-$arch"
      built_images+=("$arch")
    else
      # Cross-compilation attempt
      echo "[INFO] Attempting cross-compilation for $arch..."
      echo "[INFO] This may take 10-30 minutes for the first build as it needs to compile all dependencies..."
      echo "[INFO] Progress indicators:"
      echo "         - Building dependencies and fetching sources"
      echo "         - Compiling application components"
      echo "         - Creating Docker image layers"
      echo "[INFO] You can monitor detailed progress in another terminal with:"
      echo "         tail -f ~/.cache/nix/log/* 2>/dev/null || echo 'No detailed logs available'"
      echo ""

      # Use a more verbose build with progress indication
      if (cd .. && nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#dockerImage --system "$arch" --print-build-logs --verbose 2>&1 | while IFS= read -r line; do
        # Filter and show relevant progress information
        case "$line" in
        *"building "* | *"copying "* | *"fetching "* | *"downloading "* | *"warning: "* | *"error: "*)
          echo "[$arch] $line"
          ;;
        *"store paths deleted"* | *"store paths downloaded"* | *"built"*)
          echo "[$arch] $line"
          ;;
        *)
          # For very long builds, show a progress dot every few seconds
          if [[ $((RANDOM % 50)) -eq 0 ]]; then
            echo -n "."
          fi
          ;;
        esac
      done) then
        echo ""
        echo "[INFO] Cross-compilation successful for $arch"
        mv ../result "../result-$arch"
        built_images+=("$arch")
      else
        echo ""
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
    docker load <"../result-$arch"

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

  # Don't automatically tag latest for multiarch builds - let user decide
  if [[ "$TAG_LATEST" == "true" ]]; then
    echo "[INFO] --tag-latest requested, tagging for deployment..."

    # Prefer current architecture for local 'latest' tag
    current_arch_built=false
    for built_arch in "${built_images[@]}"; do
      if [[ "$built_arch" == "$current_arch" ]]; then
        current_arch_built=true
        break
      fi
    done

    if [[ "$current_arch_built" == "true" ]]; then
      echo "[INFO] Using native architecture ($current_arch) as 'latest'"
      case "$current_arch" in
      x86_64-linux)
        docker tag arbeitszeitapp:latest-amd64 arbeitszeitapp:latest
        ;;
      aarch64-linux)
        docker tag arbeitszeitapp:latest-arm64 arbeitszeitapp:latest
        ;;
      esac
    else
      echo "[INFO] Using first built architecture (${built_images[0]}) as 'latest'"
      case "${built_images[0]}" in
      x86_64-linux)
        docker tag arbeitszeitapp:latest-amd64 arbeitszeitapp:latest
        ;;
      aarch64-linux)
        docker tag arbeitszeitapp:latest-arm64 arbeitszeitapp:latest
        ;;
      esac
    fi
  else
    echo "[INFO] Architecture-specific images available for later tagging:"
    echo "  Use: $0 tag-latest {aarch64|x86_64} to tag for deployment"
  fi

  # Clean up build results but keep architecture tags for verification
  for arch in "${built_images[@]}"; do
    rm -f "../result-$arch"
  done

  # Show what was built for verification
  echo "[INFO] Verifying built images:"
  for arch in "${built_images[@]}"; do
    case "$arch" in
    x86_64-linux)
      if docker image inspect arbeitszeitapp:latest-amd64 >/dev/null 2>&1; then
        img_id=$(docker image inspect arbeitszeitapp:latest-amd64 --format '{{.Id}}' | cut -d: -f2 | cut -c1-12)
        img_size=$(docker image inspect arbeitszeitapp:latest-amd64 --format '{{.Size}}' | numfmt --to=iec --suffix=B)
        echo "  ✓ x86_64: arbeitszeitapp:latest-amd64 ($img_id, $img_size)"
      fi
      ;;
    aarch64-linux)
      if docker image inspect arbeitszeitapp:latest-arm64 >/dev/null 2>&1; then
        img_id=$(docker image inspect arbeitszeitapp:latest-arm64 --format '{{.Id}}' | cut -d: -f2 | cut -c1-12)
        img_size=$(docker image inspect arbeitszeitapp:latest-arm64 --format '{{.Size}}' | numfmt --to=iec --suffix=B)
        echo "  ✓ aarch64: arbeitszeitapp:latest-arm64 ($img_id, $img_size)"
      fi
      ;;
    esac
  done

  # Show the final latest image
  if docker image inspect arbeitszeitapp:latest >/dev/null 2>&1; then
    img_arch=$(docker image inspect arbeitszeitapp:latest --format '{{.Architecture}}')
    img_id=$(docker image inspect arbeitszeitapp:latest --format '{{.Id}}' | cut -d: -f2 | cut -c1-12)
    img_size=$(docker image inspect arbeitszeitapp:latest --format '{{.Size}}' | numfmt --to=iec --suffix=B)
    echo "  → latest: arbeitszeitapp:latest ($img_arch, $img_id, $img_size)"
  fi
  echo ""

  # Clean up architecture-specific tags after verification (optional)
  # Uncomment the next lines if you want to remove arch-specific tags
  # for arch in "${built_images[@]}"; do
  #   case "$arch" in
  #   x86_64-linux)
  #     docker rmi arbeitszeitapp:latest-amd64 2>/dev/null || true
  #     ;;
  #   aarch64-linux)
  #     docker rmi arbeitszeitapp:latest-arm64 2>/dev/null || true
  #     ;;
  #   esac
  # done

  if [[ ${#built_images[@]} -gt 1 ]]; then
    echo "[INFO] Multiarch build completed successfully"
    echo "[INFO] Built for architectures: ${built_images[*]}"
    echo "[INFO] Architecture-specific images preserved for later use"
  else
    echo "[INFO] Single-arch image created successfully"
    echo "[INFO] Built for architecture: ${built_images[*]}"
  fi

  if [[ "$TAG_LATEST" == "true" ]]; then
    echo "[INFO] Tagged for deployment - you can now run: $0 up {mode}"
  else
    echo "[INFO] To tag for deployment, run: $0 tag-latest {aarch64|x86_64}"
  fi
  ;;
tag-latest)
  ARCH="$ARG2"

  if [ -z "$ARCH" ]; then
    echo "Error: Architecture required for tag-latest command."
    echo "Usage: $0 tag-latest {aarch64|x86_64}"
    exit 1
  fi

  # Validate and normalize architecture
  case "$ARCH" in
  aarch64 | arm64)
    DOCKER_TAG="arbeitszeitapp:latest-arm64"
    ARCH_NAME="aarch64"
    ;;
  x86_64 | amd64)
    DOCKER_TAG="arbeitszeitapp:latest-amd64"
    ARCH_NAME="x86_64"
    ;;
  *)
    echo "Error: Invalid architecture '$ARCH'. Use 'aarch64' or 'x86_64'"
    exit 1
    ;;
  esac

  # Check if the architecture-specific image exists
  if ! docker image inspect "$DOCKER_TAG" >/dev/null 2>&1; then
    echo "[ERROR] Docker image '$DOCKER_TAG' not found locally."
    echo ""
    echo "Available arbeitszeitapp images:"
    docker image ls --filter reference=arbeitszeitapp --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"
    echo ""
    echo "To build multiarch images, run:"
    echo "  $0 build-multiarch"
    exit 1
  fi

  echo "[INFO] Tagging $ARCH_NAME architecture as 'latest' for deployment..."
  docker tag "$DOCKER_TAG" arbeitszeitapp:latest

  echo "[INFO] Successfully tagged arbeitszeitapp:latest with $ARCH_NAME architecture"
  echo "[INFO] You can now use: $0 up {http|https|letsencrypt}"
  ;;
push-multiarch)
  REGISTRY="$ARG2"

  if [ -z "$REGISTRY" ]; then
    echo "Error: Registry required for push-multiarch command."
    echo "Usage: $0 push-multiarch registry/image:tag"
    exit 1
  fi

  echo "[INFO] Creating multiarch manifest and pushing to registry: $REGISTRY"

  # Check what architecture images are available
  available_images=()
  if docker image inspect arbeitszeitapp:latest-amd64 >/dev/null 2>&1; then
    available_images+=("x86_64-linux")
  fi
  if docker image inspect arbeitszeitapp:latest-arm64 >/dev/null 2>&1; then
    available_images+=("aarch64-linux")
  fi

  if [[ ${#available_images[@]} -eq 0 ]]; then
    echo "[ERROR] No architecture-specific images found."
    echo ""
    echo "Available arbeitszeitapp images:"
    docker image ls --filter reference=arbeitszeitapp --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"
    echo ""
    echo "To build multiarch images, run:"
    echo "  $0 build-multiarch"
    exit 1
  fi

  echo "[INFO] Found images for architectures: ${available_images[*]}"

  if [[ ${#available_images[@]} -gt 1 ]]; then
    # Push multiarch manifest to registry
    echo "[INFO] Creating multiarch manifest for registry..."
    registry_manifest_images=()
    for arch in "${available_images[@]}"; do
      case "$arch" in
      x86_64-linux)
        docker tag arbeitszeitapp:latest-amd64 "$REGISTRY-amd64"
        echo "[INFO] Pushing $REGISTRY-amd64..."
        docker push "$REGISTRY-amd64"
        registry_manifest_images+=("$REGISTRY-amd64")
        ;;
      aarch64-linux)
        docker tag arbeitszeitapp:latest-arm64 "$REGISTRY-arm64"
        echo "[INFO] Pushing $REGISTRY-arm64..."
        docker push "$REGISTRY-arm64"
        registry_manifest_images+=("$REGISTRY-arm64")
        ;;
      esac
    done

    echo "[INFO] Creating registry manifest..."
    docker manifest create "$REGISTRY" "${registry_manifest_images[@]}"

    for arch in "${available_images[@]}"; do
      case "$arch" in
      x86_64-linux)
        docker manifest annotate "$REGISTRY" "$REGISTRY-amd64" --arch amd64
        ;;
      aarch64-linux)
        docker manifest annotate "$REGISTRY" "$REGISTRY-arm64" --arch arm64
        ;;
      esac
    done

    echo "[INFO] Pushing multiarch manifest..."
    docker manifest push "$REGISTRY"
    echo "[INFO] Successfully pushed multiarch image to $REGISTRY"

    # Clean up registry-specific tags
    docker rmi "$REGISTRY-amd64" "$REGISTRY-arm64" 2>/dev/null || true
  else
    # Push single architecture
    single_arch="${available_images[0]}"
    case "$single_arch" in
    x86_64-linux)
      docker tag arbeitszeitapp:latest-amd64 "$REGISTRY"
      ;;
    aarch64-linux)
      docker tag arbeitszeitapp:latest-arm64 "$REGISTRY"
      ;;
    esac

    echo "[INFO] Pushing single architecture image..."
    docker push "$REGISTRY"
    echo "[INFO] Successfully pushed single-arch ($single_arch) image to $REGISTRY"
  fi
  ;;
*)
  echo "Error: Invalid command '$COMMAND'."
  usage
  ;;
esac
