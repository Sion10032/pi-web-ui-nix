# pi-web-ui-nix

**English** | [简体中文](README.zh-CN.md)

Nix packaging and NixOS / nix-darwin / home-manager modules for
[pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) — a browser cockpit for
AI coding agents (pi / DSH): chat, code, files, terminal and Git in one tab.

The flake provides:

- `packages.<system>.pi-web-ui` (and `.default`) — the pi-web-ui server/CLI,
  built from the GitHub source tag with pnpm (`fetchPnpmDeps` + `pnpmConfigHook`)
- `overlays.default`
- `nixosModules.default`, `darwinModules.default`, `homeManagerModules.default`
- `apps.<system>.update-dev-private-narHash`
- `devShells.<system>.default`
- `checks`: a NixOS VM test (Linux), a home-manager activation check (all
  systems), and a darwin toplevel build (darwin only)

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`,
`x86_64-darwin`.

## Usage

Add the flake to your inputs:

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";
  # or, while developing locally:
  # inputs.pi-web-ui-nix.url = "path:/absolute/path/to/pi-web-ui-nix";
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

This creates a `systemd.services.pi-web-ui` system service running as the
configured `user`.

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

This creates a `launchd` agent for the configured `user`.

### home-manager

Works on Linux and macOS (a `systemd.user` service on Linux, a `launchd`
agent on macOS):

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

There is no `user` option here — the service runs as the current user.

#### Opening the port

home-manager runs as your user and cannot manage the host firewall, so this
module has no `openFirewall` option (that option only exists on the NixOS
module). To reach the service from other machines:

1. Listen on all interfaces — the default `host` binds to loopback only:

   ```nix
   services.pi-web-ui.host = "0.0.0.0";
   ```

2. Open the configured port (`port`, default `8787`) at the **host** level:

   - On a NixOS host, either use the NixOS module with
     `services.pi-web-ui.openFirewall = true;`, or add the port yourself:

     ```nix
     networking.firewall.allowedTCPPorts = [ 8787 ];
     ```

   - On macOS, the launchd agent is reachable locally without extra config;
     if you use the application firewall, allow `pi-web-ui` when prompted.

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
$ nix run github:Sion10032/pi-web-ui-nix -- --version
```

## Development

Enter the dev shell (nodejs 22 + pnpm + nixfmt-rfc-style):

```console
$ nix develop
```

The flake's `checks` reference `home-manager` and `nix-darwin` inputs that are
**not** part of the public flake's own `inputs` — they live in
`dev/private/flake.nix`, a private dev flake that is loaded at evaluation time
via `loadPrivateFlake` (see `flake.nix`). This keeps the public input graph
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

## Upgrading to a new upstream version

1. Edit `package.nix`: change the version in the `let version = "…"` binding.

2. Regenerate `pnpm-lock.yaml` from the new tag (the script downloads the
   tag's `package.json` + `package-lock.json` and runs `pnpm import` —
   versions imported verbatim, missing integrities filled from registry
   metadata; falls back to the pinned `pnpm_12` from `nix develop` if pnpm
   is not on `PATH`):

   ```console
   $ ./dev/update-pnpm-lock.sh
   ```

3. Iterate the two hashes the usual way (`nix build .#pi-web-ui -L`, copy
   each `got: sha256-…` from the mismatch errors back into `package.nix`):
   first `src`, then `pnpmDeps.hash`.

4. If the build fails with `ERR_PNPM_IGNORED_BUILDS`, copy the package names
   from the error into the `allowBuilds` map written by `postPatch` in
   `package.nix`.

5. Verify: `nix run .# -- --version` should print the new version, and
   `nix flake check -L` should still pass (it rebuilds the NixOS VM test and
   the home-manager activation check).

## Troubleshooting

### Why pnpm instead of npm (upstream shrinkwrap issue)

`@earendil-works/pi-coding-agent` publishes a tarball with an embedded
`npm-shrinkwrap.json` in which five `@earendil-works/*` dependencies have a
`resolved` URL but no `integrity` field. npm inherits a shrinkwrapped
dependency subtree verbatim — including the missing integrities — so every
`npm install` (fresh resolution included) reproduces the gap, and nixpkgs'
`fetchNpmDeps` refuses to build it. pnpm does not honour dependency-embedded
shrinkwraps, and `pnpm import` converts upstream's `package-lock.json` into
`pnpm-lock.yaml` while filling the missing integrities from registry metadata
(versions preserved verbatim). If upstream ever fixes or drops that
shrinkwrap, migrating back to `buildNpmPackage` would be straightforward.

Two pnpm-specific notes baked into `package.nix`:

- `pnpm config set minimum-release-age 0` in `prePnpmInstall`: pnpm ≥ 12 by
  default rejects packages published more recently than a cutoff; this repo
  often packages day-old upstream releases pinned by a frozen, reviewed
  lockfile, so the policy is explicitly relaxed for the fetcher.
- `allowBuilds`: pnpm ≥ 11 requires explicit approval for dependency build
  scripts (`node-pty`'s node-gyp compile, esbuild, …). Note that
  `onlyBuiltDependencies` is the removed pre-v11 spelling — pnpm ≥ 11 reads
  it from config but nothing acts on it.

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

## License

[MIT](LICENSE)
