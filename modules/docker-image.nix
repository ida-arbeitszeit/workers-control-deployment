{ pkgs }:
let
  alembicFile = pkgs.writeText "alembic.ini" ''
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

    SECRET_KEY = load_or_create("/app/secret_key")
    SECURITY_PASSWORD_SALT = load_or_create("/app/secret_key")
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL", "postgresql://arbeitszeitapp:examplepassword@db/arbeitszeitapp")
    FORCE_HTTPS = False
    SERVER_NAME = os.environ.get("SERVER_NAME", "localhost")
    AUTO_MIGRATE = True
    ALEMBIC_CONFIGURATION_FILE = "/app/alembic.ini"
    MAIL_CONFIG_PATH = os.environ.get("MAIL_CONFIG_PATH", "/app/mailconfig.json")
    PROFILING_CONFIG_PATH = os.environ.get("PROFILING_CONFIG_PATH", "/app/profiling.json")
  '';
  manageCommand = pkgs.writeShellApplication {
    name = "arbeitszeitapp-manage";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: [
        p.arbeitszeitapp
        p.psycopg2
        p.flask
        p.flask_profiler
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
      ARBEITSZEITAPP_DATABASE_URI=postgresql:///arbeitszeitapp ALEMBIC_CONFIG=/app/alembic.ini alembic "$@"
    '';
};
in
pkgs.dockerTools.buildImage {
  name = "arbeitszeitapp";
  tag = "latest";
  config = {
    Cmd = [ "uwsgi" "--socket" ":5000" "--protocol" "http" "--module" "arbeitszeit_flask.wsgi:app" "--master" "--processes" "1" "--threads" "2" ];
    WorkingDir = "/app";
    Env = [
      "FLASK_APP=arbeitszeit_flask.wsgi:app"
      "ARBEITSZEITAPP_CONFIGURATION_PATH=/app/arbeitszeitapp.cfg"
      "MPLCONFIGDIR=/app"
      "MAIL_CONFIG_PATH=/app/mailconfig.json"
      "PROFILING_CONFIG_PATH=/app/profiling.json"
    ];
    ExposedPorts = { "5000/tcp" = {}; };
    # Add a non-root user for better security
    user = "arbeitszeitapp";
  };
  contents = [
    (pkgs.python3.withPackages (p: [
      p.arbeitszeitapp
      p.psycopg2
      p.flask
      p.flask_profiler
      p.alembic
      p.uwsgi
    ]))
    pkgs.coreutils
    pkgs.curl  # Add curl for healthchecks
    manageCommand
    alembicCommand
  ];
  # Add a non-root user and group for the container
  extraCommands = ''
    mkdir -p $out/app
    cp ${configFile} $out/app/arbeitszeitapp.cfg
    cp ${alembicFile} $out/app/alembic.ini
    addgroup -g 1000 arbeitszeitapp
    adduser -D -u 1000 -G arbeitszeitapp -h /app arbeitszeitapp
    chown -R 1000:1000 $out/app
  '';
}
