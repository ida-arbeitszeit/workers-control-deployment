Workers Control deployment utilities
====================================

The `nix flake`_ defined in this repository provides a NixOS
module. This module allows NixOS administrators to setup a basic
instance of the workers control app.


Management commands
====================

The NixOS module provides a management command, `arbeitszeitapp-manage`,
which can be used by server admins to invite accountants to the app::

  arbeitszeitapp-manage

It provides also access to alembic, a tool for database migrations,
connected to worker control's database::

  alembic-command --help


Update dependencies
===================

The update process is as follows:

- Make sure that you have checked out the newest version of this
  repository on your local machine.
- If there is a new version of the workers control app, update the
  tag name in the workers control flake input in :py:mod:`flake.nix`.
- Run ``nix flake update --commit-lock-file`` to update all the flake
  inputs
- Run the tests via ``nix flake check``
- Create a pull request on github

There is a python script in this repository
that creates a remote branch with updated flake inputs::

  nix develop
  python update_repository.py


.. _`nix flake`: https://nixos.wiki/wiki/Flakes
