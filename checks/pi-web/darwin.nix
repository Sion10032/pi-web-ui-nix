{ self, ... }:
{
  imports = [ self.darwinModules.pi-web ];

  # nix-darwin unstable asserts this option must be set.
  system.stateVersion = 7;

  services.pi-web = {
    enable = true;
    user = "alice";
    port = 30141;
  };
}
