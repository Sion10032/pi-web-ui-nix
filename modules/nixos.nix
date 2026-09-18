{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ./common.nix { inherit lib; };
  inherit (common) piWebUiEnv piWebUiArgs piWebUiOptions;
  cfg = config.services.pi-web-ui;
  home = config.users.users.${cfg.user}.home;
in
{
  options.services.pi-web-ui = piWebUiOptions // {
    user = lib.mkOption {
      type = lib.types.str;
      description = "User to run pi-web-ui as. Needs read/write access to its project files and ~/.pi/agent.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the firewall for the configured port.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.pi-web-ui = {
      description = "pi-web-ui — web chat for the pi coding agent";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        WorkingDirectory = home;
        ExecStart = lib.concatStringsSep " " (
          [ "${cfg.package}/bin/pi-web-ui" ] ++ piWebUiArgs cfg
        );
        Restart = "on-failure";
        RestartSec = 5;
      };

      environment =
        piWebUiEnv { inherit cfg home; }
        // cfg.environment;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
