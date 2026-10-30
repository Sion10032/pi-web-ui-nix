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
        pi-web-ui = final.callPackage ./packages/pi-web-ui/package.nix { };
        pi-web = final.callPackage ./packages/pi-web/package.nix { };
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
            # 重新生成 pnpm-lock.yaml（pnpm import）用；仅服务 pi-web-ui 的
            # lock 转译（pi-web 走 npm，仓库内不存 lock 副本）。与 package.nix
            # 钉同一版本：lockfile 的生产者与 FOD fetcher 的消费者不能漂移
            pnpm_11
            nixfmt-rfc-style
          ];
        };
      });

      packages = eachSystem ({ pkgs, system, ... }: {
        pi-web-ui = pkgs.callPackage ./packages/pi-web-ui/package.nix { };
        pi-web = pkgs.callPackage ./packages/pi-web/package.nix { };
        default = self.packages.${system}.pi-web-ui;
      });

      checks = eachSystem ({ pkgs, system, ... }:
        let
          homeManagerActivation = checkFile:
            (privateInputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [ checkFile ];
              extraSpecialArgs = { inherit self; };
            }).activation-script;
        in
        {
          home-manager = homeManagerActivation ./checks/pi-web-ui/home-manager.nix;
          home-manager-pi-web = homeManagerActivation ./checks/pi-web/home-manager.nix;
        } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          nixos-test = pkgs.callPackage ./checks/pi-web-ui/nixos-test.nix { inherit self; };
          nixos-test-pi-web = pkgs.callPackage ./checks/pi-web/nixos-test.nix { inherit self; };
        } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          darwin =
            let
              darwinConfiguration = privateInputs.nix-darwin.lib.darwinSystem {
                modules = [
                  ./checks/pi-web-ui/darwin.nix
                  { nixpkgs.hostPlatform = system; }
                ];
                specialArgs = { inherit self; };
              };
            in
            darwinConfiguration.config.system.build.toplevel;
          darwin-pi-web =
            let
              darwinConfiguration = privateInputs.nix-darwin.lib.darwinSystem {
                modules = [
                  ./checks/pi-web/darwin.nix
                  { nixpkgs.hostPlatform = system; }
                ];
                specialArgs = { inherit self; };
              };
            in
            darwinConfiguration.config.system.build.toplevel;
        });

      nixosModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web-ui/nixos.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        pi-web = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web/nixos.nix ];
          services.pi-web.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web;
        };
        # 两包同机并存时只需 import 一个模块；副作用仅是声明了两套 options
        all = {
          imports = [
            pi-web-ui
            pi-web
          ];
        };
        default = pi-web-ui;
      };

      homeManagerModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web-ui/home-manager.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        pi-web = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web/home-manager.nix ];
          services.pi-web.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web;
        };
        all = {
          imports = [
            pi-web-ui
            pi-web
          ];
        };
        default = pi-web-ui;
      };

      darwinModules = rec {
        pi-web-ui = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web-ui/darwin.nix ];
          services.pi-web-ui.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-ui;
        };
        pi-web = { lib, pkgs, ... }: {
          imports = [ ./modules/pi-web/darwin.nix ];
          services.pi-web.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web;
        };
        all = {
          imports = [
            pi-web-ui
            pi-web
          ];
        };
        default = pi-web-ui;
      };
    };
}
