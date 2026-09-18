{ self, ... }:
{
  imports = [ self.darwinModules.default ];

  # nix-darwin unstable asserts this option must be set.
  system.stateVersion = 7;

  services.pi-web-ui = {
    enable = true;
    user = "alice";
    port = 8787;
  };
}
