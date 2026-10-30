# pi-web (Nix package + modules)

Package and NixOS / nix-darwin / home-manager modules for
[pi-web](https://github.com/agegr/pi-web) — an alternative web UI for the
[pi coding agent](https://github.com/badlogic/pi-mono), built as a Next.js app.

This is one of the two packages in this repository; see the
[top-level README](../../README.md) for the overview and for
[pi-web-ui](../pi-web-ui), the other one.

- flake output: `packages.<system>.pi-web`
- modules: `nixosModules.pi-web`, `homeManagerModules.pi-web`,
  `darwinModules.pi-web`; the aggregate modules (`*.all`) import both packages
- build route: npm (`buildNpmPackage` + `fetchNpmDeps`) from the GitHub source
  tag, using the tag's own `package-lock.json` — **no lockfile is vendored**
  in this repo
- ports/state: listens on `30141` by default; no separate data directory, the
  pi agent dir (`~/.pi/agent`, or `PI_CODING_AGENT_DIR`) holds all runtime
  state and the service's `WorkingDirectory` (the user's home) is the workspace

## Usage

Add the flake to your inputs:

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";
}
```

Both packages live in this one flake; you only need `services.pi-web` (or the
aggregate module if you also run [pi-web-ui](../pi-web-ui)).

### NixOS

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

This creates a `systemd.services.pi-web` system service running as the
configured `user`.

### nix-darwin

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nix-darwin, pi-web-ui-nix }: {
    darwinConfigurations.myhost = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        pi-web-ui-nix.darwinModules.pi-web
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

This creates a `launchd` agent for the configured `user`. Note that the log
directory `~/Library/Logs/pi-web/` is **not** created automatically (launchd
creates log files, not their parent directory): without it the service still
runs, it just writes no logs. Create it once if you want them:

```console
$ mkdir -p ~/Library/Logs/pi-web
```

### home-manager

Works on Linux and macOS (a `systemd.user` service on Linux, a `launchd` agent
on macOS):

```nix
{
  inputs.pi-web-ui-nix.url = "github:Sion10032/pi-web-ui-nix";

  outputs = { self, nixpkgs, home-manager, pi-web-ui-nix }: {
    homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        pi-web-ui-nix.homeManagerModules.pi-web
        { services.pi-web.enable = true; }
      ];
    };
  };
}
```

There is no `user` option in home-manager — the service runs as the current
user. As with pi-web-ui, home-manager cannot manage the host firewall: use the
NixOS module (with `openFirewall = true`) or open the port yourself if you
change `host` away from loopback.

## Options

Common options (all three modules; prefix with `services.pi-web.`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable` | bool | `false` | Whether to enable pi-web. |
| `package` | package | *(injected by the wrapper module)* | The pi-web package to use. |
| `port` | port | `30141` | Listening port (`-p`). |
| `host` | str | `"127.0.0.1"` | Bind address (`PI_WEB_HOSTNAME`). |
| `password` | nullOr str | `null` | Enables the browser password login and API Basic Auth (`PI_WEB_PASSWORD`). Visible in the process environment / Nix store — see the caveat below. |
| `allowedHosts` | listOf str | `[]` | Extra exact proxy/custom hostnames, comma-joined (`PI_WEB_ALLOWED_HOSTS`). |
| `appName` | nullOr str | `null` | PWA manifest name (`PI_WEB_APP_NAME`). |
| `idleTimeoutMs` | nullOr int | `null` | Session idle timeout in ms, `0` disables (`PI_WEB_IDLE_TIMEOUT_MS`). |
| `codingAgentDir` | nullOr str | `null` | pi config dir if not the default `~/.pi/agent` (`PI_CODING_AGENT_DIR`). |
| `environment` | attrsOf str | `{}` | Extra environment variables (e.g. `PI_WEB_SKIP_VERSION_CHECK = "1"`, `PI_WEB_SHUTDOWN_DEADLINE_MS`). |
| `extraArgs` | listOf str | `[]` | Extra CLI arguments (the service always passes `--no-open -p <port>`). |

NixOS-only options (`modules/pi-web/nixos.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | User to run pi-web as; its home is the service `WorkingDirectory`. |
| `openFirewall` | bool | `false` | Open the firewall for the configured port. |

darwin-only options (`modules/pi-web/darwin.nix`):

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `user` | str | *(required, no default)* | macOS user to run the LaunchAgent for; its home is the `WorkingDirectory`. |

There is deliberately no `dataDir` / `cwd` / `engine` option: pi-web keeps no
state of its own (everything lives in the agent dir) and has no engine
switching.

### Hold on: preview secrets in a read-only install

`bin/pi-web.js` rotates Next.js' preview-mode secrets at startup so the
`previewModeId` baked into a published build cannot be used to bypass the proxy
(a client that knows that id plus an `x-prerender-revalidate` header skips the
`password` and Host/Origin checks). A Nix store install is read-only, so
upstream degrades gracefully with a warning and this instance keeps the
preview id from build time.

Accepted risk: this repository builds from source, so that id is generated
during this build and is not in any public tarball; only a user who can read
*this* store path knows it. That matters only on multi-user machines that
expose the port beyond loopback — there, put a reverse proxy in front instead
of relying on `password` / `allowedHosts` alone. `password` is also passed
through the environment, so it is visible via `systemctl show` / `ps e`; use
`environment` plus a wrapper if that is a problem.

## Running directly

```console
$ nix run github:Sion10032/pi-web-ui-nix#pi-web -- --version
```

## Upgrading to a new upstream version

Normally you do not do this by hand:
[`.github/workflows/update-pi-web.yml`](../../.github/workflows/update-pi-web.yml)
runs `dev/pi-web/upgrade.sh` nightly at 04:00 UTC (and on manual dispatch) and
opens a PR with the result.

```console
$ ./dev/pi-web/upgrade.sh
```

It detects the newest semver tag, writes it into the `let version = "…"`
binding in `packages/pi-web/package.nix`, resets the three fixed-output
hashes to `lib.fakeHash` (forcing a real fetch instead of silently reusing a
warm store path), iterates them from the `got: sha256-…` values in nix's
mismatch errors, then verifies with `nix run .#pi-web -- --version` and
`nix flake check -L`. There is no lockfile translation step: `fetchNpmDeps`
downloads from the tag's own `package-lock.json`.

The three hashes are:

| Attribute | What it pins |
|-----------|--------------|
| `src.sha256` | the upstream GitHub tag tarball |
| `npmDepsHash` | the `fetchNpmDeps` dependency cache |
| `notoSansMonoFonts.outputHash` | the offline copy of Google Fonts' CSS + Noto Sans Mono woff2 subsets (see below) |

### Why the font FOD exists

`app/layout.tsx` uses `next/font/google`, which downloads CSS and woff2 files
from Google at **build** time — impossible in the Nix sandbox. The package uses
Next's own offline hook, `NEXT_FONT_GOOGLE_MOCKED_RESPONSES`: one
fixed-output derivation fetches the exact CSS Google serves for
`family=Noto+Sans+Mono:wght@100..900&display=swap` plus the seven subsets it
references, and the build rewrites the `fonts.gstatic.com` URLs to store paths
before `next build`. Upstream source is not patched and the shipped fonts are
the same files a networked build would embed.

If upstream changes its font family, weight range or subsets, the build fails
with `Missing mocked response for URL: …` — update `notoFontsCssUrl` (and the
`version`/`outputHash` of that derivation) in
[`package.nix`](./package.nix) to match.

### Doing it by hand

1. Edit the version in `packages/pi-web/package.nix`, set `sha256`,
   `npmDepsHash` and `notoSansMonoFonts.outputHash` to `lib.fakeHash`.
2. Run `nix build .#pi-web -L` and copy each `got: sha256-…` back into
   `package.nix` (one round per hash).
3. Verify: `nix run .#pi-web -- --version` prints the new version and
   `nix flake check -L` still passes.

Committing and pushing stay manual.
