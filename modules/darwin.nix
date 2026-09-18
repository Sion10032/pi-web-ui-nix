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
  home = "/Users/${cfg.user}";
  env = piWebUiEnv { inherit cfg home; } // cfg.environment;
in
{
  options.services.pi-web-ui = piWebUiOptions // {
    user = lib.mkOption {
      type = lib.types.str;
      description = "macOS user to run the LaunchAgent for; used to expand `~` in cwd/dataDir.";
    };
  };

  config = lib.mkIf cfg.enable {
    # NOTE: this nix-darwin (26.11/unstable) has no `launchd.agents.<name>.enable`
    # or freeform `.config`; plist keys go under `.serviceConfig` instead.
    launchd.agents.pi-web-ui = {
      serviceConfig = {
        ProgramArguments = [ "${cfg.package}/bin/pi-web-ui" ] ++ piWebUiArgs cfg;
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = home;
        EnvironmentVariables = env;
        StandardOutPath = "${home}/.local/state/pi-web-ui/launchd.log";
        StandardErrorPath = "${home}/.local/state/pi-web-ui/launchd.err";
      };
    };
  };
}
