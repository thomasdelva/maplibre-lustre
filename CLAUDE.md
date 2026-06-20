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

The integration seam is the `<maplibre-map>` custom element in
`src/maplibre_ffi.mjs`: `config` and `scene` arrive as JSON-string attributes,
and interactions leave as DOM `CustomEvent`s. To extend the public API, follow
the three mechanics — declarative `Scene` content, one-shot command `Effect`s,
and `on_*` observation attributes — described in the `TODO(coverage)` roadmap at
the bottom of `src/maplibre.gleam`.

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

Even better, pair the allowlist with a **setup script** (or a committed
SessionStart hook) that installs Gleam and runs `gleam deps download` for the
library and `demo/`, so each session starts with the toolchain and deps ready
instead of re-installing them.

Until then, CI is the build oracle: `.github/workflows/ci.yml` builds the
library and demo on every push (GitHub runners can reach `repo.hex.pm`).

> Reachability is **policy-dependent** and has changed over time: in some
> environments `repo.hex.pm` is reachable, and `gleam deps download` / `gleam
> build` / `gleam test` then work locally (the `repo.hex.pm` 403 above is the
> *default* Trusted list, not a hard rule). If a session can reach it, prefer
> building and running the tests locally over waiting on CI. The npm registry is
> typically reachable too, which is what makes the screenshot tests' `maplibre-gl`
> peer installable offline of any CDN.

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

## Verifying changes

- `gleam format` / `gleam format --check src demo/src` work **offline** (they
  need no package downloads) — use them to catch syntax/format errors locally
  before pushing. CI runs the same `--check`, so format first or it goes red.
- The full typecheck/build only runs in CI (it needs the blocked Hex CDN): push
  and watch `.github/workflows/ci.yml`, which builds the library and the demo
  for the JavaScript target. A green run means it compiled.
- CI checks *compilation only*, not runtime. To exercise the real map in a
  browser, push to `main` or run the **CI** workflow manually (Actions → CI →
  Run workflow) on a branch; the `publish` job then deploys the demo to the live
  Pages site.

### Visual regression tests

`test/maplibre_screenshot_test.gleam` boots the **real** `<maplibre-map>` element
in headless Chrome and pixel-diffs it against a committed baseline, using the
[`gleam_screenshots`](https://github.com/thomasdelva/gleam-screenshots) git
dev-dependency. They are hermetic (a tile-less background-only style fixture, so
no network), deterministic (SwiftShader WebGL + a settle wait), and run on every
PR via `.github/workflows/screenshots.yml` (a thin caller of the reusable
workflow). See the README's "Visual regression tests" section, and
`docs/visual-regression-testing.md` for the best-practice reasoning + sources.

To run them in a container, on top of the Gleam toolchain you also need Node
(present at `/opt/node22/bin`), a Chrome/Chromium, and the JS peers:

```sh
npm install                               # maplibre-gl + odiff + linkedom
gleam build --target javascript           # the harness page imports the built element
export CHROME_BIN=/path/to/chrome-headless-shell ODIFF_BIN=node_modules/.bin/odiff
gleam test                                # without CHROME_BIN/ODIFF_BIN they skip
# (gleam_screenshots captures by launching chrome-headless-shell with --screenshot;
#  it sizes the viewport exactly, so there's no headless letterbox band)
```

A Chromium ships with the preinstalled Playwright (look under
`/opt/pw-browsers/*/chrome-linux/chrome`). Baselines are pixel-pinned to a Chrome
**build**, so generate/accept them with the same Chrome the CI workflow pins
(`chrome-version` in the caller); accept intentional changes with
`SCREENSHOT_ACCEPT=true gleam test` or the `accept-screenshots` PR label.

## Conventions

- Keep the public surface tiny and documented (the README enumerates it).
- App asset paths in `demo/index.html` must stay **relative** (`./demo.mjs`),
  because GitHub Pages serves the demo under a sub-path.
- Marker content is arbitrary HTML/SVG injected as `innerHTML` (by design;
  note the XSS caveat in docs rather than sanitising).
- Git: commit as Claude (`git config user.email noreply@anthropic.com`); do not
  amend or reset-author commits that already exist on `origin/main`.
