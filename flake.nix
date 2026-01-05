{
  description = "Implements a module for running workers control app";
  inputs = {
    workers-control.url = "github:ida-arbeitszeit/workers-control?ref=v0.1.4";
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs-25-11,
      nixpkgs-unstable,
      workers-control,
      flake-utils,
    }:
    let
      systemDependent = flake-utils.lib.eachSystem [ "x86_64-linux" ] (
        system:
        let
          pkgs-unstable = import nixpkgs-unstable { inherit system; };
          makeSimpleTest =
            testFile: name: nixpkgs:
            nixpkgs.testers.nixosTest {
              name = name;
              nodes.machine =
                { config, ... }:
                {
                  virtualisation.memorySize = 2048;
                  virtualisation.diskSize = 1024;
                  imports = [ self.nixosModules.default ];
                  nixpkgs.pkgs = nixpkgs;
                  services.workers-control.enable = true;
                  services.workers-control.hostName = "localhost";
                  services.workers-control.enableHttps = false;
                  services.workers-control.emailEncryptionType = null;
                  services.workers-control.emailPluginModule = "workers_control.flask.mail_service.debug_mail_service";
                  services.workers-control.emailPluginClass = "DebugMailService";
                  services.workers-control.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
                    builtins.toJSON {
                      MAIL_SERVER = "mail.server.example";
                      MAIL_PORT = "25";
                      MAIL_USERNAME = "mail@mail.server.example";
                      MAIL_PASSWORD = "secret password";
                      MAIL_DEFAULT_SENDER = "sender@mail.server.example";
                      MAIL_ADMIN = "admin@mail.server.example";
                    }
                  );
                };
              testScript = builtins.readFile testFile;
            };
          makeTestWithProfiling =
            testFile: name: nixpkgs:
            nixpkgs.testers.nixosTest {
              name = name;
              nodes.machine =
                { config, ... }:
                {
                  virtualisation.memorySize = 2048;
                  virtualisation.diskSize = 1024;
                  imports = [ self.nixosModules.default ];
                  nixpkgs.pkgs = nixpkgs;
                  services.workers-control.enable = true;
                  services.workers-control.hostName = "localhost";
                  services.workers-control.enableHttps = false;
                  services.workers-control.emailEncryptionType = null;
                  services.workers-control.emailPluginModule = "workers_control.flask.mail_service.debug_mail_service";
                  services.workers-control.emailPluginClass = "DebugMailService";
                  services.workers-control.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
                    builtins.toJSON {
                      MAIL_SERVER = "mail.server.example";
                      MAIL_PORT = "25";
                      MAIL_USERNAME = "mail@mail.server.example";
                      MAIL_PASSWORD = "secret password";
                      MAIL_DEFAULT_SENDER = "sender@mail.server.example";
                      MAIL_ADMIN = "admin@mail.server.example";
                    }
                  );
                  services.workers-control.profilingEnabled = true;
                  services.workers-control.profilingCredentialsFile = nixpkgs.writeText "profiling.json" (
                    builtins.toJSON {
                      PROFILING_AUTH_USER = "testuser";
                      PROFILING_AUTH_PASSWORD = "testpassword";
                    }
                  );
                };
              testScript = builtins.readFile testFile;
            };
          nixpkgsVersions = {
            "25-11" = import nixpkgs-25-11 { inherit system; };
            unstable = import nixpkgs-unstable { inherit system; };
          };
          makeTestMatrix =
            testFunctions:
            builtins.foldl' (
              tests: testName:
              tests // (makeTests testFunctions."${testName}" testName (builtins.attrNames nixpkgsVersions))
            ) { } (builtins.attrNames testFunctions);
          makeTests =
            testFunction: testName:
            builtins.foldl' (
              tests: nixpkgsName:
              tests
              // {
                "${testName}-${nixpkgsName}" =
                  testFunction "${testName}-${nixpkgsName}"
                    nixpkgsVersions."${nixpkgsName}";
              }
            ) { };
          testCases = {
            webserver = makeSimpleTest tests/launchWebserver.py;
            wsProfiler = makeTestWithProfiling tests/launchWebserver.py;
            profiling = makeTestWithProfiling tests/testProfiling.py;
          };
          pythonEnv = pkgs-unstable.python3.withPackages (
            p: with p; [
              black
              mypy
              flake8
              isort
            ]
          );
        in
        {
          devShells = {
            default = pkgs-unstable.mkShell {
              packages = [
                pythonEnv
                pkgs-unstable.nixfmt
              ];
            };
          };
          checks = makeTestMatrix testCases;
        }
      );
      systemIndependent = {
        nixosModules = {
          default = import modules/default.nix {
            overlay = workers-control.overlays.default;
          };
        };
      };
    in
    systemDependent // systemIndependent;
}
