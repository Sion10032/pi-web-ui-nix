# pi-web-ui-nix

**English** | [简体中文](README.zh-CN.md)

Nix packaging and NixOS / nix-darwin / home-manager modules for **two** web UIs
of the [pi coding agent](https://github.com/badlogic/pi-mono):

| | [pi-web-ui](packages/pi-web-ui) | [pi-web](packages/pi-web) |
|---|---|---|
| Upstream | [xing-shuyin/pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) | [agegr/pi-web](https://github.com/agegr/pi-web) |
| What it is | Browser cockpit: chat, code, files, terminal, Git in one tab | Next.js web UI for the pi agent |
| Default port | `8787` | `30141` |
| Build route | pnpm (`fetchPnpmDeps`), lockfile vendored + translated from upstream's `package-lock.json` | npm (`buildNpmPackage` + `fetchNpmDeps`), upstream lockfile used as-is, no vendored lock |
| Runtime state | `~/.local/state/pi-web-ui` (`dataDir`) plus the agent dir | only the pi agent dir (`~/.pi/agent`, `PI_CODING_AGENT_DIR`); no separate data dir |
| Package output | `packages.<system>.pi-web-ui` (also `.default`) | `packages.<system>.pi-web` |

Both can run on the same machine (different default ports). Import the
aggregate module (`*.all`) to configure both with a single import.

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

## Flake outputs

- `packages.<system>.pi-web-ui`, `.pi-web`, and `.default` (= `pi-web-ui`)
- `overlays.default` (adds both packages)
- `nixosModules.{pi-web-ui,pi-web,all,default}`, and the same under
  `homeManagerModules` and `darwinModules`; `default` points at pi-web-ui
- `apps.<system>.update-dev-private-narHash`
- `devShells.<system>.default` (nodejs 22 + pnpm_11 + nixfmt-rfc-style)
- `checks`: `home-manager`, `home-manager-pi-web` (all systems);
  `nixos-test`, `nixos-test-pi-web` (Linux); `darwin`, `darwin-pi-web` (darwin)

## Usage

Add the flake to your inputs:

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";
  # or, while developing locally:
  # inputs.pi-web-ui-nix.url = "path:/absolute/path/to/pi-web-ui-nix";
}
```

NixOS, one package:

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

Same shape elsewhere: `nix-darwin` uses `darwinModules.*` (plus `user`),
home-manager uses `homeManagerModules.*` (no `user`, runs as the current user).
Use `nixosModules.all` (or the matching `*.all`) when you want both UIs.

Full module options, per-package usage examples and upgrade/troubleshooting
notes live in the package READMEs:

- [packages/pi-web-ui/README.md](packages/pi-web-ui/README.md)
- [packages/pi-web/README.md](packages/pi-web/README.md)

## Running directly

```console
$ nix run github:Sion10032/pi-web-ui-nix -- --version              # pi-web-ui
$ nix run github:Sion10032/pi-web-ui-nix#pi-web -- --version       # pi-web
```

## Development

Enter the dev shell (nodejs 22 + pnpm_11 + nixfmt-rfc-style):

```console
$ nix develop
```

`pnpm_11` only exists for pi-web-ui's lockfile translation; pi-web builds with
npm and has no lockfile in this repo.

The flake's `checks` reference `home-manager` and `nix-darwin` inputs that are
**not** part of the public flake's own `inputs` — they live in
`dev/private/flake.nix`, a private dev flake loaded at evaluation time via
`loadPrivateFlake` (see `flake.nix`). This keeps the public input graph
minimal: users pulling `github:Sion10032/pi-web-ui-nix` do not fetch or evaluate
the test-only inputs, while `nix flake check` still exercises the modules
against real home-manager / nix-darwin. The same pattern is used by
[sops-nix](https://github.com/Mic92/sops-nix) (see its `dev/private`).

Because `builtins.getFlake` on a `path:` source requires a pinned content
hash, the private flake's path is locked via `dev/private.narHash`. After
editing `dev/private/flake.nix` or its lockfile, refresh the pin:

```console
$ nix run .#update-dev-private-narHash
```

## Upgrading

Both packages are bumped automatically, one workflow per package, each driving
the matching script (local and CI run the same implementation):

| Package | Script | Workflow | Schedule (UTC) |
|---|---|---|---|
| pi-web-ui | `dev/pi-web-ui/upgrade.sh` | `.github/workflows/update-pi-web-ui.yml` | 03:00 |
| pi-web | `dev/pi-web/upgrade.sh` | `.github/workflows/update-pi-web.yml` | 04:00 |

Each script detects the newest upstream tag, rewrites the version, iterates the
fixed-output hashes until the build passes, then self-checks with
`nix run`/`nix flake check`; the workflow opens the PR. Details, including how
to repair a half-finished upgrade by hand:

- [pi-web-ui upgrade flow](packages/pi-web-ui/README.md#upgrading-to-a-new-upstream-version)
- [pi-web upgrade flow](packages/pi-web/README.md#upgrading-to-a-new-upstream-version)

## CI

`.github/workflows/ci.yml` runs `nix flake check -L` on `ubuntu-24.04` and
`macos-15` for every push to `main` and every PR: the two NixOS VM tests run on
Linux, the darwin toplevel builds and the home-manager activation checks run on
their respective systems. The two update workflows only build and self-check
their package, leaving the full check to the PR.

## License

[MIT](LICENSE)
