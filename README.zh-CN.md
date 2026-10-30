# pi-web-ui-nix

[English](README.md) | **简体中文**

为 [pi coding agent](https://github.com/badlogic/pi-mono) 的**两个** Web UI
提供 Nix 打包与 NixOS / nix-darwin / home-manager 模块：

| | [pi-web-ui](packages/pi-web-ui) | [pi-web](packages/pi-web) |
|---|---|---|
| 上游 | [xing-shuyin/pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) | [agegr/pi-web](https://github.com/agegr/pi-web) |
| 定位 | 浏览器驾驶舱：聊天、代码、文件、终端、Git 集于一页 | pi 代理的 Next.js Web UI |
| 默认端口 | `8787` | `30141` |
| 构建路线 | pnpm（`fetchPnpmDeps`），lock 副本在仓库内，由上游 `package-lock.json` 转译 | npm（`buildNpmPackage` + `fetchNpmDeps`），直接用上游 lock，仓库内不存副本 |
| 运行期状态 | `~/.local/state/pi-web-ui`（`dataDir`）+ pi agent 目录 | 只有 pi agent 目录（`~/.pi/agent`、`PI_CODING_AGENT_DIR`），无独立 dataDir |
| 包输出 | `packages.<system>.pi-web-ui`（同时是 `.default`） | `packages.<system>.pi-web` |

两者可同机并存（默认端口不同）。想一次配置两者时 import 聚合模块
（`*.all`）即可。

支持的系统：`x86_64-linux`、`aarch64-linux`、`aarch64-darwin`。

## flake 输出

- `packages.<system>.pi-web-ui`、`.pi-web`，以及 `.default`（= `pi-web-ui`）
- `overlays.default`（同时提供两个包）
- `nixosModules.{pi-web-ui,pi-web,all,default}`，`homeManagerModules` 与
  `darwinModules` 同构；`default` 仍指 pi-web-ui
- `apps.<system>.update-dev-private-narHash`
- `devShells.<system>.default`（nodejs 22 + pnpm_11 + nixfmt-rfc-style）
- `checks`：`home-manager`、`home-manager-pi-web`（全系统）；`nixos-test`、
  `nixos-test-pi-web`（Linux）；`darwin`、`darwin-pi-web`（darwin）

## 用法

将本 flake 加入 inputs：

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";
  # 或本地开发时：
  # inputs.pi-web-ui-nix.url = "path:/绝对路径/pi-web-ui-nix";
}
```

NixOS，单个包：

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nixpkgs, pi-web-ui-nix }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        pi-web-ui-nix.nixosModules.pi-web
        {
          services.pi-web = {
            enable = true;
            user = "sion";
          };
        }
      ];
    };
  };
}
```

其余平台同构：`nix-darwin` 用 `darwinModules.*`（需 `user`），home-manager 用
`homeManagerModules.*`（无 `user`，以当前用户运行）。要同时启用两个 UI，用
`nixosModules.all`（或对应的 `*.all`）。

完整的模块选项、各包用法示例与升级/故障排查细节见各包 README：

- [packages/pi-web-ui/README.md](packages/pi-web-ui/README.md)
- [packages/pi-web/README.md](packages/pi-web/README.md)

## 直接运行

```console
$ nix run github:Sion10032/pi-web-ui-nix -- --version              # pi-web-ui
$ nix run github:Sion10032/pi-web-ui-nix#pi-web -- --version       # pi-web
```

## 开发

进入 devShell（nodejs 22 + pnpm_11 + nixfmt-rfc-style）：

```console
$ nix develop
```

`pnpm_11` 只为 pi-web-ui 的 lock 转译服务；pi-web 走 npm，仓库内没有它的 lock
副本。

flake 的 `checks` 引用了**不在**公开 flake `inputs` 里的 `home-manager` 与
`nix-darwin` 输入 —— 它们放在 `dev/private/flake.nix`，评估期通过
`loadPrivateFlake` 载入（见 `flake.nix`）。这样公开输入图保持最小：拉
`github:Sion10032/pi-web-ui-nix` 的用户不会下载或评估测试专用输入，而
`nix flake check` 仍能对着真实的 home-manager / nix-darwin 验证模块。同样的
做法见 [sops-nix](https://github.com/Mic92/sops-nix)（其 `dev/private`）。

由于对 `path:` 源调用 `builtins.getFlake` 需要固定内容 hash，私有 flake 的路径
由 `dev/private.narHash` 锁定。改动 `dev/private/flake.nix` 或其 lockfile 后刷新
该固定值：

```console
$ nix run .#update-dev-private-narHash
```

## 升级

两个包各自自动升级，一个包一个 workflow，各自驱动对应脚本（本地与 CI 共用同一
份实现）：

| 包 | 脚本 | workflow | 定时（UTC） |
|---|---|---|---|
| pi-web-ui | `dev/pi-web-ui/upgrade.sh` | `.github/workflows/update-pi-web-ui.yml` | 03:00 |
| pi-web | `dev/pi-web/upgrade.sh` | `.github/workflows/update-pi-web.yml` | 04:00 |

脚本探测上游最新 tag、改写版本号、逐轮迭代固定输出 hash 直到构建通过，然后用
`nix run`/`nix flake check` 自检；workflow 负责开 PR。细节（含手工修复中断的升级）：

- [pi-web-ui 升级流程](packages/pi-web-ui/README.md#upgrading-to-a-new-upstream-version)
- [pi-web 升级流程](packages/pi-web/README.md#upgrading-to-a-new-upstream-version)

## CI

`.github/workflows/ci.yml` 在每次 push 到 `main` 与每个 PR 上，于
`ubuntu-24.04` 和 `macos-15` 跑 `nix flake check -L`：两个 NixOS VM 测试在
Linux 跑，darwin toplevel 构建与 home-manager activation 检查在各自系统跑。两个
更新 workflow 只构建并自检自己那个包，全量检查留给 PR。

## License

[MIT](LICENSE)
