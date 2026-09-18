{
  description = "Nix packaging and NixOS/darwin/home-manager modules for pi-web-ui";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      eachSystem = f:
        builtins.listToAttrs (
          builtins.map
            (system: {
              name = system;
              value = f {
                pkgs = nixpkgs.legacyPackages.${system};
                inherit system;
              };
            })
            systems
        );
    in
    {
      overlays.default = final: prev: {
        pi-web-ui = final.callPackage ./package.nix { };
      };

      packages = eachSystem ({ pkgs, system, ... }: {
        pi-web-ui = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.pi-web-ui;
      });
    };
}
