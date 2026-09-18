{ self, ... }:
{
  imports = [ self.homeManagerModules.default ];

  services.pi-web-ui = {
    enable = true;
    port = 8787;
  };

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "25.05";
}
