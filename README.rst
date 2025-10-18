arbeitszeit deployment utilities
================================

This repository contains code to help with the deployment of the
arbeitszeitapp. For now this is mostly limited to NixOS
modules.

The `nix flake`_ defined in this repository provides a NixOS
module. This module allows NixOS administrators to setup a basic
instance of the arbeitszeitapp.


Management commands
====================

The NixOS module provides a management command, `arbeitszeitapp-manage`,
which can be used by server admins to invite accountants to the app.

```sh
arbeitszeitapp-manage
```

It provides also access to alembic, a tool for database migrations,
connected to arbeitszeitapp's database:

```sh
alembic-command --help
```

Tests
=====

There are some basic smoke tests included in this repository that can
and should be executed via ``nix flake check``.

Update dependencies
===================

There is a handy python update script in this repository, "update_repository.py",
that automatically creates a remote branch with updated flake inputs. Run 
``python update_repository.py`` to use it.

A more manual update process is as follows:

- Make sure that you have checked out the newest version of this
  repository on your local machine.
- Run ``nix flake update --commit-lock-file`` to update all the flake
  inputs
- Run the tests via ``nix flake check``
- Create a pull request on github


.. _`nix flake`: https://nixos.wiki/wiki/Flakes
