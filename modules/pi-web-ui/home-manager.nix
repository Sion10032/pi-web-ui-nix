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
  home = config.home.homeDirectory;
  env = piWebUiEnv { inherit cfg home; } // cfg.environment;
in
{
  options.services.pi-web-ui = piWebUiOptions;

  config =
    let
      exec = lib.concatStringsSep " " ([ "${cfg.package}/bin/pi-web-ui" ] ++ piWebUiArgs cfg);
    in
    lib.mkIf cfg.enable (
      # NOTE: must not use a plain `if pkgs... then {…} else {…}` as mkIf
      # content: the module system pushes down properties by enumerating the
      # attrset structure, which would force the `pkgs` module argument during
      # the merge phase and recurse infinitely under home-manager. mkMerge +
      # mkIf keeps the structure static and the values lazy.
      lib.mkMerge [
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          launchd.agents.pi-web-ui = {
            enable = true;
            config = {
              ProgramArguments = [ "${cfg.package}/bin/pi-web-ui" ] ++ piWebUiArgs cfg;
              RunAtLoad = true;
              KeepAlive = true;
              WorkingDirectory = home;
              EnvironmentVariables = env;
              StandardOutPath = "${home}/.local/state/pi-web-ui/launchd.log";
              StandardErrorPath = "${home}/.local/state/pi-web-ui/launchd.err";
            };
          };
        })
        (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
          systemd.user.services.pi-web-ui = {
            Unit = {
              Description = "pi-web-ui — web chat for the pi coding agent";
              After = [ "network.target" ];
            };
            Install.WantedBy = [ "default.target" ];
            Service = {
              ExecStart = exec;
              WorkingDirectory = home;
              Environment = lib.mapAttrsToList (k: v: "${k}=${v}") env;
              Restart = "on-failure";
              RestartSec = 5;
            };
          };
        })
      ]
    );
}
