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

There is a python update script in this repository, "update_repository.py",
that automatically creates a remote branch with updated flake inputs.

.. _`nix flake`: https://nixos.wiki/wiki/Flakes
