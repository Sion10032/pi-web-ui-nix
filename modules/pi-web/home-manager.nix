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
  home = config.home.homeDirectory;
  env = piWebEnv cfg // cfg.environment;
in
{
  options.services.pi-web = piWebOptions;

  config =
    let
      exec = lib.concatStringsSep " " ([ "${cfg.package}/bin/pi-web" ] ++ piWebArgs cfg);
    in
    lib.mkIf cfg.enable (
      # NOTE: must not use a plain `if pkgs... then {…} else {…}` as mkIf
      # content: the module system pushes down properties by enumerating the
      # attrset structure, which would force the `pkgs` module argument during
      # the merge phase and recurse infinitely under home-manager. mkMerge +
      # mkIf keeps the structure static and the values lazy.
      lib.mkMerge [
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          launchd.agents.pi-web = {
            enable = true;
            config = {
              ProgramArguments = [ "${cfg.package}/bin/pi-web" ] ++ piWebArgs cfg;
              RunAtLoad = true;
              KeepAlive = true;
              WorkingDirectory = home;
              EnvironmentVariables = env;
              # macOS 惯例路径。注意 ~/Library/Logs/pi-web/ 这个目录不会自动
              # 存在（launchd 只创建日志文件、不创建父目录）：目录缺失时
              # launchd 写日志会失败，服务本身照常运行。需要日志时手动
              # `mkdir -p ~/Library/Logs/pi-web`。详见 modules/pi-web/darwin.nix。
              StandardOutPath = "${home}/Library/Logs/pi-web/launchd.log";
              StandardErrorPath = "${home}/Library/Logs/pi-web/launchd.err";
            };
          };
        })
        (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
          systemd.user.services.pi-web = {
            Unit = {
              Description = "pi-web — web UI for the pi coding agent";
              After = [ "network.target" ];
            };
            Install.WantedBy = [ "default.target" ];
            Service = {
              ExecStart = exec;
              # pi-web 没有独立 dataDir：workspace 就是进程 cwd
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
