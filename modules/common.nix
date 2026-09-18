{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  # 折叠为环境变量（不含 environment 的用户扩展，那层在调用处 merge）
  piWebUiEnv =
    { cfg, home }:
    (lib.filterAttrs (_: v: v != null) {
      PI_WEB_PORT = toString cfg.port;
      PI_WEB_HOST = cfg.host;
      PI_WEB_CWD = if cfg.cwd == "~" then home else cfg.cwd;
      PI_WEB_DATA_DIR = if cfg.dataDir == "~/.local/state/pi-web-ui" then "${home}/.local/state/pi-web-ui" else cfg.dataDir;
      PI_WEB_ENGINE = cfg.engine;
      PI_CODING_AGENT_DIR = cfg.codingAgentDir;
    })
    // (
      if cfg.allowOrigins == [ ] then { } else { PI_WEB_ALLOW_ORIGINS = lib.concatStringsSep "," cfg.allowOrigins; }
    );

  piWebUiArgs = cfg: [ "--no-browser" ] ++ cfg.extraArgs;

  piWebUiOptions = {
    enable = mkEnableOption "pi-web-ui, a browser cockpit for the pi coding agent";

    package = mkOption {
      type = types.package;
      description = "The pi-web-ui package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 8787;
      description = "Listening port (PI_WEB_PORT).";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address (PI_WEB_HOST).";
    };

    cwd = mkOption {
      type = types.str;
      default = "~";
      description = "Workspace root the agent operates in; `~` is expanded to the service user's home (PI_WEB_CWD).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "~/.local/state/pi-web-ui";
      description = "Data directory; `~` prefix is expanded to the service user's home (PI_WEB_DATA_DIR).";
    };

    engine = mkOption {
      type = types.enum [ "pi" "dsh" ];
      default = "pi";
      description = "Agent engine to drive (PI_WEB_ENGINE).";
    };

    allowOrigins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra allowed CORS origins, comma-joined (PI_WEB_ALLOW_ORIGINS).";
    };

    codingAgentDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "pi config dir if not the default ~/.pi/agent (PI_CODING_AGENT_DIR).";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables for the service (escape hatch).";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra CLI arguments appended to pi-web-ui.";
    };
  };
}
