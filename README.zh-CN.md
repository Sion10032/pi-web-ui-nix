# pi-web-ui-nix

[English](README.md) | **简体中文**

[pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) 的 Nix 打包与
NixOS / nix-darwin / home-manager 模块 —— pi-web-ui 是 AI 编程代理（pi / DSH）
的浏览器驾驶舱：聊天、代码、文件、终端与 Git 集于一页。

本 flake 提供：

- `packages.<system>.pi-web-ui`（及 `.default`）—— pi-web-ui 的 server/CLI，
  以 pnpm 从 GitHub 源码 tag 构建（`fetchPnpmDeps` + `pnpmConfigHook`）
- `overlays.default`
- `nixosModules.default`、`darwinModules.default`、`homeManagerModules.default`
- `apps.<system>.update-dev-private-narHash`
- `devShells.<system>.default`
- `checks`：NixOS VM 测试（Linux）、home-manager activation 检查（全系统）、
  darwin toplevel 构建（仅 darwin）

支持的系统：`x86_64-linux`、`aarch64-linux`、`aarch64-darwin`、
`x86_64-darwin`。

## 用法

将本 flake 加入 inputs：

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";
  # 或本地开发时：
  # inputs.pi-web-ui-nix.url = "path:/绝对路径/pi-web-ui-nix";
}
```

### NixOS

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nixpkgs, pi-web-ui-nix }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        pi-web-ui-nix.nixosModules.default
        {
          services.pi-web-ui = {
            enable = true;
            user = "sion";
          };
        }
      ];
    };
  };
}
```

这会创建一个以指定 `user` 运行的 `systemd.services.pi-web-ui` 系统服务。

### nix-darwin

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nix-darwin, pi-web-ui-nix }: {
    darwinConfigurations.myhost = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        pi-web-ui-nix.darwinModules.default
        {
          services.pi-web-ui = {
            enable = true;
            user = "sion";
          };
        }
      ];
    };
  };
}
```

这会为指定 `user` 创建一个 `launchd` agent。

### home-manager

Linux 与 macOS 均可用（Linux 为 `systemd.user` 服务，macOS 为 `launchd`
agent）：

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nixpkgs, home-manager, pi-web-ui-nix }: {
    homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        pi-web-ui-nix.homeManagerModules.default
        {
          services.pi-web-ui.enable = true;
        }
      ];
    };
  };
}
```

这里没有 `user` 选项 —— 服务以当前用户身份运行。

#### 开放端口

home-manager 以用户身份运行，管不了主机防火墙，因此本模块没有
`openFirewall` 选项（该选项只存在于 NixOS 模块）。若要让其他机器访问服务：

1. 监听所有网卡 —— 默认 `host` 只绑定回环地址：

   ```nix
   services.pi-web-ui.host = "0.0.0.0";
   ```

2. 在**主机**层面开放所配置的端口（`port`，默认 `8787`）：

   - NixOS 主机上，要么直接用 NixOS 模块并开启
     `services.pi-web-ui.openFirewall = true;`，要么自行放行端口：

     ```nix
     networking.firewall.allowedTCPPorts = [ 8787 ];
     ```

   - macOS 上 launchd agent 本机可直接访问；若启用了应用防火墙，
     按提示放行 `pi-web-ui` 即可。

## 选项

通用选项（三个模块均有；前缀为 `services.pi-web-ui.`）：

| 名称 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enable` | bool | `false` | 是否启用 pi-web-ui。 |
| `package` | package | *(由 wrapper 模块注入)* | 使用的 pi-web-ui 包。 |
| `port` | port | `8787` | 监听端口（`PI_WEB_PORT`）。 |
| `host` | str | `"127.0.0.1"` | 绑定地址（`PI_WEB_HOST`）。 |
| `cwd` | str | `"~"` | 代理的工作区根目录；`~` 展开为服务用户的 home（`PI_WEB_CWD`）。 |
| `dataDir` | str | `"~/.local/state/pi-web-ui"` | 数据目录；`~` 前缀展开为服务用户的 home（`PI_WEB_DATA_DIR`）。 |
| `engine` | enum `["pi" "dsh"]` | `"pi"` | 驱动的代理引擎（`PI_WEB_ENGINE`）。 |
| `allowOrigins` | listOf str | `[]` | 额外允许的 CORS 来源，逗号拼接（`PI_WEB_ALLOW_ORIGINS`）。 |
| `codingAgentDir` | nullOr str | `null` | pi 配置目录，非默认 `~/.pi/agent` 时指定（`PI_CODING_AGENT_DIR`）。 |
| `environment` | attrsOf str | `{}` | 服务的额外环境变量（逃生口）。 |
| `extraArgs` | listOf str | `[]` | 追加到 pi-web-ui 的额外 CLI 参数（服务始终传入 `--no-browser`）。 |

仅 NixOS 的选项（`modules/nixos.nix`）：

| 名称 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `user` | str | *（必填，无默认值）* | 运行 pi-web-ui 的用户。需对其项目文件与 `~/.pi/agent` 有读写权限。 |
| `openFirewall` | bool | `false` | 为所配置的端口开放防火墙。 |

仅 darwin 的选项（`modules/darwin.nix`）：

| 名称 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `user` | str | *（必填，无默认值）* | 运行 LaunchAgent 的 macOS 用户；用于展开 `cwd`/`dataDir` 中的 `~`。 |

home-manager 没有 `user` 选项 —— 服务以当前用户身份运行。

## 直接运行

```console
$ nix run github:Sion10032/pi-web-ui-nix -- --version
```

## 开发

进入开发 shell（nodejs 22 + pnpm + nixfmt-rfc-style）：

```console
$ nix develop
```

本 flake 的 `checks` 引用了 `home-manager` 与 `nix-darwin`，它们**不是**
公共 flake 自身的 `inputs` —— 而是放在 `dev/private/flake.nix` 这个私有
dev flake 里，求值时经 `loadPrivateFlake` 加载（见 `flake.nix`）。这样公共
input 图保持最小：拉取 `github:Sion10032/pi-web-ui-nix` 的用户不会下载和
求值这些仅测试用的 input，同时 `nix flake check` 仍会用真实的
home-manager / nix-darwin 检验各模块。[sops-nix](https://github.com/Mic92/sops-nix)
也采用同一模式（见其 `dev/private`）。

由于对 `path:` 来源使用 `builtins.getFlake` 需要固定的内容哈希，私有
flake 的路径通过 `dev/private.narHash` 锁定。修改 `dev/private/flake.nix`
或其 lockfile 后，刷新该锁定：

```console
$ nix run .#update-dev-private-narHash
```

## 升级到新上游版本

1. 编辑 `package.nix`：修改 `let version = "…";` 绑定中的版本号。

2. 从新 tag 重新生成 `pnpm-lock.yaml`（脚本会下载该 tag 的 `package.json`
   与 `package-lock.json` 并执行 `pnpm import` —— 版本忠实保留，缺失的
   integrity 由 registry 元数据补齐；PATH 里没有 pnpm 时自动回退到
   `nix develop` 中 pin 住的 `pnpm_12`）：

   ```console
   $ ./dev/update-pnpm-lock.sh
   ```

3. 按惯例迭代两个 hash（`nix build .#pi-web-ui -L`，把 mismatch 报错里的
   `got: sha256-…` 逐个抄回 `package.nix`）：先 `src`，后 `pnpmDeps.hash`。

4. 若构建报 `ERR_PNPM_IGNORED_BUILDS`，把报错列出的包名加入
   `package.nix` 中 `postPatch` 写入的 `allowBuilds` 映射。

5. 验证：`nix run .# -- --version` 应输出新版本号，`nix flake check -L`
   应仍然通过（它会重建 NixOS VM 测试与 home-manager activation 检查）。

## 故障排查

### 为什么用 pnpm 而不是 npm（上游 shrinkwrap 问题）

`@earendil-works/pi-coding-agent` 发布的 tarball 内嵌了一份
`npm-shrinkwrap.json`，其中 5 个 `@earendil-works/*` 依赖有 `resolved`
URL 却没有 `integrity` 字段。npm 对带 shrinkwrap 的依赖子树会原样继承 ——
包括缺失的 integrity —— 因此任何 `npm install`（包括全新解析）都会复现
这个缺口，nixpkgs 的 `fetchNpmDeps` 也因此拒绝构建。pnpm 不解析依赖内嵌
的 shrinkwrap，且 `pnpm import` 在把上游 `package-lock.json` 转成
`pnpm-lock.yaml` 时会用 registry 元数据补齐缺失的 integrity（版本逐字
保留）。若上游某天修复或去掉该 shrinkwrap，迁回 `buildNpmPackage` 并非
难事。

`package.nix` 里内置的两个 pnpm 相关处理：

- `prePnpmInstall` 中的 `pnpm config set minimum-release-age 0`：pnpm ≥ 12
  默认拒绝发布时间早于某阈值的包；本仓库经常打包上游发布仅一天的版本，
  且由冻结、经审的 lockfile 钉住，故对 fetcher 显式放宽该策略。
- `allowBuilds`：pnpm ≥ 11 要求显式批准依赖的构建脚本（`node-pty` 的
  node-gyp 编译、esbuild 等）。注意 `onlyBuiltDependencies` 是 v11 之前
  的旧写法，已被移除 —— pnpm ≥ 11 仍能从配置读到它，但没有任何代码
  会执行它。

### nix-darwin `launchd.agents` schema 变更（unstable / 26.11）

近期的 nix-darwin 更改了 `launchd.agents.<name>` 的选项 schema：不再有
`.enable` 选项和自由形式的 `.config`，plist 键直接放在 `.serviceConfig`
之下。本仓库的 `modules/darwin.nix` 已按新 schema 编写（见该文件内的
NOTE 注释），因此需要较新的 nix-darwin。如果你要在旧版 nix-darwin 上
覆写或移植本模块，需要改回旧写法
（`launchd.agents.<name>.enable = true; launchd.agents.<name>.config = { … }`）。

与之无关的一点：home-manager 模块（`modules/home-manager.nix`）在 macOS
上同样定义了 `launchd.agents.<name>`，但那是 **home-manager 自有**的
选项集，仍使用 `.enable` + 自由形式 `.config`，不受 nix-darwin 的
schema 变更影响。

## License

[MIT](LICENSE)
