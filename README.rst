arbeitszeit deployment utilities
================================

This repository contains code to help with the deployment of the
arbeitszeitapp. For now this is mostly limited to NixOS
modules. Currently the repository is not stable in any way. Please
don't use its content for now.

The `nix flake`_ defined in this repository provides a NixOS
module. This module allows NixOS administrators to setup a basic
instance of the arbeitszeitapp.

There are some basic smoke tests included in this repository that can
and should be executed via ``nix flake check``.

Update process
==============

- Make sure that you have checked out the newest version of this
  repository on your local machine.
- Run ``nix flake update --commit-lock-file`` to update all the flake
  inputs
- Run the tests via ``nix flake check``
- Create a pull request on github

Deployment Scenarios
====================

This repository provides two deployment options:

1. **NixOS Module** - For deploying on NixOS systems using the Nix package manager
2. **Docker Deployment** - For deploying on any system that supports Docker

Docker Deployment
----------------

All Docker deployment scenarios are configured using a `.env` file. Before you begin, copy the example file and customize it with your settings:

.. code-block:: bash

   cp docker-deployment/.env.example docker-deployment/.env

Now, edit the `.env` file to set your `SERVER_NAME`, database credentials, and email address.

A helper script `run-deployment.sh` is provided to simplify running each scenario.

**Script Overview**

The deployment includes two main scripts for different purposes:

1. **`run-deployment.sh`** - Day-to-day deployment operations
2. **`maintenance/update-deployment.sh`** - Comprehensive deployment updates

**run-deployment.sh vs update-deployment.sh**

.. list-table:: Script Comparison
   :widths: 30 35 35
   :header-rows: 1

   * - Aspect
     - run-deployment.sh
     - update-deployment.sh
   * - **Purpose**
     - Single deployment operations
     - Comprehensive updates & upgrades
   * - **Scope**
     - Start/stop services, build images
     - Multi-step update process
   * - **Dependencies**
     - Works with current setup
     - Updates flake inputs, checks PostgreSQL
   * - **Downtime**
     - User manages manually
     - Configurable strategies (zero/minimal/full)
   * - **Health Checks**
     - Manual verification needed
     - Automatic health verification
   * - **Use Cases**
     - Development, testing, CI/CD
     - Production updates, maintenance
   * - **Frequency**
     - Daily operations
     - Scheduled updates (weekly/monthly)

**When to Use Each Script:**

**Use `run-deployment.sh` for:**

- **Development workflow**: Starting and stopping services during development
- **Initial deployment**: Setting up a new deployment for the first time
- **Testing**: Quick builds and deployments for testing changes
- **CI/CD pipelines**: Automated builds and deployments in continuous integration
- **Manual operations**: When you need precise control over individual steps

.. code-block:: bash

   # Development examples
   ./run-deployment.sh up http              # Start development environment
   ./run-deployment.sh down http            # Stop development environment
   ./run-deployment.sh build                # Build latest changes
   
   # CI/CD examples
   ./run-deployment.sh build x86_64-linux registry/app:$VERSION
   ./run-deployment.sh build-multiarch registry/app:latest

**Use `update-deployment.sh` for:**

- **Production updates**: Updating live production deployments
- **Scheduled maintenance**: Regular updates with dependency management
- **Major upgrades**: PostgreSQL version upgrades, system updates
- **Automated maintenance**: Scripted updates with health verification
- **Emergency updates**: Quick updates with appropriate downtime strategies

.. code-block:: bash

   # Production examples
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime zero
   ./maintenance/update-deployment.sh --mode letsencrypt --postgres 16
   
   # Maintenance examples
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime minimal
   ./maintenance/update-deployment.sh --mode http --skip-flake-update

**Typical Workflow Examples:**

**Development Workflow:**

.. code-block:: bash

   # Initial setup
   cp docker-deployment/.env.example docker-deployment/.env
   # Edit .env file with your settings
   
   # Start development environment
   ./run-deployment.sh up http
   
   # Make code changes, then rebuild and restart
   ./run-deployment.sh build
   ./run-deployment.sh down http
   ./run-deployment.sh up http
   
   # Or use update script for comprehensive rebuild
   ./maintenance/update-deployment.sh --mode http --skip-flake-update

**Production Deployment:**

.. code-block:: bash

   # Initial production deployment
   ./run-deployment.sh build
   ./run-deployment.sh up letsencrypt
   
   # Regular maintenance (weekly/monthly)
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime zero
   
   # Emergency updates
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime minimal --skip-flake-update
   
   # Major upgrades
   ./maintenance/update-deployment.sh --mode letsencrypt --postgres 16 --downtime full

**CI/CD Pipeline:**

.. code-block:: bash

   # Build and push (in CI)
   ./run-deployment.sh build x86_64-linux registry/app:$VERSION
   ./run-deployment.sh build-multiarch registry/app:latest
   
   # Deploy (in CD)
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime zero --skip-flake-update

**Deployment Script Usage (run-deployment.sh):**

The `run-deployment.sh` script handles individual deployment operations:

.. code-block:: bash

   # Start deployments
   ./run-deployment.sh up http          # HTTP mode
   ./run-deployment.sh up https         # HTTPS mode
   ./run-deployment.sh up letsencrypt   # Let's Encrypt mode
   
   # Stop deployments
   ./run-deployment.sh down http        # Stop HTTP mode
   ./run-deployment.sh down https       # Stop HTTPS mode
   ./run-deployment.sh down letsencrypt # Stop Let's Encrypt mode
   
   # Build Docker images
   ./run-deployment.sh build                    # Build for current architecture
   ./run-deployment.sh build x86_64-linux      # Build for x86_64
   ./run-deployment.sh build aarch64-linux     # Build for ARM64
   ./run-deployment.sh build-multiarch         # Build multiarch (both x86_64 and ARM64)
   
   # Build and push to registry
   ./run-deployment.sh build x86_64-linux docker.io/myuser/app:v1.0
   ./run-deployment.sh build-multiarch docker.io/myuser/app:v1.0

1. **HTTP only (for local development)**
   - This is the simplest setup, serving your application over HTTP without SSL.
   - Command to start:
     
     .. code-block:: bash

        ./run-deployment.sh up http

2. **Manual HTTPS (with your own certificates)**
   - This setup serves your application over HTTPS using SSL certificates you provide.
   - **Prerequisites**: Place your certificate (`fullchain.pem`) and private key (`privkey.pem`) in a `certs/` directory.
   - Command to start:
     
     .. code-block:: bash

        ./run-deployment.sh up https

3. **Automatic HTTPS (with Let's Encrypt - Recommended for Production)**
   - This setup uses `nginx-proxy` and `letsencrypt-nginx-proxy-companion` to automatically obtain and renew SSL certificates from Let's Encrypt.
   - **Prerequisites**: Ensure your domain's DNS A/AAAA record points to your server's public IP address.
   - Command to start:
     
     .. code-block:: bash

        ./run-deployment.sh up letsencrypt

**Stopping the Deployment**

To stop the services for any scenario, use the `down` command with the corresponding mode. For example, to stop the `letsencrypt` deployment:

.. code-block:: bash

   ./run-deployment.sh down letsencrypt

Docker Deployment Architecture
=============================

The Docker deployment uses Docker Compose to orchestrate multiple services. Here's what happens behind the scenes for each deployment mode:

Service Architecture
-------------------

All deployment modes include these core services:

**Database Service (db)**
  - PostgreSQL database container
  - Persistent data storage via Docker volumes
  - Automatic health checks
  - Environment-based configuration
  - Database URL automatically constructed from ``POSTGRES_USER``, ``POSTGRES_PASSWORD``, and ``POSTGRES_DB``

**Application Service (arbeitszeitapp)**
  - Main application container built from Nix
  - Configurable server type (Flask development or uWSGI production)
  - Automatic database migrations on startup
  - Health checks via HTTP endpoints
  - Volume mounts for configuration and data
  - Dynamic profiling configuration via environment variables

**Reverse Proxy (nginx)**
  - Handles SSL termination and static file serving
  - Routes requests to the application container
  - Configuration varies by deployment mode

Deployment Mode Details
----------------------

**HTTP Mode (Development)**

This mode uses the following Docker Compose files:
- ``docker-compose.yml`` - Base services (database, application)
- ``docker-compose.override.yml`` - Development overrides (port mapping, etc.)

Services deployed:
- PostgreSQL database on internal network
- Application container with Flask development server
- Nginx reverse proxy serving HTTP on port 80

.. code-block:: bash

   ./run-deployment.sh up http

**HTTPS Mode (Manual Certificates)**

This mode extends the HTTP setup with SSL certificates you provide:
- ``docker-compose.yml`` - Base services
- ``docker-compose.override.yml`` - Development overrides
- ``docker-compose.https.yml`` - HTTPS configuration

Additional requirements:
- SSL certificate files in ``certs/`` directory (project root)
- ``fullchain.pem`` - Certificate chain file
- ``privkey.pem`` - Private key file

Services deployed:
- Same as HTTP mode plus SSL termination
- Nginx configured for HTTPS on port 443
- HTTP requests redirected to HTTPS

.. code-block:: bash

   ./run-deployment.sh up https

**Let's Encrypt Mode (Automatic SSL)**

This mode uses a different compose file optimized for production:
- ``docker-compose.letsencrypt.yml`` - Complete production setup

Additional services:
- ``nginx-proxy`` - Automated reverse proxy with SSL support
- ``letsencrypt-nginx-proxy-companion`` - Automatic SSL certificate management

Services deployed:
- PostgreSQL database
- Application container 
- Nginx proxy with automatic SSL certificate generation
- Let's Encrypt companion for certificate renewal

.. code-block:: bash

   ./run-deployment.sh up letsencrypt

**Server Configuration**

The application supports two server types that can be configured via the ``SERVER_TYPE`` environment variable:

**Flask Development Server** (``SERVER_TYPE=flask``, ``dev``, or ``development``):
  - Single-threaded development server
  - Built-in Flask development server with debugging support
  - Suitable for development and testing
  - **Not recommended for production use**

**uWSGI Production Server** (``SERVER_TYPE=uwsgi``, ``prod``, or ``production``):
  - Multi-process, multi-threaded production WSGI server
  - Configured with 4 processes and 2 threads per process
  - Optimized for production workloads
  - **Recommended for production deployments**

**Configuration Examples:**

.. code-block:: bash

   # Development environment
   echo "SERVER_TYPE=flask" >> docker-deployment/.env
   ./run-deployment.sh up http
   
   # Production environment
   echo "SERVER_TYPE=uwsgi" >> docker-deployment/.env
   ./run-deployment.sh up letsencrypt

**Environment Configuration**

All modes use the same ``.env`` file for configuration:

.. code-block:: bash

   # Database configuration
   # DATABASE_URL is automatically constructed from these values
   POSTGRES_DB=arbeitszeitapp
   POSTGRES_USER=arbeitszeitapp
   POSTGRES_PASSWORD=your_secure_password
   
   # Application configuration
   SERVER_NAME=your-domain.com
   
   # Server type configuration
   SERVER_TYPE=flask  # Options: flask, dev, development, uwsgi, prod, production
   
   # Email configuration (required)
   MAIL_SERVER=smtp.gmail.com
   MAIL_PORT=587
   MAIL_USERNAME=your-email@gmail.com
   MAIL_PASSWORD=your-app-password
   MAIL_DEFAULT_SENDER=your-email@gmail.com
   MAIL_USE_TLS=true
   MAIL_USE_SSL=false
   
   # Let's Encrypt configuration (for letsencrypt mode)
   LETSENCRYPT_EMAIL=admin@your-domain.com
   
   # Profiling configuration (optional)
   PROFILING_ENABLED=false
   PROFILING_AUTH_ENABLED=false
   PROFILING_USERNAME=admin
   PROFILING_PASSWORD=your_profiling_password
   PROFILING_ENDPOINT=profiling

**Profiling Configuration**

The application includes Flask-profiler integration for performance monitoring. Profiling is configured entirely via environment variables:

- **PROFILING_ENABLED**: Enable/disable profiling (default: false)
- **PROFILING_AUTH_ENABLED**: Enable basic authentication for profiling endpoint (default: false)
- **PROFILING_USERNAME**: Username for profiling endpoint access
- **PROFILING_PASSWORD**: Password for profiling endpoint access
- **PROFILING_ENDPOINT**: URL path for profiling interface (default: "profiling")

When enabled, profiling data is accessible at ``http://your-domain.com/profiling`` (or your configured endpoint path). The profiling configuration is generated dynamically at runtime, eliminating the need for static configuration files.

**Alternative File-Based Profiling Configuration:**

If you prefer to use a file-based configuration, you can create a ``profiling.json`` file and mount it into the container. See ``profiling.json.example`` for the required format. The application will automatically detect and use this file if present, taking precedence over environment variables.

**Using File-Based Configurations:**

To use file-based configurations instead of environment variables:

.. code-block:: bash

   # Copy and customize the example files
   cp mailconfig.json.example mailconfig.json
   cp profiling.json.example profiling.json
   
   # Edit the files with your settings
   nano mailconfig.json
   nano profiling.json
   
   # Mount them into the container by adding volumes to your Docker Compose override:
   # docker-deployment/docker-compose.override.yml
   cat >> docker-deployment/docker-compose.override.yml << EOF
   services:
     arbeitszeitapp:
       volumes:
         - ../mailconfig.json:/app/mailconfig.json:ro
         - ../profiling.json:/app/profiling.json:ro
   EOF

**Mail Configuration**

The application requires email functionality for core features like user registration, password resets, and notifications. Mail configuration is handled via environment variables:

- **MAIL_SERVER**: SMTP server hostname (e.g., ``smtp.gmail.com``) - **Required**
- **MAIL_PORT**: SMTP server port (default: 587)
- **MAIL_USERNAME**: SMTP username/email address - **Required**
- **MAIL_PASSWORD**: SMTP password or app-specific password - **Required**
- **MAIL_DEFAULT_SENDER**: Default sender email address - **Required**
- **MAIL_USE_TLS**: Enable TLS encryption (default: true)
- **MAIL_USE_SSL**: Enable SSL encryption (default: false)

**Important:** Email configuration is **required** for the application to function properly. Without valid email settings, user registration and password reset functionality will not work.

**Common SMTP Providers:**

.. list-table:: Popular Email Providers
   :widths: 20 25 15 40
   :header-rows: 1

   * - Provider
     - SMTP Server
     - Port
     - Notes
   * - **Gmail**
     - smtp.gmail.com
     - 587
     - Requires App Password (not your regular password)
   * - **Outlook/Hotmail**
     - smtp-mail.outlook.com
     - 587
     - Use your regular Microsoft account credentials
   * - **Yahoo Mail**
     - smtp.mail.yahoo.com
     - 587
     - Requires App Password
   * - **SendGrid**
     - smtp.sendgrid.net
     - 587
     - Professional service, requires API key as password
   * - **Mailgun**
     - smtp.mailgun.org
     - 587
     - Professional service, requires API credentials

**Gmail Setup Example:**

For Gmail, you need to create an "App Password" (not your regular password):

.. code-block:: bash

   # 1. Enable 2-Factor Authentication on your Google account
   # 2. Go to Google Account settings > Security > App passwords
   # 3. Generate an app password for "Mail"
   # 4. Use this generated password in MAIL_PASSWORD

   MAIL_SERVER=smtp.gmail.com
   MAIL_PORT=587
   MAIL_USERNAME=youremail@gmail.com
   MAIL_PASSWORD=your_16_character_app_password
   MAIL_DEFAULT_SENDER=youremail@gmail.com
   MAIL_USE_TLS=true
   MAIL_USE_SSL=false

**Alternative File-Based Mail Configuration:**

If you prefer to use a file-based configuration, you can create a ``mailconfig.json`` file and mount it into the container. See ``mailconfig.json.example`` for the required format. The application will automatically detect and use this file if present, taking precedence over environment variables.

**Docker Image Building**

The application Docker image is built using Nix and contains:

- Python application with all dependencies
- Flask development server (with debug mode support)
- Database migration tools (Alembic)
- Configuration management utilities
- Health check endpoints
- Flask-profiler integration for performance monitoring

The profiling system is configured via environment variables and generates configuration dynamically at runtime, eliminating the need for static configuration files.

**Build options:**

.. code-block:: bash

   # Single architecture (matches your current Linux system)
   ./run-deployment.sh build
   
   # Specific architecture
   ./run-deployment.sh build x86_64-linux
   ./run-deployment.sh build aarch64-linux
   
   # Multiarch build (builds both architectures)
   ./run-deployment.sh build-multiarch
   
   # Push to registry
   ./run-deployment.sh build x86_64-linux docker.io/myuser/arbeitszeitapp:latest
   ./run-deployment.sh build-multiarch docker.io/myuser/arbeitszeitapp:latest

**Building ONLY the Application Docker Image**

If you want to build just the arbeitszeitapp Docker image without PostgreSQL, nginx, or other services, you can use the following approaches:

**Prerequisites:**
- **Linux system required** (building only works on Linux)
- **Nix with flakes enabled** (the build system uses Nix flakes)
- **Docker installed** (to load and use the resulting image)

**Method 1: Using run-deployment.sh (Recommended)**

.. code-block:: bash

   # Build for current Linux architecture
   ./run-deployment.sh build

   # Build for specific architecture
   ./run-deployment.sh build x86_64-linux    # AMD64/Intel
   ./run-deployment.sh build aarch64-linux   # ARM64

   # Build and push to registry
   ./run-deployment.sh build x86_64-linux docker.io/username/arbeitszeitapp:v1.0

**Method 2: Direct Nix Command**

.. code-block:: bash

   # Build the Docker image directly with Nix
   nix --extra-experimental-features nix-command \
       --extra-experimental-features flakes \
       build .#dockerImage --system x86_64-linux

   # Load the image into Docker
   docker load < result

   # Clean up
   rm -f result

**Method 3: Build for Multiple Architectures**

.. code-block:: bash

   # Build multiarch image (both AMD64 and ARM64)
   ./run-deployment.sh build-multiarch

   # Build multiarch and push to registry
   ./run-deployment.sh build-multiarch docker.io/username/arbeitszeitapp:v1.0

**What You Get:**

The build process creates a **standalone Docker image** containing:

✅ **arbeitszeitapp application** with all Python dependencies  
✅ **Runtime server options** (Flask dev server OR uWSGI production server)  
✅ **Configuration system** that generates config files at runtime  
✅ **Management commands** for database migrations, etc.  
✅ **Health check endpoint** at ``/health``  
✅ **All required system dependencies** (Python, uWSGI, etc.)

**Image Details:**

- **Name:** ``arbeitszeitapp:latest``
- **Port:** Exposes port 5000
- **User:** Runs as user ID 1000 (arbeitszeitapp)
- **Size:** Optimized with Nix (only includes necessary dependencies)
- **Configuration:** Uses environment variables and runtime config generation

**Using the Built Image:**

.. code-block:: bash

   # Run with Flask development server (default)
   docker run -p 5000:5000 arbeitszeitapp:latest

   # Run with uWSGI production server
   docker run -p 5000:5000 -e SERVER_TYPE=uwsgi arbeitszeitapp:latest

   # Run with custom database connection
   docker run -p 5000:5000 \
     -e DATABASE_URL=postgresql://user:pass@host/db \
     arbeitszeitapp:latest

**Key Points:**

🔴 **Linux Only:** Building must be done on a Linux system  
🟢 **No Dependencies:** The image is completely self-contained  
🟢 **Configurable:** Server type (Flask/uWSGI) configurable via environment variables  
🟢 **Production Ready:** Includes security hardening and proper user management  

The resulting image is **completely independent** and doesn't require nginx, PostgreSQL, or any other services to run - those are handled separately in the Docker Compose configurations.

**Using Pre-built Images from Registry**

If you're running the deployment on a non-Linux system (Windows, macOS) or want to use pre-built images, you can override the default image location:

**Option 1: Environment Variable**

.. code-block:: bash

   # Set the image registry location
   export ARBEITSZEITAPP_IMAGE=myregistry/arbeitszeitapp:latest
   
   # Run the deployment normally
   ./run-deployment.sh up letsencrypt

**Option 2: Pull and Tag**

.. code-block:: bash

   # Pull from registry and tag as expected name
   docker pull myregistry/arbeitszeitapp:latest
   docker tag myregistry/arbeitszeitapp:latest arbeitszeitapp:latest
   
   # Run the deployment normally
   ./run-deployment.sh up letsencrypt

**Option 3: Docker Compose Override**

.. code-block:: bash

   # Create override file
   cat > docker-deployment/docker-compose.override.yml << EOF
   services:
     arbeitszeitapp:
       image: myregistry/arbeitszeitapp:latest
   EOF
   
   # Run the deployment normally
   ./run-deployment.sh up letsencrypt

This approach allows Windows servers, macOS systems, or any Docker-compatible environment to run the deployment using pre-built images without requiring a Linux build environment.

**Operating System Requirements**

Building Docker images requires a Linux host system. The flake supports:

- **x86_64-linux** (Intel/AMD 64-bit)
- **aarch64-linux** (ARM 64-bit)

**Running the deployment** works on any Docker-compatible system (Windows, macOS, Linux).

**For non-Linux development:**

If you're developing on macOS or Windows, you'll need to use a Linux environment for building:

- **Linux VM**: Set up a Linux virtual machine (Ubuntu, Debian, etc.)
- **GitHub Actions**: Use CI/CD for building and testing
- **Linux development server**: Use a remote Linux machine
- **Docker Desktop with Linux containers**: For running (building still requires Linux)

**Common Issues:**

- **"unsupported system" errors**: Ensure you're running on a Linux system for building Docker images
- **"ERROR: Docker image building is only supported on Linux"**: Use a Linux VM or CI/CD for building
- **Docker permission errors**: Add your user to the docker group
- **Nix not found**: Install Nix package manager on your Linux system

**Production Deployment Checklist**

For production deployments, ensure you have:

1. **Domain Configuration**
   - DNS A/AAAA records pointing to your server
   - Firewall rules allowing ports 80 and 443

2. **Environment Setup**
   - Secure database passwords in ``.env``
   - Valid email address for Let's Encrypt
   - Backup strategy for database volumes

3. **SSL Certificates**
   - For HTTPS mode: Valid SSL certificates in ``certs/`` directory
   - For Let's Encrypt mode: Ensure domain is publicly accessible

4. **Monitoring and Maintenance**
   - Regular database backups
   - Log monitoring and rotation
   - Security updates for base images

**Troubleshooting Common Issues**

- **Port conflicts**: Ensure ports 80 and 443 are not in use by other services
- **SSL certificate issues**: Check certificate validity and file permissions
- **Database connection errors**: Verify database credentials and network connectivity
- **Let's Encrypt failures**: Ensure domain points to server and is publicly accessible
- **Profiling endpoint issues**: Check PROFILING_ENABLED environment variable and authentication settings
- **Container health check failures**: Use ``./tests/docker/test-deployments.sh`` to diagnose issues

**Automated Troubleshooting**

The test script provides comprehensive failure diagnosis:

.. code-block:: bash

   # Run diagnostic tests
   ./tests/docker/test-deployments.sh --modes http
   
   # Check failure logs (automatically generated)
   ls -la arbeitszeitapp_failure_logs_*.tar.gz
   
   # Extract and examine logs
   tar -xzf arbeitszeitapp_failure_logs_*.tar.gz
   cat arbeitszeitapp_failure_logs_*/SUMMARY.txt

**Monitoring and Maintenance**

The deployment includes comprehensive tools for monitoring and maintenance:

**Unified Update Script**

The ``maintenance/update-deployment.sh`` script provides a comprehensive solution for deployment updates:

.. code-block:: bash

   # Show all available options
   ./maintenance/update-deployment.sh --help
   
   # Standard production update
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime zero
   
   # Emergency update with full restart
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime full --verbose

**Monitoring Commands**

Monitor your deployment with these commands:

.. code-block:: bash

   # Check service status
   docker compose -f docker-deployment/docker-compose.yml ps
   
   # View logs
   docker compose -f docker-deployment/docker-compose.yml logs -f arbeitszeitapp
   docker compose -f docker-deployment/docker-compose.yml logs -f db
   
   # Check resource usage
   docker stats
   
   # Access application container for debugging
   docker compose -f docker-deployment/docker-compose.yml exec arbeitszeitapp bash
   
   # Run database migrations manually
   docker compose -f docker-deployment/docker-compose.yml exec arbeitszeitapp alembic-command upgrade head
   
   # Backup database
   docker compose -f docker-deployment/docker-compose.yml exec db pg_dump -U arbeitszeitapp arbeitszeitapp > backup.sql
   
   # Test deployment health
   ./tests/docker/test-deployments.sh --modes http
   
   # Monitor profiling data (if enabled)
   # Access http://your-domain.com/profiling with configured credentials

**Updating the Deployment**

A comprehensive update script is provided to handle all aspects of deployment updates:

.. code-block:: bash

   # Standard update with minimal downtime
   ./maintenance/update-deployment.sh --mode letsencrypt
   
   # Zero-downtime update for production
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime zero
   
   # Full restart with PostgreSQL upgrade
   ./maintenance/update-deployment.sh --mode letsencrypt --downtime full --postgres 16
   
   # Quick update skipping flake updates
   ./maintenance/update-deployment.sh --mode http --skip-flake-update

**Update Script Features:**

The update script automatically handles:

- **Flake Input Updates**: Updates all Nix flake dependencies to latest versions
- **PostgreSQL Version Checks**: Automatically detects and offers to upgrade PostgreSQL
- **Docker Image Building**: Rebuilds the application image with latest changes
- **Deployment Updates**: Updates services with configurable downtime strategies
- **Health Verification**: Runs automated tests to verify deployment health

**Downtime Strategies:**

- **Zero-downtime** (``--downtime zero``): Rolling update that recreates only changed services
- **Minimal-downtime** (``--downtime minimal``): Updates all services with minimal downtime (default)
- **Full restart** (``--downtime full``): Complete restart, useful for major configuration changes

**Script Options:**

.. code-block:: bash

   Usage: ./maintenance/update-deployment.sh [OPTIONS]
   
   OPTIONS:
       -m, --mode MODE          Deployment mode (http, https, letsencrypt)
       -d, --downtime STRATEGY  Downtime tolerance (zero, minimal, full)
       -p, --postgres VERSION   Force PostgreSQL upgrade to specific version
       --skip-flake-update     Skip flake input updates
       --skip-postgres-check   Skip PostgreSQL version check
       -v, --verbose           Enable verbose output
       -h, --help              Show help message

**Manual Update Process (Advanced Users):**

If you prefer manual control, you can follow these steps:

.. code-block:: bash

   # 1. Pull latest changes
   git pull origin main
   
   # 2. Update flake inputs
   nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update --commit-lock-file
   
   # 3. Rebuild Docker image
   ./run-deployment.sh build
   
   # 4. Update deployment (choose one strategy):
   
   # Zero-downtime rolling update
   docker compose -f docker-deployment/docker-compose.letsencrypt.yml up -d --force-recreate arbeitszeitapp
   
   # Minimal-downtime update
   docker compose -f docker-deployment/docker-compose.letsencrypt.yml up -d
   
   # Full restart
   ./run-deployment.sh down letsencrypt
   ./run-deployment.sh up letsencrypt

**PostgreSQL Version Upgrades**

**Minor Version Updates (15.x → 15.y)**

Minor PostgreSQL updates are handled automatically:

.. code-block:: bash

   # Pull the latest image
   docker compose -f docker-deployment/docker-compose.yml pull db
   
   # Restart the database service
   ./run-deployment.sh down [mode]
   ./run-deployment.sh up [mode]

**Major Version Updates (15 → 16)**

Major PostgreSQL upgrades require data migration. Here's the recommended process:

.. code-block:: bash

   # 1. Backup your database
   docker compose -f docker-deployment/docker-compose.yml exec db pg_dump -U arbeitszeitapp arbeitszeitapp > backup.sql
   
   # 2. Stop the deployment
   ./run-deployment.sh down [mode]
   
   # 3. Update the PostgreSQL version in docker-compose files
   # Edit docker-compose.yml, docker-compose.https.yml, docker-compose.letsencrypt.yml
   # Change: image: postgres:15-alpine
   # To:     image: postgres:16-alpine
   
   # 4. Remove old volume data (THIS DELETES YOUR DATA!)
   docker volume rm docker-deployment_postgres-data
   
   # 5. Start with new PostgreSQL version
   ./run-deployment.sh up [mode]
   
   # 6. Restore your data
   docker compose -f docker-deployment/docker-compose.yml exec -T db psql -U arbeitszeitapp -d arbeitszeitapp < backup.sql

**Alternative: pg_upgrade approach**

For advanced users, you can use pg_upgrade within containers:

.. code-block:: bash

   # Create a temporary container with both PostgreSQL versions
   docker run --rm -it -v docker-deployment_postgres-data:/old-data -v postgres-new-data:/new-data postgres:16-alpine bash
   
   # Inside the container, run pg_upgrade
   # (This requires more advanced Docker knowledge)

**Automated PostgreSQL Upgrade (Recommended)**

The deployment update script can automatically handle PostgreSQL upgrades:

.. code-block:: bash

   # Upgrade PostgreSQL as part of deployment update
   ./maintenance/update-deployment.sh --mode letsencrypt --postgres 16
   
   # The script will automatically:
   # 1. Update flake inputs
   # 2. Create a database backup
   # 3. Stop the deployment
   # 4. Update Docker Compose files
   # 5. Remove old volume data
   # 6. Start deployment with new version
   # 7. Restore the backup
   # 8. Verify deployment health

**Manual PostgreSQL Upgrade Script**

For standalone PostgreSQL upgrades, a dedicated script is provided:

.. code-block:: bash

   # Upgrade from PostgreSQL 15 to 16
   ./maintenance/upgrade-postgres.sh 15 16

**Note**: This script requires manual confirmation before deleting data.

**PostgreSQL Version Management**

To check your current PostgreSQL version:

.. code-block:: bash

   docker compose -f docker-deployment/docker-compose.yml exec db psql -U arbeitszeitapp -c "SELECT version();"

**Update Strategy Notes:**

- **Zero-downtime** provides true zero-downtime updates for the application service
- **Minimal-downtime** minimizes downtime by only restarting changed services  
- **Full restart** should only be used when configuration changes require a complete restart
- Database updates typically don't require service restart unless you're upgrading PostgreSQL versions
- The update script automatically handles flake input updates and PostgreSQL version management

For more details on the automated update process, see the "Updating the Deployment" section above.

Testing the Docker Deployment
============================

The deployment includes comprehensive automated testing to validate all deployment scenarios.

Prerequisites
------------

To run the automated tests for Docker deployment scenarios, you need:

Required Software:
~~~~~~~~~~~~~~~~

* Docker Engine with Compose V2 support
* jq command-line tool for parsing JSON
* curl command-line tool for HTTP requests
* Bash shell (pre-installed on macOS and Linux)
* OpenSSL (for generating self-signed certificates)
* Nix package manager (for building the Docker image)

Installation on macOS:
~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   brew install docker jq curl openssl nix

Installation on Linux (Debian/Ubuntu):
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   apt-get update && apt-get install -y docker.io jq curl openssl
   # Install Nix (see https://nixos.org/download.html)
   sh <(curl -L https://nixos.org/nix/install) --no-daemon

Setup and Configuration:
~~~~~~~~~~~~~~~~~~~~~~

1. Create and configure environment file:

.. code-block:: bash

   # Copy the example environment file
   cd docker-deployment
   cp .env.example .env
   
   # Edit the file with your preferred settings
   nano .env

2. Generate self-signed certificates for HTTPS testing:

.. code-block:: bash

   # Create certificates directory if it doesn't exist
   mkdir -p certs
   
   # Generate self-signed certificate valid for 1 year
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout certs/privkey.pem \
     -out certs/fullchain.pem \
     -subj "/CN=localhost" \
     -addext "subjectAltName=DNS:localhost"

3. Build and load the Docker image:

.. code-block:: bash

   # From the project root directory
   # For single-arch build (matches current Linux system architecture)
   ./run-deployment.sh build
   
   # For multiarch build
   ./run-deployment.sh build-multiarch
   
   # For specific architecture
   ./run-deployment.sh build x86_64-linux
   ./run-deployment.sh build aarch64-linux

Running the Tests
---------------

Execute the test script from the project root directory:

.. code-block:: bash

   # Make the script executable if needed
   chmod +x tests/docker/test-deployments.sh
   
   # Run all tests with single-arch build (default)
   ./tests/docker/test-deployments.sh
   
   # Run all tests with multiarch build
   ./tests/docker/test-deployments.sh --multiarch
   
   # Test specific deployment modes
   ./tests/docker/test-deployments.sh --modes http
   ./tests/docker/test-deployments.sh --modes https,letsencrypt
   
   # Let's Encrypt testing options
   ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test staging
   ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test mock
   ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test containers-only
   
   # Show help and available options
   ./tests/docker/test-deployments.sh --help

**Test Script Options:**

* ``--multiarch`` - Build multiarch Docker images instead of single-arch
* ``--modes MODE1,MODE2`` - Test specific deployment modes (http, https, letsencrypt)
* ``--letsencrypt-test MODE`` - Configure Let's Encrypt testing approach:
  
  - ``staging`` - Use Let's Encrypt staging environment with real domains
  - ``mock`` - Test with mock domains and /etc/hosts configuration
  - ``containers-only`` - Test container orchestration without certificate requests

* ``--help`` - Show usage information and available options

**Test Coverage:**

The test suite validates:

* **Container Health**: All services start correctly and pass health checks
* **Database Connectivity**: Database migrations and connection functionality
* **HTTP/HTTPS Endpoints**: Application accessibility and SSL configuration
* **Static File Serving**: CSS, JavaScript, and other static assets
* **Flask-Profiler Integration**: Performance monitoring endpoints (when enabled)
* **Let's Encrypt Integration**: Certificate provisioning and renewal (staging/mock modes)
* **Service Restart Resilience**: Application recovery after container restarts

**Automated Build Process:**

The test script will automatically:

* Check for all required tools and configuration
* Build the Docker image if not already present
* Use single-arch build by default for faster testing
* Support multiarch builds for both supported Linux architectures (x86_64 and aarch64)
* Clean up resources after testing is complete

**Failure Diagnostics:**

When tests fail, the script automatically:

* Collects comprehensive logs from all containers
* Captures Docker system information and resource usage
* Generates detailed failure reports in timestamped archives
* Preserves logs for troubleshooting: ``arbeitszeitapp_failure_logs_*.tar.gz``

**Let's Encrypt Testing Modes:**

The test script supports multiple approaches for testing Let's Encrypt functionality:

**Staging Mode**
  Uses Let's Encrypt staging environment with real domains (requires valid DNS). This mode requires:
  
  - A real domain name configured in your ``.env`` file
  - DNS A/AAAA records pointing to your server
  - Internet connectivity for Let's Encrypt validation
  
  .. code-block:: bash
  
     ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test staging

**Mock Mode**
  Tests with mock domains using ``/etc/hosts`` configuration (safe for development). This mode allows testing Let's Encrypt container orchestration without requiring real domains or internet connectivity.
  
  **Prerequisites for Mock Mode:**
  
  Before running mock mode tests, you need to add entries to your ``/etc/hosts`` file to simulate domain resolution:
  
  .. code-block:: bash
  
     # Add these entries to /etc/hosts (requires sudo)
     sudo bash -c 'echo "127.0.0.1 letsencrypt-test.example.com" >> /etc/hosts'
     sudo bash -c 'echo "::1 letsencrypt-test.example.com" >> /etc/hosts'
  
  **Alternative method using a text editor:**
  
  .. code-block:: bash
  
     # Edit /etc/hosts with your preferred editor
     sudo nano /etc/hosts
     
     # Add these lines to the file:
     127.0.0.1 letsencrypt-test.example.com
     ::1 letsencrypt-test.example.com
  
  **Verification:**
  
  After adding the entries, verify they work correctly:
  
  .. code-block:: bash
  
     # Test domain resolution
     ping -c 1 letsencrypt-test.example.com
     nslookup letsencrypt-test.example.com
     
     # Should resolve to 127.0.0.1 (localhost)
  
  **Running Mock Mode Tests:**
  
  .. code-block:: bash
  
     ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test mock
  
  **What Mock Mode Tests:**
  
  - Container orchestration with nginx-proxy and letsencrypt-nginx-proxy-companion
  - Service discovery and routing configuration
  - Environment variable configuration for Let's Encrypt
  - Application accessibility through the nginx proxy
  - Certificate request processes (will fail gracefully as expected)
  
  **Important Notes:**
  
  - Mock mode will attempt certificate provisioning but certificates will fail to generate (this is expected behavior)
  - The test validates that the application remains accessible despite certificate failures
  - Certificate provisioning errors are expected and do not indicate test failure
  - The test focuses on container orchestration and service configuration rather than actual SSL certificates
  
  **Cleanup:**
  
  After testing, you may want to remove the mock entries from ``/etc/hosts``:
  
  .. code-block:: bash
  
     # Remove the mock domain entries
     sudo sed -i '' '/letsencrypt-test.example.com/d' /etc/hosts
     
     # Or manually edit the file to remove the lines
     sudo nano /etc/hosts

**Containers-Only Mode**
  Validates container orchestration without certificate requests. This mode tests the deployment configuration without attempting any certificate provisioning:
  
  .. code-block:: bash
  
     ./tests/docker/test-deployments.sh --modes letsencrypt --letsencrypt-test containers-only

This comprehensive testing ensures deployment reliability across all supported scenarios.

.. _`nix flake`: https://nixos.wiki/wiki/Flakes
