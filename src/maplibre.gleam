//// A minimal [Lustre](https://lustre.build) wrapper around
//// [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/).
////
//// The surface is intentionally tiny. It covers exactly four things:
////
////   1. Render a basemap into a container (no API key required).
////   2. Show markers whose content is arbitrary HTML/SVG.
////   3. Emit a message when a marker is tapped.
////   4. Frame a set of points with `fit_bounds`.
////
//// The imperative, stateful MapLibre `Map` instance never lives in your
//// Lustre `Model`. It is held in a registry inside the FFI module and is
//// looked up by container id. Your `update` loop returns effects that
//// reconcile that live map.
////
//// This library targets JavaScript only. MapLibre itself is expected to be
//// loaded by the host page via a CDN `<script>` and `<link>` (the wrapper
//// reads `window.maplibregl`).

import gleam/json
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

/// A longitude/latitude pair, in degrees. Note the field order: MapLibre
/// works in `[lng, lat]`, and so does this type.
pub type LngLat {
  LngLat(lng: Float, lat: Float)
}

/// The options used to create a map.
///
/// `style_url` is a MapLibre style document URL — for example
/// `"https://tiles.openfreemap.org/styles/bright"`, which needs no API key.
pub type Config {
  Config(style_url: String, center: LngLat, zoom: Float)
}

/// A single map pin.
///
/// `html` is arbitrary markup (e.g. an inline SVG) injected as the marker
/// element's `innerHTML`. `id` is echoed back to your `on_click` handler when
/// the marker is tapped.
pub type Marker {
  Marker(id: String, position: LngLat, html: String)
}

/// The element to place in your `view`. Give it a stable `id` and size it with
/// CSS (an explicit height is required, or the map is invisible).
///
/// It renders with **no children** — MapLibre injects its own canvas into it,
/// so Lustre must not try to diff children into this node.
pub fn container(id: String, attrs: List(Attribute(msg))) -> Element(msg) {
  html.div([attribute.id(id), ..attrs], [])
}

/// Create the map. Run this once (e.g. from your app's `init`). It uses
/// `effect.after_paint` internally so the container element is guaranteed to
/// exist in the DOM before `new maplibregl.Map(...)` runs.
///
/// Once the map has been created, `on_ready` is dispatched to your `update`
/// loop. Fire [`set_markers`](#set_markers)/[`fit_bounds`](#fit_bounds) in
/// response to that message — the map is guaranteed to exist by then, so you
/// never have to reason about effect ordering. (Note: `on_ready` fires when the
/// map object exists, which is enough for markers and bounds; it does not wait
/// for the style/tiles to finish loading.)
pub fn init(id: String, config: Config, on_ready: msg) -> Effect(msg) {
  use dispatch, _root <- effect.after_paint
  do_init(
    id,
    config.style_url,
    config.center.lng,
    config.center.lat,
    config.zoom,
  )
  dispatch(on_ready)
}

/// Replace all markers on the map.
///
/// This is a cheap clear-and-re-add: every existing marker is removed and the
/// given list is added. That is fine for modest counts (hundreds of pins, not
/// thousands).
///
/// `on_click` turns a tapped marker's `id` into a message for your `update`
/// loop. The markers cross the FFI boundary as a JSON string rather than as a
/// Gleam list (a Gleam list is a linked list, not a JS array).
///
/// Call this only once the map exists — i.e. in response to [`init`](#init)'s
/// `on_ready` message, or any time after. If the map does not exist yet this is
/// a no-op.
pub fn set_markers(
  id: String,
  markers: List(Marker),
  on_click: fn(String) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  do_set_markers(id, encode_markers(markers), fn(marker_id) {
    dispatch(on_click(marker_id))
  })
}

/// Frame a bounding box, animating the camera so the box (plus `padding`
/// pixels on every side) is visible. Use this when the set of points you want
/// in view changes.
///
/// Like [`set_markers`](#set_markers), call this once the map exists (in
/// response to [`init`](#init)'s `on_ready` message, or later). If the map does
/// not exist yet this is a no-op.
pub fn fit_bounds(
  id: String,
  sw: LngLat,
  ne: LngLat,
  padding: Int,
) -> Effect(msg) {
  use _dispatch <- effect.from
  do_fit_bounds(id, sw.lng, sw.lat, ne.lng, ne.lat, padding)
}

fn encode_markers(markers: List(Marker)) -> String {
  json.to_string(
    json.array(markers, fn(m) {
      json.object([
        #("id", json.string(m.id)),
        #("lng", json.float(m.position.lng)),
        #("lat", json.float(m.position.lat)),
        #("html", json.string(m.html)),
      ])
    }),
  )
}

@external(javascript, "./maplibre_ffi.mjs", "init")
fn do_init(
  id: String,
  style: String,
  lng: Float,
  lat: Float,
  zoom: Float,
) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "setMarkers")
fn do_set_markers(
  id: String,
  markers_json: String,
  on_click: fn(String) -> Nil,
) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "fitBounds")
fn do_fit_bounds(
  id: String,
  sw_lng: Float,
  sw_lat: Float,
  ne_lng: Float,
  ne_lat: Float,
  padding: Int,
) -> Nil
