{ pkgs, overlay, system ? pkgs.system }:
let
  pkgs' = import pkgs.path { overlays = [ overlay ]; inherit system; };
  alembicFile = pkgs'.writeText "alembic.ini" ''
    [alembic]
    script_location = arbeitszeit_flask:migrations
    version_path_separator = os

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
  configFile = pkgs'.writeText "arbeitszeitapp.cfg" ''
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

    SECRET_KEY = load_or_create("/app/secret_key")
    SECURITY_PASSWORD_SALT = load_or_create("/app/secret_key")
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL", "postgresql://arbeitszeitapp:examplepassword@db/arbeitszeitapp")
    FORCE_HTTPS = False
    SERVER_NAME = os.environ.get("SERVER_NAME", "localhost")
    AUTO_MIGRATE = True
    ALEMBIC_CONFIGURATION_FILE = "/app/alembic.ini"
    MAIL_CONFIG_PATH = os.environ.get("MAIL_CONFIG_PATH", "/app/mailconfig.json")
    # Generate mail configuration on the fly
    def _generate_mail_config():
        # Check if external mail config file exists
        mail_config_path = os.environ.get("MAIL_CONFIG_PATH", "/app/mailconfig.json")
        if os.path.exists(mail_config_path):
            try:
                with open(mail_config_path) as handle:
                    return json.load(handle)
            except (json.JSONDecodeError, FileNotFoundError):
                pass
        
        # Generate configuration from environment variables
        mail_server = os.environ.get("MAIL_SERVER", "")
        if not mail_server:
            # No mail configuration provided, return empty config
            return {}
        
        return {
            "MAIL_SERVER": mail_server,
            "MAIL_PORT": os.environ.get("MAIL_PORT", "587"),
            "MAIL_USERNAME": os.environ.get("MAIL_USERNAME", ""),
            "MAIL_PASSWORD": os.environ.get("MAIL_PASSWORD", ""),
            "MAIL_DEFAULT_SENDER": os.environ.get("MAIL_DEFAULT_SENDER", ""),
            "MAIL_USE_TLS": os.environ.get("MAIL_USE_TLS", "true").lower() == "true",
            "MAIL_USE_SSL": os.environ.get("MAIL_USE_SSL", "false").lower() == "true"
        }
    
    # Apply mail configuration
    mail_config = _generate_mail_config()
    if mail_config:
        MAIL_BACKEND = "flask_mail"
        MAIL_SERVER = mail_config["MAIL_SERVER"]
        MAIL_PORT = mail_config["MAIL_PORT"]
        MAIL_USERNAME = mail_config["MAIL_USERNAME"]
        MAIL_PASSWORD = mail_config["MAIL_PASSWORD"]
        MAIL_DEFAULT_SENDER = mail_config["MAIL_DEFAULT_SENDER"]
        MAIL_USE_TLS = mail_config["MAIL_USE_TLS"]
        MAIL_USE_SSL = mail_config["MAIL_USE_SSL"]
    # Generate Flask-profiler configuration on the fly
    def _generate_profiler_config():
        # Check if external profiling config file exists
        profiling_config_path = os.environ.get("PROFILING_CONFIG_PATH", "/app/profiling.json")
        if os.path.exists(profiling_config_path):
            try:
                with open(profiling_config_path) as handle:
                    return json.load(handle)
            except (json.JSONDecodeError, FileNotFoundError):
                pass
        
        # Generate default configuration
        return {
            "enabled": os.environ.get("PROFILING_ENABLED", "false").lower() == "true",
            "storage": {
                "engine": "sqlite"
            },
            "basicAuth": {
                "enabled": os.environ.get("PROFILING_AUTH_ENABLED", "false").lower() == "true",
                "username": os.environ.get("PROFILING_USERNAME", ""),
                "password": os.environ.get("PROFILING_PASSWORD", "")
            },
            "ignore": [
                "^/static/.*",
                "^/favicon.ico$",
                "^/health$"
            ],
            "endpointRoot": os.environ.get("PROFILING_ENDPOINT", "profiling")
        }
    
    FLASK_PROFILER = _generate_profiler_config()
  '';
  manageCommand = pkgs'.writeShellApplication {
    name = "arbeitszeitapp-manage";
    runtimeInputs = [
      (pkgs'.python3.withPackages (p: [
        p.arbeitszeitapp
        p.psycopg2
        p.flask
        p.flask-profiler
      ]))
    ];
    text = ''
      cd /app
      FLASK_APP=arbeitszeit_flask.wsgi:app \
          MPLCONFIGDIR=/app \
          ARBEITSZEITAPP_CONFIGURATION_PATH=/app/arbeitszeitapp.cfg \
          flask "$@"
    '';
  };
  alembicCommand = pkgs'.writeShellApplication {
    name = "alembic-command";
    runtimeInputs = [
      (pkgs'.python3.withPackages (p: [
        p.alembic
        p.psycopg2
        p.arbeitszeitapp
      ]))
    ];
    text = ''
      ARBEITSZEITAPP_DATABASE_URI=postgresql:///arbeitszeitapp ALEMBIC_CONFIG=/app/alembic.ini alembic "$@"
    '';
};
in
pkgs'.dockerTools.buildImage {
  name = "arbeitszeitapp";
  tag = "latest";
  config = {
    Cmd = [ "python" "-m" "flask" "run" "--host=0.0.0.0" "--port=5000" ];
    WorkingDir = "/app";
    Env = [
      "FLASK_APP=arbeitszeit_flask.wsgi:app"
      "FLASK_DEBUG=1"
      "ARBEITSZEITAPP_CONFIGURATION_PATH=/app/arbeitszeitapp.cfg"
      "MPLCONFIGDIR=/app"
      "MAIL_CONFIG_PATH=/app/mailconfig.json"
      "PROFILING_CONFIG_PATH=/app/profiling.json"
    ];
    ExposedPorts = { "5000/tcp" = {}; };
    users = [
      {
        name = "arbeitszeitapp";
        uid = 1000;
        gid = 1000;
        home = "/app";
      }
    ];
    groups = [
      {
        name = "arbeitszeitapp";
        gid = 1000;
      }
    ];
  };
  copyToRoot = pkgs'.buildEnv {
    name = "arbeitszeitapp-rootfs";
    paths = [
      (pkgs'.python3.withPackages (p: [
        p.arbeitszeitapp
        p.psycopg2
        p.flask
        p.flask-profiler
        p.alembic
      ]))
      pkgs'.coreutils
      pkgs'.curl  # Add curl for healthchecks
      manageCommand
      alembicCommand
      (pkgs'.runCommand "arbeitszeitapp-cfg" {} ''
        mkdir -p $out/app
        cp ${configFile} $out/app/arbeitszeitapp.cfg
        cp ${alembicFile} $out/app/alembic.ini
      '')
    ];
  };
}
