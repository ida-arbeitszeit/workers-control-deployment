{
  overlay,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.workers-control;
  user = "arbeitszeitapp";
  group = "arbeitszeitapp";
  stateDirectory = "/var/lib/arbeitszeitapp";
  databaseUri = "postgresql:///${user}";
  socketDirectory = "/run/arbeitszeit";
  socketPath = "${socketDirectory}/arbeitszeit.sock";
  profilingConfigSection = ''
    def _make_profiler_config():
        path = "${cfg.profilingCredentialsFile}"
        with open(path) as handle:
            config = json.load(handle)
        return {
            "enabled": True,
            "storage": {
                "engine": "sqlite",
                "FILE": "${stateDirectory}/flask-profiler.db",
            },
            "ignore": ["^/static/.*"],
            "endpointRoot": "profiling",
            "basicAuth":{
                "enabled": True,
                "username": config['PROFILING_AUTH_USER'],
                "password": config['PROFILING_AUTH_PASSWORD'],
            },
        }
    FLASK_PROFILER = _make_profiler_config()
  '';
  mailConfigSection = ''
    path = "${cfg.emailConfigurationFile}"
    with open(path) as handle:
        mail_config = json.load(handle)
    MAIL_SERVER = mail_config["MAIL_SERVER"]
    MAIL_PORT = mail_config["MAIL_PORT"]
    MAIL_USERNAME = mail_config["MAIL_USERNAME"]
    MAIL_PASSWORD = mail_config["MAIL_PASSWORD"]
    MAIL_DEFAULT_SENDER = mail_config["MAIL_DEFAULT_SENDER"]
    MAIL_ADMIN = mail_config["MAIL_ADMIN"]
    MAIL_ENCRYPTION_TYPE = "${cfg.emailEncryptionType}"
  '';
  pythonEnv = pkgs.python3.withPackages (p: [
    p.workers-control
    p.psycopg2
    p.flask
    p.flask-profiler
    p.alembic
  ]);
  configFile = pkgs.writeText "arbeitszeitapp.cfg" ''
    import secrets
    import json
    import os

    def load_or_create(path):
        try:
            with open(path) as handle:
                result = handle.read()
        except FileNotFoundError:
            result = secrets.token_hex(50)
            with open(path, "w") as handle:
                handle.write(result)
            os.chmod(path, 0o600)
        return result

    SECRET_KEY = load_or_create("${stateDirectory}/secret_key")
    SECURITY_PASSWORD_SALT = load_or_create("${stateDirectory}/secret_key")
    SQLALCHEMY_DATABASE_URI = "${databaseUri}"
    FORCE_HTTPS = False
    SERVER_NAME = "${cfg.hostName}";
    AUTO_MIGRATE = ${if cfg.autoMigrate then "True" else "False"}
    DEFAULT_USER_TIMEZONE = "${cfg.defaultUserTimezone}"
    ${mailConfigSection}
    ${if cfg.profilingEnabled then profilingConfigSection else ""}
  '';

  manageCommand = pkgs.writeShellApplication {
    name = "arbeitszeitapp-manage";
    runtimeInputs = [ pythonEnv ];
    text = ''
      cd ${stateDirectory}
      FLASK_APP=workers_control.flask.wsgi:app \
      MPLCONFIGDIR=${stateDirectory} \
      WOCO_CONFIGURATION_PATH=${configFile} \
      flask "$@"
    '';
  };
in
{
  options.services.workers-control = {
    enable = lib.mkEnableOption "workers-control";
    enableHttps = lib.mkEnableOption "HTTPS connections to workers-control app";
    emailConfigurationFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a json file containing the mail configuration in the
        following format:

        {
          "MAIL_SERVER": "mail.server.example",
          "MAIL_PORT": "465",
          "MAIL_USERNAME": "username@mail.server.example",
          "MAIL_PASSWORD": "my secret mail password",
          "MAIL_DEFAULT_SENDER": "sender.address@mail.server.example",
          "MAIL_ADMIN": "admin.address@mail.server.example"
        }
      '';
    };
    profilingEnabled = lib.mkEnableOption "profiling for workers control app";
    profilingCredentialsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a json file containing the profiling login credentials in
        the following format:

        {
          "PROFILING_AUTH_USER": "username",
          "PROFILING_AUTH_PASSWORD": "password",
        }
      '';
      default = "/dev/null";
    };
    emailEncryptionType = lib.mkOption {
      type = lib.types.enum [
        "ssl"
        "tls"
      ];
      description = ''
        The encryption scheme that will be used when sending email.
      '';
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Hostname where the server can be reached.
      '';
      example = "my.server.example";
    };
    defaultUserTimezone = lib.mkOption {
      type = lib.types.str;
      description = ''
        The default timezone for users. This must be a valid timezone
        string as found in the tz database.
      '';
      example = "Europe/Berlin";
      default = "UTC";
    };
    autoMigrate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to run database migrations automatically. When enabled, a
        oneshot systemd service runs `arbeitszeitapp-manage db upgrade
        head` before uwsgi and the email worker start, and AUTO_MIGRATE
        is set to True in the application configuration. When disabled,
        no migrations are performed automatically; operators must run
        them via `arbeitszeitapp-manage db upgrade head`.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ overlay ];
    environment.systemPackages = [
      manageCommand
    ];
    services.postgresql = {
      enable = true;
      ensureDatabases = [ user ];
      ensureUsers = [
        {
          name = user;
          ensureDBOwnership = true;
        }
      ];
    };
    services.nginx = {
      enable = true;
      virtualHosts."${cfg.hostName}" = {
        addSSL = cfg.enableHttps;
        enableACME = cfg.enableHttps;
        locations."/".extraConfig = ''
          uwsgi_pass unix:${socketPath};
          uwsgi_read_timeout 300;
        '';
      };
    };
    services.uwsgi = {
      enable = true;
      plugins = [ "python3" ];
      capabilities = [ "CAP_NET_BIND_SERVICE" ];
      instance = {
        type = "emperor";
        vassals.arbeitszeitapp = {
          env = [
            "WOCO_CONFIGURATION_PATH=${configFile}"
            "MPLCONFIGDIR=${stateDirectory}"
          ];
          type = "normal";
          enable-threads = true;
          master = true;
          workers = 1;
          socket = "${socketPath}";
          chmod-socket = 660;
          chown-socket = "${user}:nginx";
          module = "workers_control.flask.wsgi:app";
          pythonPackages =
            self: with self; [
              workers-control
              psycopg2
              flask-profiler
            ];
          immediate-uid = user;
          need-app = true;
        };
      };
    };
    systemd.tmpfiles.rules = [
      "d ${stateDirectory} 770 ${user} ${group}"
      "d ${socketDirectory} 770 ${user} ${group}"
    ];
    systemd.services.postgresql = {
      wantedBy = [ "uwsgi.service" ];
      before = [ "uwsgi.service" ];
    };
    systemd.services.workers-control-migrate = lib.mkIf cfg.autoMigrate {
      description = "Workers Control database migrations";
      wantedBy = [
        "uwsgi.service"
        "workers-control-email-worker.service"
      ];
      before = [
        "uwsgi.service"
        "workers-control-email-worker.service"
      ];
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        Group = group;
        ExecStart = "${manageCommand}/bin/arbeitszeitapp-manage db upgrade head";
      };
    };
    systemd.services.workers-control-email-worker = {
      description = "Workers Control email sending worker";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "postgresql.service"
      ];
      requires = [ "postgresql.service" ];
      environment = {
        WOCO_CONFIGURATION_PATH = "${configFile}";
        MPLCONFIGDIR = "${stateDirectory}";
      };
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = stateDirectory;
        ExecStart = "${pythonEnv}/bin/flask --app workers_control.flask.wsgi:app send-emails";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
    users = {
      users.nginx.extraGroups = [ group ];
      users.${user} = {
        isSystemUser = true;
        home = stateDirectory;
        inherit group;
      };
      groups.${group} = { };
    };
  };
}
