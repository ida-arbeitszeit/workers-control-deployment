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
machine.succeed("sudo -u arbeitszeitapp arbeitszeitapp-manage db upgrade head")

# Check if service still works after restarting
machine.succeed("systemctl restart uwsgi.service")
machine.wait_for_unit("uwsgi.service")
assert "Workers Control" in machine.succeed("curl -vLf localhost/")
