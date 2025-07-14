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

**Application Service (arbeitszeitapp)**
  - Main application container built from Nix
  - uWSGI server serving the Flask application
  - Automatic database migrations on startup
  - Health checks via HTTP endpoints
  - Volume mounts for configuration and data

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
- Application container with uWSGI
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

**Environment Configuration**

All modes use the same ``.env`` file for configuration:

.. code-block:: bash

   # Database configuration
   POSTGRES_DB=arbeitszeitapp
   POSTGRES_USER=arbeitszeitapp
   POSTGRES_PASSWORD=your_secure_password
   
   # Application configuration
   SERVER_NAME=your-domain.com
   DATABASE_URL=postgresql://arbeitszeitapp:your_secure_password@db/arbeitszeitapp
   
   # Email configuration (optional)
   MAIL_CONFIG_PATH=/app/mailconfig.json
   
   # Let's Encrypt configuration (for letsencrypt mode)
   LETSENCRYPT_EMAIL=admin@your-domain.com

**Docker Image Building**

The application Docker image is built using Nix and contains:

- Python application with all dependencies
- uWSGI application server
- Database migration tools (Alembic)
- Configuration management utilities
- Health check endpoints

Build options:

.. code-block:: bash

   # Single architecture (current system)
   ./run-deployment.sh build
   
   # Specific architecture
   ./run-deployment.sh build x86_64-linux
   ./run-deployment.sh build aarch64-linux
   
   # Multi-architecture (both x86_64 and aarch64)
   ./run-deployment.sh build-multiarch
   
   # Push to registry
   ./run-deployment.sh build x86_64-linux docker.io/myuser/arbeitszeitapp:latest
   ./run-deployment.sh build-multiarch docker.io/myuser/arbeitszeitapp:latest

**macOS Considerations**

Building Docker images on macOS requires cross-compilation from Darwin to Linux. This may require additional Nix configuration.

**Step-by-Step Cross-compilation Setup:**

1. **Check current configuration** (optional but recommended)::

    ./check-nix-config.sh

   This script will diagnose your current Nix configuration and identify any issues.

2. **Configure Nix daemon** (requires admin privileges):

   .. code-block:: bash

      # Add trusted users and extra platforms
      echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
      echo "extra-platforms = x86_64-linux aarch64-linux" | sudo tee -a /etc/nix/nix.conf

3. **Restart the Nix daemon**:

   .. code-block:: bash

      # Restart daemon to apply changes
      sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
      sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist

4. **Verify configuration**:

   .. code-block:: bash

      # Check that settings are applied
      nix --extra-experimental-features nix-command config show | grep -E "(trusted-users|extra-platforms)"

   You should see your username in trusted-users and the additional platforms listed.

5. **Test cross-compilation**:

   .. code-block:: bash

      ./run-deployment.sh build-docker

**Troubleshooting Cross-compilation:**

If you encounter "Undefined error: 0" or similar cross-compilation failures:

- Ensure you have sufficient disk space (cross-compilation requires significant space)
- Verify Docker Desktop is running and configured for Linux containers
- Check that your Nix installation supports cross-compilation features
- Try building with increased verbosity: ``nix build --verbose --print-build-logs``
- Clean Nix store if space is limited: ``nix-collect-garbage -d``
- If using local path dependencies (``path:/Users/...``), ensure they are compatible with cross-compilation
- Consider using GitHub URLs instead of local paths for dependencies

**Known Issues:**

- **"Undefined error: 0" during cross-compilation**: This error occurs when cross-compiling from macOS to Linux, even with matching architectures (aarch64-darwin → aarch64-linux)
- The arbeitszeitapp flake DOES support aarch64-linux (confirmed by successful builds on native aarch64-linux VMs)
- The issue is specific to the cross-compilation mechanism from Darwin to Linux, not missing architecture support
- This appears to be related to how Nix handles cross-compilation from Darwin to Linux during the build process
- The same code builds successfully on native Linux systems (including aarch64-linux VMs)

**Alternative Approaches:**

If cross-compilation continues to fail, consider:

- Using a Linux VM or container for building
- Setting up CI/CD pipelines (GitHub Actions, etc.)
- Building on a Linux machine and pushing to a registry
- Using pre-built images from a registry
- Configuring remote Linux builders in Nix configuration

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

**Monitoring and Maintenance**

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

**Updating the Deployment**

To update your deployment:

.. code-block:: bash

   # Pull latest changes
   git pull origin main
   
   # Rebuild Docker image
   ./run-deployment.sh build
   
   # Restart services (example for letsencrypt mode)
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

**Automated PostgreSQL Upgrade Script**

For convenience, an automated upgrade script is provided:

.. code-block:: bash

   # Upgrade from PostgreSQL 15 to 16
   ./maintenance/upgrade-postgres.sh 15 16
   
   # The script will:
   # 1. Create a database backup
   # 2. Stop the deployment
   # 3. Update Docker Compose files
   # 4. Remove old volume data
   # 5. Start deployment with new version
   # 6. Restore the backup

**Note**: This script requires manual confirmation before deleting data.

**PostgreSQL Version Management**

To check your current PostgreSQL version:

.. code-block:: bash

   docker compose -f docker-deployment/docker-compose.yml exec db psql -U arbeitszeitapp -c "SELECT version();"

**Updating the Deployment**

There are several approaches to update your deployment, depending on your downtime tolerance:

**Method 1: Zero-Downtime Rolling Update (Recommended)**

.. code-block:: bash

   # Pull latest changes
   git pull origin main
   
   # Rebuild Docker image
   ./run-deployment.sh build
   
   # Rolling update - this recreates only changed services
   docker compose -f docker-deployment/docker-compose.letsencrypt.yml up -d --force-recreate arbeitszeitapp
   
   # Or for other modes:
   # docker compose -f docker-deployment/docker-compose.yml -f docker-deployment/docker-compose.https.yml up -d --force-recreate arbeitszeitapp

**Method 2: Minimal-Downtime Update**

.. code-block:: bash

   # Pull latest changes and rebuild
   git pull origin main
   ./run-deployment.sh build
   
   # Update all services with minimal downtime
   docker compose -f docker-deployment/docker-compose.letsencrypt.yml up -d

**Method 3: Full Restart (With Downtime)**

.. code-block:: bash

   # Pull latest changes
   git pull origin main
   
   # Rebuild Docker image
   ./run-deployment.sh build
   
   # Full restart (causes downtime)
   ./run-deployment.sh down letsencrypt
   ./run-deployment.sh up letsencrypt

**Update Strategy Notes:**

- **Method 1** provides true zero-downtime updates for the application service
- **Method 2** minimizes downtime by only restarting changed services
- **Method 3** should only be used when configuration changes require a full restart
- Database updates typically don't require service restart unless you're upgrading PostgreSQL versions

Testing the Docker Deployment
============================

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
   # For single-arch build (detects current architecture)
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
   
   # Run the tests with single-arch build (default)
   ./tests/docker/test-deployments.sh
   
   # Run the tests with multiarch build
   ./tests/docker/test-deployments.sh --multiarch
   
   # Show help and available options
   ./tests/docker/test-deployments.sh --help

**Test Script Options:**

* ``--multiarch`` - Build multiarch Docker images instead of single-arch (useful for testing cross-platform compatibility)
* ``--help`` - Show usage information and available options

**Build Process:**

The test script will automatically build the Docker image if it's not already present. You can choose between:

* **Single-arch build** (default): Builds for the current system architecture only, faster for local testing
* **Multiarch build** (``--multiarch``): Builds for both x86_64 and aarch64 architectures, slower but tests cross-platform compatibility

The script will:
* Check for all required tools and configuration
* Build the Docker image if not already present (single-arch by default, multiarch with ``--multiarch``)
* Create necessary temporary files
* Test each deployment scenario (HTTP, HTTPS, Let's Encrypt)
* Clean up after testing is complete

Note: The HTTPS tests require the self-signed certificates generated above.

.. _`nix flake`: https://nixos.wiki/wiki/Flakes
