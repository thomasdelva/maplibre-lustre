//// Visual-regression tests for the *real* `<maplibre-map>` custom element.
////
//// Unlike `reconcile_test`, which unit-tests the pure marker diff, these boot
//// the live element in headless Chrome and pixel-diff the result against a
//// committed baseline with [`gleam_screenshots`](https://github.com/thomasdelva/gleam-screenshots).
//// They are the only end-to-end coverage of the integration seam: the element
//// upgrading, parsing `config`, creating a MapLibre map, reconciling a `Scene`,
//// and positioning HTML markers over the basemap.
////
//// ## Why this is deterministic (and hermetic)
////
//// A live map is a hostile thing to screenshot — async tile loads, network
//// flakiness, GPU-dependent WebGL. We sidestep all three:
////
////   - **No network.** The map's `style_url` points at `test/fixtures/style.fixture.json`,
////     a tile-less *background-only* style. Nothing is fetched, so there is
////     nothing to load late or to drift over time. The basemap is a flat colour;
////     the markers (plain HTML/SVG overlays, not drawn into the WebGL canvas)
////     render crisply on top — which is exactly the wrapper's job to place.
////   - **Software WebGL.** `screenshot.with_webgl` renders through SwiftShader,
////     deterministic for a pinned Chrome build (CI pins `chrome-version`).
////   - **Wait for settle.** `screenshot.with_settle` gives Chrome a virtual-time
////     budget so the map reaches `load` and places its markers before the frame
////     is grabbed — a plain first-paint snapshot would catch an empty container.
////
//// ## Running them
////
//// Like `gleam_screenshots`' own suite, these **skip** unless `CHROME_BIN` and
//// `ODIFF_BIN` are set, so `gleam test` still runs the pure tests on a machine
//// without a browser. To run them you also need the JS peers (`npm i`) and a
//// built library for the harness page to import (`gleam build --target javascript`):
////
//// ```sh
//// npm i
//// gleam build --target javascript
//// export CHROME_BIN=/path/to/chrome-headless-shell ODIFF_BIN=node_modules/.bin/odiff
//// gleam test
//// ```
////
//// Accept an intentional change with `SCREENSHOT_ACCEPT=true gleam test` (or the
//// `accept-screenshots` PR label in CI). Baselines are committed per platform
//// (`*.linux.png`); see `README.md`.

import envoy
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import lustre/attribute
import lustre/element
import maplibre.{type Config, type Marker, Centered, Config, LngLat, Marker}
import maplibre/reconcile
import screenshot
import simplifile

const template = "test/fixtures/maplibre_template.html"

// The harness viewport. Small and fixed so the baseline PNGs stay tiny.
const size = screenshot.ScreenSize(width: 600, height: 400)

// A generous virtual-time budget: real wall-clock cost is a fraction of this,
// but it leaves ample room for the style to parse and the map to reach `load`.
const settle_ms = 12_000

// A tile-less basemap centred on the equator, so marker longitudes/latitudes
// map to stable, well-separated screen positions.
fn config() -> Config {
  Config(
    // Resolved relative to the scratch render, which the library writes next to
    // the baseline (test/screenshots/), so reach back into test/fixtures/.
    style_url: "../fixtures/style.fixture.json",
    view: Centered(center: LngLat(lng: 0.0, lat: 0.0), zoom: 2.0),
  )
}

// Distinct solid-colour pins (no text, so nothing is font-sensitive). One up in
// the north-west, one down in the south-east — the diff catches either drifting.
fn red_pin() -> String {
  "<svg width='24' height='24'><circle cx='12' cy='12' r='10' fill='#e4002b' stroke='#fff' stroke-width='2'/></svg>"
}

fn blue_pin() -> String {
  "<svg width='20' height='20'><circle cx='10' cy='10' r='8' fill='#0072ce' stroke='#fff' stroke-width='2'/></svg>"
}

/// The bare basemap with no markers: proves the element creates the map and
/// frames the view, independent of any marker reconciliation.
pub fn empty_basemap_test() {
  use <- skip_without_browser
  matches("map_empty", [])
}

/// The basemap with two keyed markers: proves the element reconciles a `Scene`
/// and positions arbitrary HTML/SVG markers over the map at the right spots.
pub fn map_with_markers_test() {
  use <- skip_without_browser
  matches("map_markers", [
    #("belem", Marker(position: LngLat(lng: -30.0, lat: 20.0), html: red_pin())),
    #(
      "alfama",
      Marker(position: LngLat(lng: 30.0, lat: -10.0), html: blue_pin()),
    ),
  ])
}

// Render the real element to HTML, capture it through the live-WebGL pipeline,
// and assert it matches the committed baseline.
fn matches(name: String, markers: List(#(String, Marker))) -> Nil {
  screenshot.document_matches_baseline(
    document: document(markers),
    baseline: "test/screenshots/" <> name,
    size:,
    threshold: 0.2,
    options: screenshot.options()
      |> screenshot.with_webgl
      |> screenshot.with_settle(ms: settle_ms),
  )
  |> should.equal(Ok(screenshot.Match))
}

// Build the complete HTML document the library screenshots: the harness template
// (which loads MapLibre GL JS and the compiled element, and reads the scene) with
// the `<maplibre-map>` fragment injected at its `#app` mount point. We do the
// injection here — a plain string substitution on a fixture we control — rather
// than rely on the library, which is view-layer agnostic and only deals in
// complete documents.
fn document(markers: List(#(String, Marker))) -> String {
  let assert Ok(template_html) = simplifile.read(template)
  string.replace(
    template_html,
    each: "<div id=\"app\"></div>",
    with: "<div id=\"app\">" <> harness_html(markers) <> "</div>",
  )
}

// The fragment mounted into the template: the genuine `maplibre.map` element
// (so its `config` encoding is under test too), plus the scene as a JSON
// `<script>` the harness page reads back onto the element's `scene` property —
// because `scene` is a DOM property and can't travel in serialised HTML.
fn harness_html(markers: List(#(String, Marker))) -> String {
  let view =
    maplibre.map(
      "map",
      config(),
      [
        attribute.style("width", "600px"),
        attribute.style("height", "400px"),
      ],
      maplibre.scene(markers),
    )

  let scene_json =
    markers
    |> list.map(fn(entry) {
      let #(key, marker) = entry
      reconcile.Entry(
        key:,
        lng: marker.position.lng,
        lat: marker.position.lat,
        html: marker.html,
      )
    })
    |> reconcile.encode_scene
    |> json.to_string

  element.to_string(view)
  <> "<script type=\"application/json\" class=\"scene-for-map\">"
  <> scene_json
  <> "</script>"
}

fn skip_without_browser(run: fn() -> Nil) -> Nil {
  case envoy.get("CHROME_BIN"), envoy.get("ODIFF_BIN") {
    Ok(_), Ok(_) -> run()
    _, _ -> Nil
  }
}
