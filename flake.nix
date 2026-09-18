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
      loadPrivateFlake = path:
        let
          flakeHash = builtins.readFile "${toString path}.narHash";
          flakePath = "path:${toString path}?narHash=${flakeHash}";
        in
        builtins.getFlake (builtins.unsafeDiscardStringContext flakePath);

      privateInputs = (loadPrivateFlake ./dev/private).inputs;
    in
    {
      overlays.default = final: prev: {
        pi-web-ui = final.callPackage ./package.nix { };
      };

      apps = eachSystem ({ pkgs, ... }: {
        update-dev-private-narHash = {
          type = "app";
          program = "${pkgs.writeShellScript "update-dev-private-narHash" ''
            nix flake lock ./dev/private
            nix hash path ./dev/private | tr -d '\n' > ./dev/private.narHash
          ''}";
        };
      });

      devShells = eachSystem ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs_22
            nixfmt-rfc-style
          ];
        };
      });

      packages = eachSystem ({ pkgs, system, ... }: {
        pi-web-ui = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.pi-web-ui;
      });
    };
}
