# pi-web-ui-nix

Nix packaging and NixOS / nix-darwin / home-manager modules for
[pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) — a browser cockpit for
AI coding agents (pi / DSH): chat, code, files, terminal and Git in one tab.

The flake provides:

- `packages.<system>.pi-web-ui` (and `.default`) — the `pi-web-ui` npm package
  built with `buildNpmPackage`
- `overlays.default`
- `nixosModules.default`, `darwinModules.default`, `homeManagerModules.default`
- `apps.<system>.update-dev-private-narHash`
- `devShells.<system>.default`
- `checks`: a NixOS VM test (Linux), a home-manager activation check (all
  systems), and a darwin toplevel build (darwin only)

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`,
`x86_64-darwin` — but see [Troubleshooting](#troubleshooting) regarding
`x86_64-darwin` on current nixpkgs unstable.

## Usage

Add the flake to your inputs:

```nix
{
  inputs.pi-web-ui-nix.url = "github:<owner>/pi-web-ui-nix";
  # or, while developing locally:
  # inputs.pi-web-ui-nix.url = "path:/home/sion/dev/pi-web-ui-nix";
}
```

### NixOS

```nix
{
  inputs.pi-web-ui-nix.url = "github:<owner>/pi-web-ui-nix";

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

This creates a `systemd.services.pi-web-ui` system service running as the
configured `user`.

### nix-darwin

```nix
{
  inputs.pi-web-ui-nix.url = "github:<owner>/pi-web-ui-nix";

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

This creates a `launchd` agent for the configured `user`.

### home-manager

Works on Linux and macOS (a `systemd.user` service on Linux, a `launchd`
agent on macOS):

```nix
{
  inputs.pi-web-ui-nix.url = "github:<owner>/pi-web-ui-nix";

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

There is no `user` option here — the service runs as the current user.

## Options

Common options (all three modules; prefix with `services.pi-web-ui.`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable` | bool | `false` | Whether to enable pi-web-ui. |
| `package` | package | *(injected by the wrapper module)* | The pi-web-ui package to use. |
| `port` | port | `8787` | Listening port (`PI_WEB_PORT`). |
| `host` | str | `"127.0.0.1"` | Bind address (`PI_WEB_HOST`). |
| `cwd` | str | `"~"` | Workspace root the agent operates in; `~` is expanded to the service user's home (`PI_WEB_CWD`). |
| `dataDir` | str | `"~/.local/state/pi-web-ui"` | Data directory; `~` prefix is expanded to the service user's home (`PI_WEB_DATA_DIR`). |
| `engine` | enum `["pi" "dsh"]` | `"pi"` | Agent engine to drive (`PI_WEB_ENGINE`). |
| `allowOrigins` | listOf str | `[]` | Extra allowed CORS origins, comma-joined (`PI_WEB_ALLOW_ORIGINS`). |
| `codingAgentDir` | nullOr str | `null` | pi config dir if not the default `~/.pi/agent` (`PI_CODING_AGENT_DIR`). |
| `environment` | attrsOf str | `{}` | Extra environment variables for the service (escape hatch). |
| `extraArgs` | listOf str | `[]` | Extra CLI arguments appended to pi-web-ui (the service always passes `--no-browser`). |

NixOS-only options (`modules/nixos.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | User to run pi-web-ui as. Needs read/write access to its project files and `~/.pi/agent`. |
| `openFirewall` | bool | `false` | Open the firewall for the configured port. |

darwin-only options (`modules/darwin.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | macOS user to run the LaunchAgent for; used to expand `~` in `cwd`/`dataDir`. |

home-manager has no `user` option — the service runs as the current user.

## Running directly

```console
$ nix run github:<owner>/pi-web-ui-nix -- --version
```

Substitute your GitHub owner/org — this repository has no canonical remote
published yet.

## Development

Enter the dev shell (nodejs 22 + nixfmt-rfc-style):

```console
$ nix develop
```

The flake's `checks` reference `home-manager` and `nix-darwin` inputs that are
**not** part of the public flake's own `inputs` — they live in
`dev/private/flake.nix`, a private dev flake that is loaded at evaluation time
via `loadPrivateFlake` (see `flake.nix`). This keeps the public input graph
minimal: users pulling `github:<owner>/pi-web-ui-nix` do not fetch or evaluate
the test-only inputs, while `nix flake check` still exercises the modules
against real home-manager / nix-darwin. The same pattern is used by
[sops-nix](https://github.com/Mic92/sops-nix) (see its `dev/private`).

Because `builtins.getFlake` on a `path:` source requires a pinned content
hash, the private flake's path is locked via `dev/private.narHash`. After
editing `dev/private/flake.nix` or its lockfile, refresh the pin:

```console
$ nix run .#update-dev-private-narHash
```

## Upgrading to a new upstream version

1. Edit `package.nix`: change the version in the `let version = "…"` binding
   **and** the `version = "…"` field of the derivation (both must match).
   The `let` binding feeds both the npm tarball URL and the `package-lock.json`
   URL fetched in `postPatch`.

2. Iterate the three hashes. Each of the following will fail once with a
   hash mismatch; copy the `got: sha256-…` value from the error output back
   into `package.nix`, then re-run until it builds:

   ```console
   $ nix build .#pi-web-ui -L
   ```

   Fix them in this order:

   1. `src.hash` — the npm tarball hash.
   2. The `fetchurl` hash inside `postPatch` — the GitHub `package-lock.json`
      for the new tag.
   3. `npmDepsHash` — the npm dependency closure.

3. The `postPatch` `sed` block patches `integrity` fields into upstream
   lockfile entries that are missing them (nested `@earendil-works/*`
   packages); `fetchNpmDeps` panics on non-git dependencies without integrity.
   If the new lockfile changes its missing-integrity set, update the sed
   expressions (add/remove/retarget `-e` lines) accordingly.

4. Note `makeCacheWritable = true` is required: the npm-deps cache entries
   produced by `fetch-npm-deps` have `time=0`, which npm 10 treats as stale
   and tries to re-verify; a read-only store cache then fails with
   `ENOTCACHED`.

5. Verify: `nix run .# -- --version` should print the new version, and
   `nix flake check -L` should still pass (it rebuilds the NixOS VM test and
   the home-manager activation check).

## Troubleshooting

### nix-darwin `launchd.agents` schema change (unstable / 26.11)

Recent nix-darwin changed the `launchd.agents.<name>` option schema: there is
no `.enable` option and no freeform `.config` anymore — the plist keys go
directly under `.serviceConfig`. This repository's `modules/darwin.nix`
already targets the new schema (see the NOTE comment in that file), so it
requires a recent nix-darwin. If you are overriding or upstreaming this
module against an older nix-darwin, you need the old shape
(`launchd.agents.<name>.enable = true; launchd.agents.<name>.config = { … }`).

Unrelated to that change: the home-manager module
(`modules/home-manager.nix`) also defines a `launchd.agents.<name>` on macOS,
but that is **home-manager's own** option set, which still uses
`.enable` + freeform `.config` — it is unaffected by the nix-darwin schema
change.

### x86_64-darwin dropped from nixpkgs unstable (26.11)

`nix flake check --all-systems` fails on `x86_64-darwin` with current
nixpkgs unstable, because that system was dropped there. This is a known
limitation: the flake keeps the 4-system list for `aarch64-darwin`
future-proofing. Intel Mac users must pin an older nixpkgs input (e.g.
`github:NixOS/nixpkgs/nixos-25.05` or an older unstable revision) rather
than following `nixos-unstable`. On the CI matrix, `macos-14`/`macos-15`
runners are ARM (`aarch64-darwin`) and are unaffected.
