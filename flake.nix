{
  description = "Nix packaging and NixOS/darwin/home-manager modules for pi-web-ui";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
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
      inherit (nixpkgs) lib;
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
            pnpm # 重新生成 pnpm-lock.yaml（pnpm import）用
            nixfmt-rfc-style
          ];
        };
      });

      packages = eachSystem ({ pkgs, system, ... }: {
        pi-web-ui = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.pi-web-ui;
      });

      checks = eachSystem ({ pkgs, system, ... }:
        {
          home-manager =
            let
              homeConfiguration = privateInputs.home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                modules = [ ./checks/home-manager.nix ];
                extraSpecialArgs = { inherit self; };
              };
            in
            homeConfiguration.activation-script;
        } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          nixos-test = pkgs.callPackage ./checks/nixos-test.nix { inherit self; };
        } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          darwin =
            let
              darwinConfiguration = privateInputs.nix-darwin.lib.darwinSystem {
                modules = [
                  ./checks/darwin.nix
                  { nixpkgs.hostPlatform = system; }
                ];
                specialArgs = { inherit self; };
              };
            in
            darwinConfiguration.config.system.build.toplevel;
        });

      nixosModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/nixos.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        default = pi-web-ui;
      };

      homeManagerModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/home-manager.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        default = pi-web-ui;
      };

      darwinModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/darwin.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        default = pi-web-ui;
      };
    };
}
