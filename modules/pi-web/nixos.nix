{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ./common.nix { inherit lib; };
  inherit (common) piWebEnv piWebArgs piWebOptions;
  cfg = config.services.pi-web;
  home = config.users.users.${cfg.user}.home;
in
{
  options.services.pi-web = piWebOptions // {
    user = lib.mkOption {
      type = lib.types.str;
      description = "User to run pi-web as. Needs read/write access to its workspace (the user's home, which is also the service WorkingDirectory) and to ~/.pi/agent.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the firewall for the configured port.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.pi-web = {
      description = "pi-web — web UI for the pi coding agent";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        # pi-web 没有独立 dataDir：workspace 就是进程 cwd，故与 pi-web-ui
        # 同款取服务用户 home
        WorkingDirectory = home;
        ExecStart = lib.concatStringsSep " " (
          [ "${cfg.package}/bin/pi-web" ] ++ piWebArgs cfg
        );
        Restart = "on-failure";
        RestartSec = 5;
      };

      environment = piWebEnv cfg // cfg.environment;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
