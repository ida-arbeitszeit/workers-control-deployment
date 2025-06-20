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
   nix build .#dockerImage
   docker load < result

Running the Tests
---------------

Execute the test script from the project root directory:

.. code-block:: bash

   # Make the script executable if needed
   chmod +x tests/docker/test-deployments.sh
   
   # Run the tests (from project root directory)
   ./tests/docker/test-deployments.sh

The script will:
* Check for all required tools and configuration
* Create necessary temporary files
* Test each deployment scenario (HTTP, HTTPS, Let's Encrypt)
* Clean up after testing is complete

Note: The HTTPS tests require the self-signed certificates generated above.

.. _`nix flake`: https://nixos.wiki/wiki/Flakes
