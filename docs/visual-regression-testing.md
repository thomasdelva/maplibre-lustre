# Visual regression testing for maps

Notes behind `test/maplibre_screenshot_test.gleam` — why screenshot-testing a
live map is normally flaky, and the specific choices that make these tests
hermetic and deterministic instead. Sources are listed at the end.

## The problem

A web map is one of the most hostile things to put under a pixel-diff. Three
properties fight you:

1. **Asynchronous tile loading.** A real basemap streams vector/raster tiles
   from a CDN after the page loads. A naive "load the page, screenshot it"
   captures a half-loaded (or empty) map, and the result depends on network
   timing. Worse, the tiles themselves are **served content that changes over
   time** — the basemap provider updates roads, labels, colours — so a baseline
   pinned to live tiles rots even when your code never changed.
2. **Non-deterministic WebGL.** MapLibre renders the basemap through WebGL.
   GPU/driver/OS differences mean the same draw calls produce subtly different
   pixels on different machines (and headless CI usually has *no* GPU at all).
3. **Capturing at the wrong moment.** Even with everything available locally,
   the map needs a frame or two — and an `idle`/`load` event — before it has
   drawn anything. A first-paint snapshot catches an empty container.

## What the ecosystem does

The recurring best practices across visual-regression tooling and MapLibre's own
render-test suite:

- **Wait for a stable state, not first paint.** MapLibre's render tests apply a
  sequence of *wait / idle* steps before querying, and the library forces
  `fadeDuration: 0` until the first `idle` so tile fade-in can't be caught
  mid-transition. General VRT guidance says the same: wait for `networkidle` or
  an explicit ready signal, and **disable animations**.
- **Make rendering deterministic by removing the GPU from the equation.** Render
  WebGL through a **software rasteriser** (SwiftShader). It is deterministic for
  a given browser *build*, which is what makes a committed WebGL baseline
  reproducible. Note: since **Chrome 137** the automatic SwiftShader fallback was
  removed, so you must ask for it explicitly (`--use-gl=angle
  --use-angle=swiftshader --enable-unsafe-swiftshader`).
- **Pin everything that affects pixels.** Device scale factor
  (`--force-device-scale-factor=1`), viewport size, the Chrome version, and a
  per-platform baseline (rendering differs across rasterisation stacks). Keep
  fixtures **free of text** where possible — font rendering is the other large
  cross-machine variable.
- **Control the data.** Mock/stub third-party and network content; use fixtures
  rather than live sources so a run is hermetic and reproducible.
- **Loosen the per-pixel tolerance a little.** Antialiasing on shape edges
  produces sub-pixel differences that are not regressions; a small threshold (and
  odiff's `--antialiasing`) absorbs them without hiding real changes.

## How these tests apply that

| Risk | Mitigation here |
| --- | --- |
| Async tiles / network / drift | The map's `style_url` is a **tile-less, background-only** style fixture (`test/fixtures/style.fixture.json`). Nothing is fetched, so there is nothing to load late or to drift. The basemap is a flat colour. |
| What is actually under test | MapLibre **markers are HTML/DOM overlays, not WebGL**. On a flat basemap they render crisply, and placing them at the right screen position is exactly the wrapper's job — so the diff is meaningful even without real tiles. |
| Non-deterministic WebGL | `screenshot.with_webgl` renders through ANGLE/SwiftShader. Verified byte-identical across repeated local runs. |
| Capturing too early | `screenshot.with_settle(ms:)` gives Chrome a virtual-time budget so timers/`rAF`/the style load drain and the map reaches `load` (placing its markers) before the frame is grabbed. |
| Cross-machine pixels | Per-platform baselines (`*.linux.png`); CI pins `chrome-version`; a small `threshold` + odiff `--antialiasing` for sub-pixel edges; fixtures are solid shapes with **no text**. |

The one residual non-determinism is the **Chrome build**: a baseline rendered
with one Chromium build can differ slightly from another at the same version
number (e.g. Playwright's Chromium vs Chrome-for-Testing). That is why the
baseline is pinned to a Chrome version in CI and why intentional or
environment-driven changes are accepted explicitly (`SCREENSHOT_ACCEPT=true`, or
the `accept-screenshots` PR label) rather than silently overwritten.

## A note on the harness

`gleam_screenshots` captures a `file://` page. Loading a real custom element that
way needs two things beyond a static snapshot, both provided by the opt-in flags
above: software WebGL, and `--allow-file-access-from-files` (Chrome blocks
`file://` **ES-module** imports under the opaque `null` origin, which a bundled
web component needs to import its own compiled modules). The element's `scene` is
a DOM *property*, so it cannot travel in serialised HTML — the test emits it as a
`<script type="application/json">` blob that the harness page reads back onto the
element after it upgrades.

## Sources

- MapLibre GL JS render test suite —
  <https://github.com/maplibre/maplibre-gl-js/blob/main/test/README.md>
- MapLibre GL JS `Map` API (`idle`/`load` events, `fadeDuration`) —
  <https://maplibre.org/maplibre-gl-js/docs/API/classes/Map/>
- Rendering WebGL in headless Chrome without a GPU (SwiftShader; Chrome 137
  fallback removal) —
  <https://copyprogramming.com/howto/rendering-webgl-image-in-headless-chrome-without-a-gpu>
- Chromium issue: remove SwiftShader as a WebGL fallback unless explicitly
  requested — <https://issues.chromium.org/issues/40277080>
- Vitest — Visual Regression Testing (wait for stability, disable animations,
  pin DPI, threshold) —
  <https://main.vitest.dev/guide/browser/visual-regression-testing>
- BrowserStack / Percy — What is Visual Regression Testing? —
  <https://www.browserstack.com/percy/visual-regression-testing>
- odiff (per-pixel diff, `--antialiasing`, `--threshold`) —
  <https://github.com/dmtrKovalenko/odiff>
