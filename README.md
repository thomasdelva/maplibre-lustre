# maplibre_lustre

A minimal [Lustre](https://lustre.build) wrapper around
[MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/).

The surface is intentionally tiny. It does exactly five things:

1. **Render a basemap** into a container — no API key (works great with
   [OpenFreeMap](https://openfreemap.org) vector tiles).
2. **Show markers whose content is arbitrary HTML/SVG**, so each pin can be a
   bespoke graphic (e.g. an inline SVG).
3. **Emit a message when a marker is tapped**, to keep the map in sync with a
   text/list view.
4. **Emit a message when the map background is tapped** (with the clicked
   `LngLat`), so you can place new markers or clear a selection.
5. **Frame a set of points** with `fit_bounds` when the selection changes.

That is the whole API. There are no GeoJSON sources, style layers, clustering,
popups, or controls — by design.

## How it works

The imperative, stateful MapLibre `Map` instance **never lives in your Lustre
`Model`**. It is held in a registry inside the FFI module, keyed by container
id, and your `update` loop returns effects that reconcile it. Your model only
holds serialisable state (the selected id, the marker list, …).

This library targets **JavaScript only**, and MapLibre is loaded by the host
page from a CDN (the wrapper reads `window.maplibregl`) — so the wrapper stays
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
import maplibre.{Config, LngLat, Marker}

const map_id = "map"

type Msg {
  MapReady
  MarkerClicked(String)
  MapClicked(LngLat)
}

fn init(_args) {
  let config =
    Config(
      style_url: "https://tiles.openfreemap.org/styles/bright",
      center: LngLat(lng: -9.139, lat: 38.722),
      zoom: 12.5,
    )

  // Just create the map. `init` dispatches `MapReady` once it exists; place the
  // markers in response to that, so you never reason about effect ordering.
  #(Model(selected: None), maplibre.init(map_id, config, MapReady))
}

fn update(model, msg) {
  case msg {
    MapReady -> {
      let markers = [
        Marker(id: "belem", position: LngLat(-9.2160, 38.6916), html: "<svg>…</svg>"),
      ]
      // Place the markers, and listen for taps on the map background.
      #(model, effect.batch([
        maplibre.set_markers(map_id, markers, MarkerClicked),
        maplibre.on_map_click(map_id, MapClicked),
      ]))
    }
    MarkerClicked(id) -> #(Model(selected: Some(id)), effect.none())
    // Tap empty space to clear the selection (or drop a new marker here).
    MapClicked(_lng_lat) -> #(Model(selected: None), effect.none())
  }
}

fn view(_model) {
  // Give the container a stable id and an explicit height via CSS, and render
  // it with NO children — MapLibre injects its own canvas.
  maplibre.container(map_id, [attribute.style("height", "100%")])
}
```

`maplibre.fit_bounds(map_id, sw, ne, padding)` frames a bounding box, e.g. when
the set of points you want in view changes.

## Demo

[`demo/`](demo/) is a separate Lustre SPA that consumes this library via a path
dependency and exercises the whole surface: an OpenFreeMap basemap, four Lisbon
pins (one rendered as a two-colour pie), tap-to-select updating an on-screen
label, an "Add pin" mode that drops new markers where you tap, tap-empty-space
to clear the selection, and a "Fit all" button. It is deployed to GitHub Pages
by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml).

### Previews

Every branch is built and published to the `gh-pages` branch: `main` lands at
the site root, and any other branch lands under `previews/<branch>/`. So a
branch named `foo` is browsable at
`https://thomasdelva.github.io/maplibre-lustre/previews/foo/` before it is
merged — handy for reviewing on a phone. (This requires the repo's Pages
**Source** to be set to "Deploy from a branch" → `gh-pages` → `/` root.)

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

## Licence

Apache-2.0. See [LICENCE](LICENCE).
