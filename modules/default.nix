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
    MAIL_PLUGIN_MODULE = "${cfg.emailPluginModule}"
    MAIL_PLUGIN_CLASS = "${cfg.emailPluginClass}"
    MAIL_USE_TLS = ${if cfg.emailEncryptionType == "tls" then "True" else "False"}  
    MAIL_USE_SSL = ${if cfg.emailEncryptionType == "ssl" then "True" else "False"}
  '';
  alembicFile = pkgs.writeText "alembic.ini" ''
    [alembic]
    script_location = workers_control.db:migrations
    path_separator = os
    sqlalchemy.url = ${databaseUri}

    [loggers]
    keys = root,sqlalchemy,alembic

    [handlers]
    keys = console

    [formatters]
    keys = generic

    [logger_root]
    level = WARN
    handlers = console
    qualname =

    [logger_sqlalchemy]
    level = WARN
    handlers =
    qualname = sqlalchemy.engine

    [logger_alembic]
    level = INFO
    handlers =
    qualname = alembic

    [handler_console]
    class = StreamHandler
    args = (sys.stderr,)
    level = NOTSET
    formatter = generic

    [formatter_generic]
    format = %(levelname)-5.5s [%(name)s] %(message)s
    datefmt = %H:%M:%S
  '';
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
    AUTO_MIGRATE = True
    DEFAULT_USER_TIMEZONE = "${cfg.defaultUserTimezone}"
    ${mailConfigSection}
    ${if cfg.profilingEnabled then profilingConfigSection else ""}
  '';

  alembicCommand = pkgs.writeShellApplication {
    name = "alembic-command";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: [
        p.alembic
        p.psycopg2
        p.arbeitszeitapp
      ]))
    ];
    text = ''
      ALEMBIC_CONFIG=${alembicFile} alembic "$@"
    '';
  };

  manageCommand = pkgs.writeShellApplication {
    name = "arbeitszeitapp-manage";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: [
        p.arbeitszeitapp
        p.psycopg2
        p.flask
        p.flask-profiler
      ]))
    ];
    text = ''
      cd ${stateDirectory}
      FLASK_APP=workers_control.flask.wsgi:app \
      MPLCONFIGDIR=${stateDirectory} \
      ALEMBIC_CONFIG=${alembicFile} \
      ARBEITSZEITAPP_CONFIGURATION_PATH=${configFile} \
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
    emailPluginModule = lib.mkOption {
      type = lib.types.str;
      description = ''
        This option must be a python module path to the email plugin to be used.
        By default flask-mail is used. Other plugins can be found in the
        ``src/workers_control/flask/mail_service`` directory.
      '';
      default = "workers_control.flask.mail_service.flask_mail_service";
    };
    emailPluginClass = lib.mkOption {
      type = lib.types.str;
      description = ''
        This option must be the class name of the email service found under
        ``MAIL_PLUGIN_MODULE``. By default ``FlaskMailService`` is used.
      '';
      default = "FlaskMailService";
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
        null
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
  };
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ overlay ];
    environment.systemPackages = [
      manageCommand
      alembicCommand
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
            "ALEMBIC_CONFIG=${alembicFile}"
            "ARBEITSZEITAPP_CONFIGURATION_PATH=${configFile}"
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
              arbeitszeitapp
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
