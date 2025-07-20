{ pkgs, overlay, system ? pkgs.system }:
let
  pkgs' = import pkgs.path { overlays = [ overlay ]; inherit system; };
  
  uwsgi = pkgs'.uwsgi.override { plugins = [ "python3" ]; };
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
  
  # Startup script that chooses between Flask dev server and uWSGI
  startupScript = pkgs'.writeShellApplication {
    name = "arbeitszeitapp-start";
    runtimeInputs = [
      (pkgs'.python3.withPackages (p: [
        p.arbeitszeitapp
        p.psycopg2
        p.flask
        p.flask-profiler
      ]))
      uwsgi
    ];
    text = ''
      cd /app
      
      # Set default server type if not specified
      SERVER_TYPE=''${SERVER_TYPE:-flask}
      
      # Create writable state directory (similar to NixOS approach)
      STATE_DIR="/var/lib/arbeitszeitapp"
      mkdir -p "$STATE_DIR"
      chown 1000:1000 "$STATE_DIR" 2>/dev/null || true
      
      # Ensure FLASK_APP is set
      export FLASK_APP=arbeitszeit_flask.wsgi:app
      export ARBEITSZEITAPP_CONFIGURATION_PATH=/app/arbeitszeitapp.cfg
      export MPLCONFIGDIR="$STATE_DIR"
      export ARBEITSZEITAPP_STATE_DIR="$STATE_DIR"
      
      # Construct DATABASE_URL if not provided
      if [ -z "$DATABASE_URL" ] && [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_PASSWORD" ] && [ -n "$POSTGRES_DB" ]; then
        export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db/$POSTGRES_DB"
      fi
      
      # Generate runtime configuration file with correct paths (needed for both Flask and uWSGI)
      cat > /app/arbeitszeitapp.cfg << 'EOF'
# Configuration file with runtime environment variable support - runtime generated
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

SECRET_KEY = load_or_create(os.environ.get("ARBEITSZEITAPP_STATE_DIR", "/var/lib/arbeitszeitapp") + "/secret_key")
SECURITY_PASSWORD_SALT = load_or_create(os.environ.get("ARBEITSZEITAPP_STATE_DIR", "/var/lib/arbeitszeitapp") + "/secret_key")
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
        # Only show email configuration warnings during normal app startup, not during migrations
        if not os.environ.get("SUPPRESS_EMAIL_WARNINGS"):
            # Email configuration is required for core functionality
            print("WARNING: No MAIL_SERVER configured. Email functionality is required for user registration, password resets, and notifications.")
            print("Please configure MAIL_SERVER, MAIL_USERNAME, MAIL_PASSWORD, and MAIL_DEFAULT_SENDER in your environment.")
        return {}
    
    # Validate required email configuration
    mail_username = os.environ.get("MAIL_USERNAME", "")
    mail_password = os.environ.get("MAIL_PASSWORD", "")
    mail_default_sender = os.environ.get("MAIL_DEFAULT_SENDER", "")
    
    if not all([mail_username, mail_password, mail_default_sender]):
        # Only show email configuration warnings during normal app startup, not during migrations
        if not os.environ.get("SUPPRESS_EMAIL_WARNINGS"):
            print("WARNING: Incomplete email configuration detected.")
            print("Required: MAIL_SERVER, MAIL_USERNAME, MAIL_PASSWORD, MAIL_DEFAULT_SENDER")
            print("Current configuration may cause authentication and notification failures.")
    
    return {
        "MAIL_SERVER": mail_server,
        "MAIL_PORT": os.environ.get("MAIL_PORT", "587"),
        "MAIL_USERNAME": mail_username,
        "MAIL_PASSWORD": mail_password,
        "MAIL_DEFAULT_SENDER": mail_default_sender,
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
            "engine": "sqlite",
            "FILE": os.environ.get("ARBEITSZEITAPP_STATE_DIR", "/var/lib/arbeitszeitapp") + "/flask-profiler.db"
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
EOF
          
      case "$SERVER_TYPE" in
        flask|dev|development)
          echo "Starting with Flask development server..."
          exec python -m flask run --host=0.0.0.0 --port=5000
          ;;
        uwsgi|prod|production)
          echo "Starting with uWSGI production server..."
          # Set PYTHONPATH environment variable instead of using uwsgi --pythonpath
          PYTHONPATH="$(python -c 'import sys; print(":".join(sys.path))')"
          export PYTHONPATH
          # Set state directory environment variable before starting uWSGI
          export ARBEITSZEITAPP_STATE_DIR="$STATE_DIR"
          exec uwsgi --http 0.0.0.0:5000 --plugins python3 --module arbeitszeit_flask.wsgi:app --processes 4 --threads 2 --master --enable-threads --uid 1000 --gid 1000
          ;;
        *)
          echo "ERROR: Unknown SERVER_TYPE: $SERVER_TYPE"
          echo "Valid options: flask, dev, development, uwsgi, prod, production"
          exit 1
          ;;
      esac
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
      cd /app
      
      # Use the same database URL construction logic as the main application
      if [ -z "$DATABASE_URL" ] && [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_PASSWORD" ] && [ -n "$POSTGRES_DB" ]; then
        export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db/$POSTGRES_DB"
      fi
      
      # Set flag to suppress email warnings during migrations
      export SUPPRESS_EMAIL_WARNINGS=true
      
      # Set the database URI for alembic - fallback to default if not set
      export ARBEITSZEITAPP_DATABASE_URI="''${DATABASE_URL:-postgresql://arbeitszeitapp:examplepassword@db/arbeitszeitapp}"
      export ALEMBIC_CONFIG=/app/alembic.ini
      exec alembic "$@"
    '';
};
in
pkgs'.dockerTools.buildImage {
  name = "arbeitszeitapp";
  tag = "latest";
  config = {
    Cmd = [ "arbeitszeitapp-start" ];
    WorkingDir = "/app";
    Env = [
      "FLASK_APP=arbeitszeit_flask.wsgi:app"
      "FLASK_DEBUG=1"
      "ARBEITSZEITAPP_CONFIGURATION_PATH=/app/arbeitszeitapp.cfg"
      "MPLCONFIGDIR=/app"
      "MAIL_CONFIG_PATH=/app/mailconfig.json"
      "PROFILING_CONFIG_PATH=/app/profiling.json"
      "SERVER_TYPE=flask"  # Default to Flask dev server
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
      uwsgi
      pkgs'.coreutils
      pkgs'.curl  # Add curl for healthchecks
      manageCommand
      alembicCommand
      startupScript
      (pkgs'.runCommand "alembic-cfg" {} ''
        mkdir -p $out/app
        cp ${alembicFile} $out/app/alembic.ini
      '')
    ];
  };
}
