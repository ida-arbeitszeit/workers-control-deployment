{
  description = "Implements a module for running arbeitszeitapp";
  inputs = {
    arbeitszeitapp.url = "github:ida-arbeitszeit/arbeitszeitapp";
    nixpkgs-25-05.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs-25-05,
      nixpkgs-unstable,
      arbeitszeitapp,
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
                  services.arbeitszeitapp.enable = true;
                  services.arbeitszeitapp.hostName = "localhost";
                  services.arbeitszeitapp.enableHttps = false;
                  services.arbeitszeitapp.emailEncryptionType = null;
                  services.arbeitszeitapp.emailPluginModule = "arbeitszeit_flask.mail_service.debug_mail_service";
                  services.arbeitszeitapp.emailPluginClass = "DebugMailService";
                  services.arbeitszeitapp.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
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
                  services.arbeitszeitapp.enable = true;
                  services.arbeitszeitapp.hostName = "localhost";
                  services.arbeitszeitapp.enableHttps = false;
                  services.arbeitszeitapp.emailEncryptionType = null;
                  services.arbeitszeitapp.emailPluginModule = "arbeitszeit_flask.mail_service.debug_mail_service";
                  services.arbeitszeitapp.emailPluginClass = "DebugMailService";
                  services.arbeitszeitapp.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
                    builtins.toJSON {
                      MAIL_SERVER = "mail.server.example";
                      MAIL_PORT = "25";
                      MAIL_USERNAME = "mail@mail.server.example";
                      MAIL_PASSWORD = "secret password";
                      MAIL_DEFAULT_SENDER = "sender@mail.server.example";
                      MAIL_ADMIN = "admin@mail.server.example";
                    }
                  );
                  services.arbeitszeitapp.profilingEnabled = true;
                  services.arbeitszeitapp.profilingCredentialsFile = nixpkgs.writeText "profiling.json" (
                    builtins.toJSON {
                      PROFILING_AUTH_USER = "testuser";
                      PROFILING_AUTH_PASSWORD = "testpassword";
                    }
                  );
                };
              testScript = builtins.readFile testFile;
            };
          nixpkgsVersions = {
            nixpkgs-25-05 = import nixpkgs-25-05 { inherit system; };
            nixpkgs-unstable = import nixpkgs-unstable { inherit system; };
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
            launchWebserver = makeSimpleTest tests/launchWebserver.py;
            launchWebserverWithProfiler = makeTestWithProfiling tests/launchWebserver.py;
            testProfiling = makeTestWithProfiling tests/testProfiling.py;
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
                pkgs-unstable.nixfmt-rfc-style
                pkgs-unstable.gh
              ];
            };
          };
          checks = makeTestMatrix testCases;
        }
      );
      systemIndependent = {
        nixosModules = {
          default = import modules/default.nix {
            overlay = arbeitszeitapp.overlays.default;
          };
        };
      };
    in
    systemDependent // systemIndependent;
}
