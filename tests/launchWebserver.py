machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("postgresql.service")
machine.wait_for_unit("nginx.service")
machine.wait_for_unit("uwsgi.service")
machine.wait_for_open_port(80)
# The first connection takes a long time since it must build font
# cache and run db migrations
assert "Workers Control" in machine.succeed("curl -vLf localhost/")
assert "Workers Control" in machine.succeed("curl -vLf localhost/login-member")
machine.succeed("curl -vLf localhost/static/main.js")

# Text responses must be gzip compressed by nginx
for path in ["/", "/static/bulma.css", "/static/main.js"]:
    headers = machine.succeed(
        f"curl -sSfL -H 'Accept-Encoding: gzip' -o /dev/null -D - localhost{path}"
    )
    assert "content-encoding: gzip" in headers.lower(), headers
machine.succeed("sudo -u arbeitszeitapp workers-control-manage db upgrade head")

# Check if service still works after restarting
machine.succeed("systemctl restart uwsgi.service")
machine.wait_for_unit("uwsgi.service")
assert "Workers Control" in machine.succeed("curl -vLf localhost/")

machine.wait_for_unit("workers-control-email-worker.service")
machine.succeed("systemctl is-active workers-control-email-worker.service")
