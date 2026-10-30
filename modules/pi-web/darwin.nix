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
  home = "/Users/${cfg.user}";
  env = piWebEnv cfg // cfg.environment;
in
{
  options.services.pi-web = piWebOptions // {
    user = lib.mkOption {
      type = lib.types.str;
      description = "macOS user to run the LaunchAgent for. Its home is the service WorkingDirectory (pi-web has no separate data dir).";
    };
  };

  config = lib.mkIf cfg.enable {
    # NOTE: this nix-darwin (26.11/unstable) has no `launchd.agents.<name>.enable`
    # or freeform `.config`; plist keys go under `.serviceConfig` instead.
    #
    # 日志路径选 ~/Library/Logs/pi-web/（macOS 惯例）而不是
    # ~/.local/state/pi-web/：pi-web 没有独立 dataDir，也不像 pi-web-ui 那样
    # 运行期创建状态目录，写 ~/.local/state 只会多出一个不存在目录下的日志。
    # 目录保证手段：nix-darwin 的 launchd agent 没有 preStart 钩子，activation
    # 期也没有"以服务用户身份建目录"的惯用落点，故不预创建 —— 目录缺失时
    # launchd 只是写日志失败，服务照常运行。需要日志时手动
    # `mkdir -p ~/Library/Logs/pi-web`（README 与选项文档同样注明）。
    launchd.agents.pi-web = {
      serviceConfig = {
        ProgramArguments = [ "${cfg.package}/bin/pi-web" ] ++ piWebArgs cfg;
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = home;
        EnvironmentVariables = env;
        StandardOutPath = "${home}/Library/Logs/pi-web/launchd.log";
        StandardErrorPath = "${home}/Library/Logs/pi-web/launchd.err";
      };
    };
  };
}
