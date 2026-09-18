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
      };
    };

  testScript = ''
    machine.wait_for_unit("pi-web-ui.service")
    machine.wait_for_open_port(8787)
    machine.succeed("curl -sf http://127.0.0.1:8787/ | grep -qi html")
    machine.succeed("systemctl show pi-web-ui --property=User --value | grep alice")
  '';
}
