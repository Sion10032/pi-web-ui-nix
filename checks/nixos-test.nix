{
  pkgs,
  self,
}:
pkgs.testers.nixosTest {
  name = "pi-web-ui";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ self.nixosModules.default ];

      users.users.alice = {
        isNormalUser = true;
        home = "/home/alice";
      };

      services.pi-web-ui = {
        enable = true;
        user = "alice";
        port = 8787;
        # Exercise PI_WEB_ALLOW_HOSTS strict mode (non-empty flips the guard
        # to allowlist-only): loopback must be listed explicitly to keep
        # serving, and any other Host must be rejected with 403.
        allowHosts = [
          "localhost"
          "127.0.0.1"
        ];
      };
    };

  testScript = ''
    machine.wait_for_unit("pi-web-ui.service")
    machine.wait_for_open_port(8787)
    machine.succeed("curl -sf http://127.0.0.1:8787/ | grep -qi html")
    machine.succeed("systemctl show pi-web-ui --property=User --value | grep alice")
    machine.succeed("systemctl show pi-web-ui --property=Environment | grep 'PI_WEB_ALLOW_HOSTS=localhost,127.0.0.1'")
    # Strict mode rejects any Host not on the allowlist with 403 "host not allowed".
    machine.succeed("curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' http://127.0.0.1:8787/ | grep 403")
    machine.succeed("curl -s -H 'Host: evil.example' http://127.0.0.1:8787/ | grep -q 'host not allowed'")
  '';
}
