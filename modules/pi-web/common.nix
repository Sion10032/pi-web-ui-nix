{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  # 折叠为环境变量（不含 environment 的用户扩展，那层在调用处 merge）。
  # 与 pi-web-ui 不同，这里没有 home 参数：pi-web 的选项全是原样字符串
  # （没有 `~` 展开），状态与 workspace 都不由模块决定。
  piWebEnv = cfg:
    (lib.filterAttrs (_: v: v != null) {
      PI_WEB_HOSTNAME = cfg.host;
      PI_WEB_PASSWORD = cfg.password;
      PI_WEB_APP_NAME = cfg.appName;
      PI_WEB_IDLE_TIMEOUT_MS =
        if cfg.idleTimeoutMs == null
        then null
        else toString cfg.idleTimeoutMs;
      PI_CODING_AGENT_DIR = cfg.codingAgentDir;
    })
    // (
      if cfg.allowedHosts == [ ]
      then { }
      else { PI_WEB_ALLOWED_HOSTS = lib.concatStringsSep "," cfg.allowedHosts; }
    );

  # 无人值守服务场景：一律 --no-open；端口走 CLI flag（与 pi-web-ui 的
  # --no-browser 风格一致），其余配置面走环境变量。
  piWebArgs = cfg: [ "--no-open" ] ++ [ "-p" (toString cfg.port) ] ++ cfg.extraArgs;

  piWebOptions = {
    enable = mkEnableOption "pi-web, a web UI for the pi coding agent";

    package = mkOption {
      type = types.package;
      description = "The pi-web package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 30141;
      description = "Listening port (-p).";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address (PI_WEB_HOSTNAME).";
    };

    password = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Enable the browser password login and API Basic Auth
        (PI_WEB_PASSWORD). Passed through the environment, so it is visible in
        the process environment (`systemctl show`, `ps e`) and in the Nix store
        when set here — use `environment` with a wrapper if that matters.

        Note: a read-only Nix store install cannot rotate pi-web's preview-mode
        secrets, so a client that can read this store path can bypass the
        password and Host/Origin checks with the `x-prerender-revalidate`
        header. On multi-user machines, put a reverse proxy in front instead of
        relying on this option alone.
      '';
    };

    allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra exact proxy/custom hostnames, comma-joined (PI_WEB_ALLOWED_HOSTS).
        Needed when reaching the service through a reverse proxy that forwards
        a Host the built-in loopback/LAN check does not accept.

        Note: same preview-secret caveat as `password` — a local client that
        knows the store path's preview id can skip the Host/Origin check with
        `x-prerender-revalidate`. Prefer a reverse proxy for LAN exposure.
      '';
    };

    appName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "PWA manifest name (PI_WEB_APP_NAME).";
    };

    idleTimeoutMs = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Session idle timeout in milliseconds, 0 disables (PI_WEB_IDLE_TIMEOUT_MS).";
    };

    codingAgentDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "pi config dir if not the default ~/.pi/agent (PI_CODING_AGENT_DIR).";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables for the service (escape hatch), e.g.
        `PI_WEB_SKIP_VERSION_CHECK = "1"` or `PI_WEB_SHUTDOWN_DEADLINE_MS`.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra CLI arguments appended to pi-web.";
    };
  };
}
