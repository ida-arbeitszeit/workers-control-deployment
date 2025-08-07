{
  description = "Implements a module for running arbeitszeitapp";
  inputs = {
    arbeitszeitapp.url = "github:ida-arbeitszeit/arbeitszeitapp/addHealthCheckEndpoint";
    nixpkgs-24-11.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs-24-11, nixpkgs-unstable, arbeitszeitapp, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs-unstable = import nixpkgs-unstable { inherit system; };
        
        # Helper function to build Docker image for any system
        buildDockerImage = import ./modules/docker-image.nix {
          pkgs = pkgs-unstable;
          overlay = arbeitszeitapp.overlays.default;
          inherit system;
        };
        
        makeSimpleTest =
          testFile: name: nixpkgs:
          nixpkgs.nixosTest {
            name = name;
            nodes.machine =
              { ... }:
              {
                imports = [ self.nixosModules.default ];
                nixpkgs.pkgs = nixpkgs;
                services.arbeitszeitapp.enable = true;
                services.arbeitszeitapp.hostName = "localhost";
                services.arbeitszeitapp.enableHttps = false;
                services.arbeitszeitapp.emailEncryptionType = null;
                services.arbeitszeitapp.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
                  builtins.toJSON {
                    MAIL_SERVER = "mail.server.example";
                    MAIL_PORT = "465";
                    MAIL_USERNAME = "mail@mail.server.example";
                    MAIL_PASSWORD = "secret password";
                    MAIL_DEFAULT_SENDER = "sender@mail.server.example";
                  }
                );
              };
            testScript = builtins.readFile testFile;
          };
          
        makeTestWithProfiling =
          testFile: name: nixpkgs:
          nixpkgs.nixosTest {
            name = name;
            nodes.machine =
              { ... }:
              {
                virtualisation.memorySize = 2048;
                virtualisation.diskSize = 1024;
                imports = [ self.nixosModules.default ];
                nixpkgs.pkgs = nixpkgs;
                services.arbeitszeitapp.enable = true;
                services.arbeitszeitapp.hostName = "localhost";
                services.arbeitszeitapp.enableHttps = false;
                services.arbeitszeitapp.emailEncryptionType = null;
                services.arbeitszeitapp.emailConfigurationFile = nixpkgs.writeText "mailconfig.json" (
                  builtins.toJSON {
                    MAIL_SERVER = "mail.server.example";
                    MAIL_PORT = "465";
                    MAIL_USERNAME = "mail@mail.server.example";
                    MAIL_PASSWORD = "secret password";
                    MAIL_DEFAULT_SENDER = "sender@mail.server.example";
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
          nixpkgs-24-11 = import nixpkgs-24-11 { inherit system; };
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
          launchWebserver = makeSimpleTest ./tests/nix/launchWebserver.py;
          launchWebserverWithProfiler = makeTestWithProfiling ./tests/nix/launchWebserver.py;
          testProfiling = makeTestWithProfiling ./tests/nix/testProfiling.py;
        };
        
        pythonEnv = pkgs-unstable.python3.withPackages (
          p: with p; [
            black
            mypy
            flake8
            isort
          ]
        );
      in {
        # Packages output
        packages = {
          dockerImage = buildDockerImage;
          default = buildDockerImage;
        };
        
        # Development shell
        devShells.default = pkgs-unstable.mkShell {
          packages = [ pythonEnv pkgs-unstable.nixfmt-rfc-style pkgs-unstable.gh ];
        };
        
        # Checks (tests)
        checks = makeTestMatrix testCases;
      }
    ) // {
      # System-independent outputs
      nixosModules.default = import modules/default.nix {
        overlay = arbeitszeitapp.overlays.default;
      };
    };
}
