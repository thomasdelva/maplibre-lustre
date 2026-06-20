# maplibre_lustre

A minimal [Lustre](https://lustre.build) wrapper around
[MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/).

The surface is intentionally tiny. It does exactly six things:

1. **Render a basemap** into a container — no API key (works great with
   [OpenFreeMap](https://openfreemap.org) vector tiles) — opening either
   centred on a point or fitted to a bounding box.
2. **Show markers whose content is arbitrary HTML/SVG**, so each pin can be a
   bespoke graphic (e.g. an inline SVG).
3. **Emit a message when a marker is tapped**, to keep the map in sync with a
   text/list view.
4. **Emit a message when the map background is tapped** (with the clicked
   `LngLat`), so you can place new markers or clear a selection.
5. **Frame a set of points** with `fit_bounds` when the selection changes.
6. **Report the visible bounds as the camera settles** with `on_move`, and
   serialise them (`bounds_to_json` / `bounds_from_json`) so a viewport can be
   persisted and restored — there's a tiny `maplibre/storage` helper for
   `localStorage`.

That is the whole API. There are no GeoJSON sources, style layers, clustering,
popups, or controls — by design.

## How it works

The imperative, stateful MapLibre `Map` instance **never lives in your Lustre
`Model`**. It lives inside a `<maplibre-map>` custom element. You render that
element in your `view` and hand it a declarative **`Scene`** — a pure function
of your model — and the element diffs successive scenes, adding, moving, and
removing only the markers that changed. Markers are **keyed**, so a pin keeps
its identity across renders. Your model only holds serialisable state (the
selected id, the marker list, …).

Data flows one way:

- **content** (the markers) is declared by the scene and reconciled for you;
- **camera motion** is a one-shot command effect — `fit_bounds`;
- **what happened** comes back as messages via `on_*` event attributes —
  `on_marker_click`, `on_map_click`, and `on_move` (the visible bounds as the
  camera settles).

Because the camera is never a controlled prop (`fit_bounds` is a one-shot
command, never re-asserted every render), there is no feedback loop to guard
against.

This library targets **JavaScript only**, and MapLibre is loaded by the host
page from a CDN (the element reads `window.maplibregl`) — so the wrapper stays
bundler-agnostic.

## Installing

Add it to your app's `gleam.toml` as a git dependency:

```toml
# your app's gleam.toml
[dependencies]
maplibre_lustre = { git = "https://github.com/thomasdelva/maplibre-lustre.git", ref = "v0.1.0" }
```

Your host HTML **must** include the MapLibre GL JS script **and** its CSS
before your app module (the CSS is required — without it markers and controls
render with broken positioning):

```html
<link
  href="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.css"
  rel="stylesheet"
/>
<script src="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.js"></script>
```

> Serving from GitHub Pages (or any sub-path)? Keep your app's own asset paths
> **relative** (`./app.mjs`, not `/app.mjs`), or they will 404. The CDN URLs
> above are absolute and fine.

## Usage

```gleam
import maplibre.{Centered, Config, LngLat, Marker}

const map_id = "map"

const config = Config(
  style_url: "https://tiles.openfreemap.org/styles/bright",
  view: Centered(center: LngLat(lng: -9.139, lat: 38.722), zoom: 12.5),
)

type Msg {
  MarkerClicked(String)
  MapClicked(LngLat)
}

fn init(_args) {
  // Nothing to do up front: the element creates the map when `view` renders it,
  // and the markers are part of the scene.
  #(Model(selected: None), effect.none())
}

fn update(model, msg) {
  case msg {
    MarkerClicked(id) -> #(Model(..model, selected: Some(id)), effect.none())
    // Tap empty space to clear the selection (or drop a new marker here).
    MapClicked(_lng_lat) -> #(Model(..model, selected: None), effect.none())
  }
}

fn view(model) {
  // The scene is a pure function of the model. Each marker is paired with a
  // stable key; the element diffs the scene and only touches what changed.
  let scene =
    maplibre.scene([
      #("belem", Marker(position: LngLat(-9.2160, 38.6916), html: "<svg>…</svg>")),
    ])

  // Render the element with NO children — it injects MapLibre's own canvas —
  // give it a stable id and an explicit height, and wire interactions as
  // attributes.
  maplibre.map(
    map_id,
    config,
    [
      attribute.style("height", "100%"),
      maplibre.on_marker_click(MarkerClicked),
      maplibre.on_map_click(MapClicked),
    ],
    scene,
  )
}
```

To move the camera, return a command effect from `update`, e.g.
`maplibre.fit_bounds(map_id, sw, ne, padding)` to frame a bounding box.

### Remembering the viewport

`on_move` reports the visible `Bounds` each time the camera settles. Persist
them, then **open the map `Fitted` to the saved box** on the next visit so it
appears where the user left it — instantly, with no post-load pan (the bounds
become the map's initial camera):

```gleam
import maplibre.{Centered, Config, Fitted}
import maplibre/storage

const bounds_key = "my-app:bounds"

fn init(_args) {
  // Read the saved viewport synchronously and use it as the initial view.
  let view = case storage.get(bounds_key) {
    Ok(saved) ->
      case maplibre.bounds_from_json(saved) {
        Ok(bounds) -> Fitted(bounds:, padding: 0)
        Error(_) -> default_view
      }
    Error(_) -> default_view
  }
  #(Model(config: Config(style_url:, view:), ..), effect.none())
}

fn update(model, msg) {
  case msg {
    // Persist every settled viewport.
    ViewportChanged(bounds) ->
      #(model, storage.set(bounds_key, maplibre.bounds_to_json(bounds)))
    // …
  }
}

// …and wire the observation as an attribute on the element:
//   maplibre.on_move(ViewportChanged)
```

`maplibre/storage` is a thin, defensive wrapper over `localStorage`: `get`
returns `Result(String, Nil)` and `set` / `remove` are effects. It degrades
gracefully when storage is unavailable (private mode, disabled cookies, …).

## Demo

[`demo/`](demo/) is a separate Lustre SPA that consumes this library via a path
dependency and exercises the whole surface: an OpenFreeMap basemap, four Lisbon
pins (one rendered as a two-colour pie), tap-to-select updating an on-screen
label, an "Add pin" mode that drops new markers where you tap, tap-empty-space
to clear the selection, a "Fit all" button, and viewport persistence (pan/zoom,
reload, and the map reopens where you left it). It is deployed to GitHub Pages
by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml).

### Deploys

The demo is rebuilt and deployed (via `actions/deploy-pages`) to the single live
site at `https://thomasdelva.github.io/maplibre-lustre/` on two triggers: pushes
to `main`, and manual `workflow_dispatch`. To preview a branch before merging,
run the **CI** workflow manually on it (Actions → CI → Run workflow → pick the
branch). Each deploy overwrites the previous one (the latest run wins; rapid
pushes cancel older in-flight ones), and a small badge in the bottom-left corner
shows which branch produced the current deploy.

This requires Pages **Source** = "GitHub Actions". If you dispatch from a branch
other than `main`, the `github-pages` environment must also allow deploys from
that branch (Settings → Environments → `github-pages` → Deployment branches).

To run it locally:

```sh
cd demo
gleam deps download
gleam build --target javascript
# then bundle build/dev/javascript/demo/demo.mjs (which exports `main`) with
# your bundler of choice and serve it alongside demo/index.html.
```

## Development

```sh
gleam build --target javascript   # build the library
cd demo && gleam build --target javascript   # build the demo
```

## Visual regression tests

`test/maplibre_screenshot_test.gleam` screenshots the **real** `<maplibre-map>`
element in headless Chrome and pixel-diffs it against a committed baseline with
[`gleam_screenshots`](https://github.com/thomasdelva/gleam-screenshots) (a
dev-only git dependency). It's the one end-to-end check that the element boots,
parses `config`, creates a MapLibre map, reconciles a `Scene`, and positions the
HTML markers — everything `reconcile_test` can't reach because it's pure.

Screenshotting a live map is normally flaky (async tiles, network, GPU-dependent
WebGL); these tests are hermetic and deterministic instead:

- the map's `style_url` is a **tile-less, background-only** style fixture
  (`test/fixtures/style.fixture.json`), so nothing is fetched — the basemap is a
  flat colour and the markers (HTML overlays, not WebGL) render on top;
- WebGL goes through Chrome's **SwiftShader** software rasteriser
  (`screenshot.with_webgl`), deterministic for a pinned Chrome build;
- the capture **waits for the map to settle** before grabbing the frame
  (`screenshot.with_settle`), so it never catches an empty container.

They **skip** unless a browser is configured, so plain `gleam test` still runs
the pure tests. To run them locally:

```sh
npm install                              # maplibre-gl + odiff + linkedom (peers)
gleam build --target javascript          # the harness page imports the built element
export CHROME_BIN=/path/to/chrome-headless-shell ODIFF_BIN=node_modules/.bin/odiff
gleam test
```

Baselines are committed **per platform** (`test/screenshots/*.linux.png`). When a
change is intentional, accept it with `SCREENSHOT_ACCEPT=true gleam test` locally,
or by adding the `accept-screenshots` label to the PR. CI runs these on every PR
via [`.github/workflows/screenshots.yml`](.github/workflows/screenshots.yml),
which references the reusable workflow and pins the Chrome version the baselines
were rendered with.

For the reasoning behind the hermetic, deterministic setup — and references —
see [`docs/visual-regression-testing.md`](docs/visual-regression-testing.md).

## Licence

Apache-2.0. See [LICENCE](LICENCE).
