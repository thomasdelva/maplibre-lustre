# CLAUDE.md

Guidance for working in this repo from a Claude Code session (including
Claude Code on the web, where the container is ephemeral and the toolchain
is not pre-installed).

## What this project is

A minimal [Lustre](https://lustre.build) (Gleam) wrapper around
[MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/). JavaScript target
only. MapLibre itself is **not** a dependency — the host page loads it from a
CDN and the FFI reads `window.maplibregl`. The live, imperative `Map` instance
never lives in the Lustre `Model`; it lives inside a `<maplibre-map>` custom
element that reconciles a declarative scene (the markers) and surfaces clicks
and camera commands. See `README.md` for the public API.

- Library source: `src/maplibre.gleam` (+ `src/maplibre_ffi.mjs`).
- Demo SPA (path-dependency consumer): `demo/`.

## Environment setup (do this first in a fresh container)

### 1. Toolchain is not pre-installed

- **Gleam**: not on `PATH`. Install a recent release (>= 1.14 is required by
  current deps; the repo was last built with **1.17.0**). x86_64 Linux:

  ```sh
  cd /tmp
  curl -fsSL -o gleam.tar.gz \
    https://github.com/gleam-lang/gleam/releases/download/v1.17.0/gleam-v1.17.0-x86_64-unknown-linux-musl.tar.gz
  tar xzf gleam.tar.gz && mv gleam /usr/local/bin/gleam
  gleam --version
  ```

- **Node**: present at `/opt/node22/bin` (`node`, `npm`). Needed to run/bundle
  the compiled `.mjs` output.

### 2. Network policy blocks the Hex package CDN

`gleam deps download` (and therefore `gleam build`) fails in this environment:

```
error: Dependency resolution failed ...
error sending request for url (https://repo.hex.pm/packages/lustre)
```

Reachability (verified):

| Host | Status | Notes |
|---|---|---|
| `repo.hex.pm` | **403 (blocked)** | Hex package registry + tarballs live here — this is what `gleam` needs |
| `hex.pm` | 200 | website/API only; not where tarballs are served |
| `github.com`, `raw.githubusercontent.com`, `codeload.github.com` | 200 | reachable |

**Recommended fix: allow `repo.hex.pm` in the environment's network policy**, so
the standard `gleam deps download` / `gleam build` work unchanged. The default
**Trusted** allowlist includes `hex.pm`/`www.hex.pm` (the website) but *not*
`repo.hex.pm`, which is the package CDN Gleam actually fetches from — hence the
403. To add it: open the environment for editing (cloud icon → gear), set
**Network access** to **Custom**, add `repo.hex.pm` (or `*.hex.pm`) under
**Allowed domains**, tick "Also include default list of common package
managers", save, and start a **new** session (the policy applies at session
creation, not mid-run). Docs:
<https://code.claude.com/docs/en/claude-code-on-the-web#network-access>.

Until then, CI is the build oracle: `.github/workflows/ci.yml` builds the
library and demo on every push (GitHub runners can reach `repo.hex.pm`).

> Note: manually vendoring the dependency tree from GitHub as path deps is
> **not** the sanctioned path — the sandbox classifier blocks fetching and
> compiling arbitrary external repos (untrusted code integration). Prefer the
> network-policy allowlist above, or have a maintainer pre-populate
> `~/.cache/gleam` / `build/packages`.

Direct dependency tree (for reference): `lustre` →
`exception, gleam_erlang, gleam_json, gleam_otp, gleam_stdlib, houdini`.

## Build & run

Once deps are available:

```sh
gleam build --target javascript            # build the library
cd demo && gleam build --target javascript # build the demo SPA
# then bundle build/dev/javascript/demo/demo.mjs (exports `main`) and serve it
# alongside demo/index.html
```

## Conventions

- Keep the public surface tiny and documented (the README enumerates it).
- App asset paths in `demo/index.html` must stay **relative** (`./demo.mjs`),
  because GitHub Pages serves the demo under a sub-path.
- Marker content is arbitrary HTML/SVG injected as `innerHTML` (by design;
  note the XSS caveat in docs rather than sanitising).
- Git: commit as Claude (`git config user.email noreply@anthropic.com`); do not
  amend or reset-author commits that already exist on `origin/main`.
</content>
</invoke>
