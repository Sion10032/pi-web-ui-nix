# pi-web-ui (Nix package + modules)

Package and NixOS / nix-darwin / home-manager modules for
[pi-web-ui](https://github.com/xing-shuyin/pi-web-ui) — a browser cockpit for AI
coding agents (pi / DSH): chat, code, files, terminal and Git in one tab.

This is one of the two packages in this repository; see the
[top-level README](../../README.md) for the overview and for
[pi-web](../pi-web), the other one.

- flake output: `packages.<system>.pi-web-ui` (also `.default`)
- modules: `nixosModules.pi-web-ui`, `homeManagerModules.pi-web-ui`,
  `darwinModules.pi-web-ui` (`.default` points here)
- build route: pnpm (`fetchPnpmDeps` + `pnpmConfigHook`) from the GitHub source
  tag; `packages/pi-web-ui/` holds `package.nix`, `pnpm-lock.yaml` and
  `pnpm-workspace.yaml`

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
        pi-web-ui-nix.nixosModules.pi-web-ui
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
configured `user` (port `8787` by default).

### nix-darwin

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nix-darwin, pi-web-ui-nix }: {
    darwinConfigurations.myhost = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        pi-web-ui-nix.darwinModules.pi-web-ui
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
        pi-web-ui-nix.homeManagerModules.pi-web-ui
        {
          services.pi-web-ui.enable = true;
        }
      ];
    };
  };
}
```

There is no `user` option here — the service runs as the current user.

Running both this package and [pi-web](../pi-web) on one machine? Import the
aggregate module (`nixosModules.all` / `homeManagerModules.all` /
`darwinModules.all`) instead of two separate ones.

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
| `allowHosts` | listOf str | `[]` | Hostname allowlist for the Host-header guard, comma-joined (`PI_WEB_ALLOW_HOSTS`) — needed behind a reverse proxy forwarding a public-domain Host. Strict mode: once non-empty, the loopback/private-LAN fallback no longer applies, so also list `localhost` / LAN addresses you still use. |
| `codingAgentDir` | nullOr str | `null` | pi config dir if not the default `~/.pi/agent` (`PI_CODING_AGENT_DIR`). |
| `environment` | attrsOf str | `{}` | Extra environment variables for the service (escape hatch). |
| `extraArgs` | listOf str | `[]` | Extra CLI arguments appended to pi-web-ui (the service always passes `--no-browser`). |

NixOS-only options (`modules/pi-web-ui/nixos.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | User to run pi-web-ui as. Needs read/write access to its project files and `~/.pi/agent`. |
| `openFirewall` | bool | `false` | Open the firewall for the configured port. |

darwin-only options (`modules/pi-web-ui/darwin.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | macOS user to run the LaunchAgent for; used to expand `~` in `cwd`/`dataDir`. |

home-manager has no `user` option — the service runs as the current user.

## Running directly

```console
$ nix run github:Sion10032/pi-web-ui-nix -- --version
$ nix run github:Sion10032/pi-web-ui-nix#pi-web-ui -- --version
```

(The bare form works because `packages.<system>.default` is `pi-web-ui`.)

## Upgrading to a new upstream version

Normally you do not do this by hand:
[`.github/workflows/update-pi-web-ui.yml`](../../.github/workflows/update-pi-web-ui.yml)
runs `dev/pi-web-ui/upgrade.sh` nightly (and on manual dispatch) and opens a PR
with the result. Run the script locally to repair a half-finished upgrade or to
test a change to it.

```console
$ ./dev/pi-web-ui/upgrade.sh
```

That single command upgrades to the latest upstream tag and does not stop
until the build is green. It:

1. detects the newest semver tag via `git ls-remote` and writes it into the
   `let version = "…"` binding in `packages/pi-web-ui/package.nix`;
2. runs `dev/pi-web-ui/update-pnpm-lock.sh` to regenerate `pnpm-lock.yaml` from
   that tag (versions imported verbatim, missing integrities filled from
   registry metadata; always inside `nix develop` so the pinned `pnpm_11`
   produces it);
3. resets both FOD hashes to `lib.fakeHash` and then iterates them from the
   `got: sha256-…` values in nix's mismatch errors (see the warm-store caveat
   below for why the reset comes first);
4. merges newly reported packages into `allowBuilds` when pnpm fails with
   `ERR_PNPM_IGNORED_BUILDS`;
5. repairs ghost imports: on `TS2307 Cannot find module 'X'`, if `X` is in the
   lockfile it adds `X`'s scope to `publicHoistPattern` and retries (a module
   that fails twice aborts instead of looping);
6. verifies the result: `nix run .# -- --version` must print the new version
   and `nix flake check -L` must pass (NixOS VM test + home-manager).

`allowBuilds` / `publicHoistPattern` live in the tracked
[`pnpm-workspace.yaml`](./pnpm-workspace.yaml), which `postPatch` copies into
upstream's source tree — the script edits that data file rather than Nix
source. Both settings are install-time only and never appear in
`pnpm-lock.yaml`; the lockfile changes only because dependency versions did.

Committing and pushing stay manual (the script prints the diff stat and never
touches git history). If a run dies mid-way, just run it again: it is
idempotent and picks up from wherever the tree is.

The workflow passes the resolved target via `UPGRADE_TARGET_VERSION` (which is
how the manual dispatch input can pick a specific tag) plus `--no-flake-check`,
leaving the full `nix flake check` to `ci.yml` on the PR.

### Doing it by hand

Useful when the script cannot repair something, or for review:

1. Edit the version in the `let version = "…"` binding in
   `packages/pi-web-ui/package.nix`.

2. Regenerate the lockfile:

   ```console
   $ ./dev/pi-web-ui/update-pnpm-lock.sh
   ```

3. Iterate the two hashes (`nix build .#pi-web-ui -L`, copy each
   `got: sha256-…` from the mismatch errors back into `package.nix`): first
   `src`, then `pnpmDeps.hash`.

   Warm-store caveat: FOD output paths are keyed by `(name, outputHash)`, so
   with an unchanged old hash nix happily reuses the stale store path instead
   of surfacing a mismatch — if the build fails with puzzling errors about a
   *previous* version (e.g. `ERR_PNPM_OUTDATED_LOCKFILE` naming deps the new
   release doesn't have), the old `src` output got silently reused. Set the
   stale hash to `lib.fakeHash` to force a refetch and get the real `got:`
   value (this is what `upgrade.sh` does up front).

4. If the build fails with `ERR_PNPM_IGNORED_BUILDS`, copy the package names
   from the error into the `allowBuilds` map in `pnpm-workspace.yaml`.

5. Verify: `nix run .# -- --version` should print the new version, and
   `nix flake check -L` should still pass.

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
shrinkwrap, migrating back to `buildNpmPackage` would be straightforward —
[pi-web](../pi-web) already takes that route.

Four pnpm-specific notes:

- the pinned `pnpm_11` (fetcher and devShell alike): the deps hash is tied
  to the pnpm version that fetched it; top-level `pnpm` rolls with unstable
  (any minor bump can change the store and break the hash), while the
  versioned alias is effectively frozen — consumers overriding this flake's
  `nixpkgs` input (`follows`) still hit the same hash. Pinning the devShell
  too keeps `pnpm import` (lockfile producer) and the fetcher (consumer) on
  the same version; `dev/pi-web-ui/update-pnpm-lock.sh` always runs inside
  `nix develop` to enforce it. When nixpkgs eventually drops `pnpm_11`,
  migrate to the then-current alias and re-hash.
- `pnpm config set minimum-release-age 0` in `prePnpmInstall`: pnpm ≥ 12 by
  default rejects packages published more recently than a cutoff; this repo
  often packages day-old upstream releases pinned by a frozen, reviewed
  lockfile, so the policy is explicitly relaxed for the fetcher.
- [`pnpm-workspace.yaml`](./pnpm-workspace.yaml) (tracked in this repo,
  copied into upstream's source tree by `postPatch`): pnpm ≥ 10 requires
  pnpm-specific settings to live in that file — the same-named key in
  `.npmrc` is silently ignored — and upstream ships no such file because it
  develops with npm. Both entries below patch over differences npm tolerates
  and pnpm does not. `dev/pi-web-ui/upgrade.sh` maintains the file
  automatically.
  - `allowBuilds`: pnpm ≥ 11 requires explicit approval for dependency build
    scripts (`node-pty`'s node-gyp compile, esbuild, …); the default
    `strictDepBuilds=true` turns unapproved scripts into a hard install
    failure, and the key names come from the `Ignored build scripts:` list in
    `ERR_PNPM_IGNORED_BUILDS`. (`onlyBuiltDependencies` is the removed pre-v11
    spelling — pnpm ≥ 11 reads it from config but nothing acts on it.)
  - `publicHoistPattern: ["@earendil-works/*"]`: since v0.105.x the server
    code imports `@earendil-works/pi-tui` directly (`server/virtual-tui.ts`,
    `server/webui-context.ts`), yet upstream's `package.json` never declares
    it — `pi-tui` is only a transitive dependency of `pi-coding-agent`.
    Upstream CI installs with npm, whose flat `node_modules` hoists transitive
    deps to the top level, so the ghost import happens to resolve there; under
    pnpm's isolated layout the root `node_modules` only links
    importer-declared packages, and `tsc` fails with TS2307. Hoisting the whole
    `@earendil-works` namespace to the public root restores npm-equivalent
    resolution semantics and also covers future ghost imports from the same
    namespace. Hoisting is an install-time layout concern, so it never appears
    in `pnpm-lock.yaml` — no `update-pnpm-lock.sh` changes needed.

### nix-darwin `launchd.agents` schema change (unstable / 26.11)

Recent nix-darwin changed the `launchd.agents.<name>` option schema: there is
no `.enable` option and no freeform `.config` anymore — the plist keys go
directly under `.serviceConfig`. This repository's
`modules/pi-web-ui/darwin.nix` already targets the new schema (see the NOTE
comment in that file), so it requires a recent nix-darwin. If you are
overriding or upstreaming this module against an older nix-darwin, you need the
old shape (`launchd.agents.<name>.enable = true;
launchd.agents.<name>.config = { … }`).

Unrelated to that change: the home-manager module
(`modules/pi-web-ui/home-manager.nix`) also defines a `launchd.agents.<name>`
on macOS, but that is **home-manager's own** option set, which still uses
`.enable` + freeform `.config` — it is unaffected by the nix-darwin schema
change.
