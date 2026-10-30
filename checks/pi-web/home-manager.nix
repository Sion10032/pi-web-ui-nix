{ self, ... }:
{
  imports = [ self.homeManagerModules.pi-web ];

  services.pi-web = {
    enable = true;
    port = 30141;
  };

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "25.05";
}
