//// A minimal [Lustre](https://lustre.build) wrapper around
//// [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/).
////
//// The imperative, stateful MapLibre `Map` never lives in your Lustre `Model`.
//// It lives inside a `<maplibre-map>` custom element: you render that element
//// in your `view` and hand it a declarative [`Scene`](#Scene) (a pure function
//// of your model). The element diffs successive scenes and issues the minimal
//// MapLibre calls — adding, moving, and removing only the markers that changed.
////
//// Data flows one way:
////
////   - **content** is declared by the scene and reconciled for you,
////   - **camera motion** is a one-shot command ([`fit_bounds`](#fit_bounds))
////     returned as an effect,
////   - **what happened** comes back as messages via the `on_*` event
////     attributes ([`on_marker_click`](#on_marker_click) and
////     [`on_map_click`](#on_map_click)).
////
//// Because the camera is never a controlled prop — `fit_bounds` is a one-shot
//// command, never re-asserted on every render — there is no feedback loop to
//// guard against.
////
//// This library targets JavaScript only. MapLibre itself is expected to be
//// loaded by the host page via a CDN `<script>` and `<link>` (the custom
//// element reads `window.maplibregl`).

import gleam/dynamic/decode
import gleam/json.{type Json}
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event

/// A longitude/latitude pair, in degrees. Note the field order: MapLibre works
/// in `[lng, lat]`, and so does this type.
pub type LngLat {
  LngLat(lng: Float, lat: Float)
}

/// How the map is first created. `center`/`zoom` are the *initial* camera only;
/// after creation the map owns its own camera (move it with
/// [`fit_bounds`](#fit_bounds)).
///
/// `style_url` is a MapLibre style document URL — for example
/// `"https://tiles.openfreemap.org/styles/bright"`, which needs no API key.
pub type Config {
  Config(style_url: String, center: LngLat, zoom: Float)
}

/// A single map pin. `html` is arbitrary markup (e.g. an inline SVG) injected as
/// the marker element's `innerHTML`.
///
/// > Note: `html` is set as `innerHTML`, so treat it as trusted markup — do not
/// > build it from unsanitised user input.
pub type Marker {
  Marker(position: LngLat, html: String)
}

/// A declarative description of what should be on the map right now. Build it
/// with [`scene`](#scene), as a pure function of your model, and pass it to
/// [`map`](#map). The element reconciles successive scenes for you.
pub opaque type Scene {
  Scene(markers: List(#(String, Marker)))
}

/// Build a scene from a keyed list of markers. Each marker is paired with a
/// **stable key** (any unique string); the key is how the element tells one
/// render's markers from the next, so a marker keeps its identity — and the
/// element only adds, moves, or removes the ones that actually changed. The key
/// is also echoed back to [`on_marker_click`](#on_marker_click).
pub fn scene(markers: List(#(String, Marker))) -> Scene {
  Scene(markers: markers)
}

/// Render the map. Give it a stable `id` and size it with CSS (an explicit
/// height is required, or the map is invisible). It renders with **no
/// children** — the element injects MapLibre's own canvas — and reconciles the
/// given [`Scene`](#Scene) on every render.
///
/// Wire interactions through `attributes` with the `on_*` helpers below, e.g.
/// `maplibre.on_marker_click(MarkerClicked)`.
pub fn map(
  id: String,
  config: Config,
  attributes: List(Attribute(msg)),
  scene: Scene,
) -> Element(msg) {
  element.element(
    "maplibre-map",
    [
      attribute.id(id),
      attribute.attribute("config", json.to_string(encode_config(config))),
      attribute.attribute("scene", json.to_string(encode_scene(scene))),
      ..attributes
    ],
    [],
  )
}

/// Fires with a tapped marker's key. Tapping a marker does **not** also fire
/// [`on_map_click`](#on_map_click).
pub fn on_marker_click(handler: fn(String) -> msg) -> Attribute(msg) {
  let decoder = {
    use id <- decode.subfield(["detail", "id"], decode.string)
    decode.success(handler(id))
  }
  event.on("maplibre:markerclick", decoder)
}

/// Fires with the clicked [`LngLat`](#LngLat) whenever the map *background* (not
/// a marker) is tapped. Use it to place a new marker, or to clear a selection.
pub fn on_map_click(handler: fn(LngLat) -> msg) -> Attribute(msg) {
  let decoder = {
    use lng <- decode.subfield(["detail", "lng"], decode.float)
    use lat <- decode.subfield(["detail", "lat"], decode.float)
    decode.success(handler(LngLat(lng:, lat:)))
  }
  event.on("maplibre:click", decoder)
}

/// Frame a bounding box, animating the camera so the box (plus `padding` pixels
/// on every side) is visible. A one-shot command: applied when the effect runs,
/// never re-asserted, and queued until the map for `id` exists.
pub fn fit_bounds(
  id: String,
  sw: LngLat,
  ne: LngLat,
  padding: Int,
) -> Effect(msg) {
  use _dispatch <- effect.from
  do_fit_bounds(id, sw.lng, sw.lat, ne.lng, ne.lat, padding)
}

fn encode_config(config: Config) -> Json {
  json.object([
    #("style_url", json.string(config.style_url)),
    #("lng", json.float(config.center.lng)),
    #("lat", json.float(config.center.lat)),
    #("zoom", json.float(config.zoom)),
  ])
}

fn encode_scene(scene: Scene) -> Json {
  json.object([
    #(
      "markers",
      json.array(scene.markers, fn(entry) {
        let #(key, marker) = entry
        json.object([
          #("key", json.string(key)),
          #("lng", json.float(marker.position.lng)),
          #("lat", json.float(marker.position.lat)),
          #("html", json.string(marker.html)),
        ])
      }),
    ),
  ])
}

@external(javascript, "./maplibre_ffi.mjs", "fitBounds")
fn do_fit_bounds(
  id: String,
  sw_lng: Float,
  sw_lat: Float,
  ne_lng: Float,
  ne_lat: Float,
  padding: Int,
) -> Nil
// ---------------------------------------------------------------------------
// TODO(coverage): MapLibre GL JS surface this wrapper does NOT cover, and how
// to add each piece. Today it covers a deliberately tiny slice — create a
// basemap (`Config`: style/center/zoom), show keyed HTML markers, report
// marker and map-background taps, and `fit_bounds`. Everything below is
// unwrapped, grouped by area and ordered roughly by value.
//
// Three mechanics cover almost every addition; pick by the kind of API:
//   * Declarative content (derived from the model) -> add it to the `Scene`
//     JSON and extend the keyed reconciler in maplibre_ffi.mjs to diff it.
//     This is how markers work; sources/layers/popups follow the same shape.
//   * One-shot command (imperative action) -> a `fn(...) -> Effect`, an FFI
//     export, and a method on the element queued until `load`. Like fit_bounds.
//   * Observation (the map reports something) -> an `on_*(handler) ->
//     Attribute` that decodes a CustomEvent the element dispatches. Like
//     on_map_click.
//
// 1. Map creation options — extend `Config` and the `new maplibregl.Map({...})`
//    call: bearing, pitch, minZoom/maxZoom, minPitch/maxPitch, maxBounds,
//    interactive, attributionControl, cooperativeGestures, hash,
//    renderWorldCopies, locale, fadeDuration. Pure config; cheapest win.
//
// 2. Camera — commands mirroring fit_bounds (Effect + FFI + queued method):
//    jumpTo, easeTo, flyTo, panBy, zoomTo, rotateTo, setBearing, setPitch,
//    fitScreenCoordinates. Observation: moveend/move/zoom/rotate/pitch events
//    exposing center/zoom/bearing/pitch (reintroduce a `Camera` type).
//
// 3. Map & interaction events — beyond click: dblclick, contextmenu,
//    mousemove/mousedown/mouseup, mouseenter/mouseleave, wheel,
//    dragstart/drag/dragend, boxzoom, load (a ready signal), idle, render,
//    error, resize, and the data lifecycle (data/sourcedata/styledata). Each
//    is one `on_*` Attribute.
//
// 4. Sources + Layers — the big one, and the reason the model stays small.
//    Sources: geojson, vector, raster, raster-dem, image, video
//    (addSource/removeSource/getSource, setData). Layers: fill, line, symbol,
//    circle, heatmap, fill-extrusion, raster, hillshade, background, sky, with
//    setPaintProperty/setLayoutProperty/setFilter/setLayerZoomRange and
//    `beforeId` ordering. Model declaratively: add `sources` and `layers`
//    (keyed, like markers) to the `Scene` and diff them in the reconciler
//    (add/remove/update by id; layers also need order handling). Both must wait
//    for style load — queue like the scene does today. Unlocks clustering (a
//    geojson option) and data-driven styling.
//
// 5. Feature state & hit-testing — needs (4) first: setFeatureState/
//    removeFeatureState for hover/selection styling, queryRenderedFeatures/
//    querySourceFeatures for "what's under the cursor", project/unproject for
//    lng-lat <-> pixel. Layer-scoped events (`map.on('click', layerId, ...)`)
//    are a layer-keyed variant of the on_* Attributes.
//
// 6. Controls — NavigationControl, GeolocateControl, ScaleControl,
//    FullscreenControl, AttributionControl, GlobeControl, and custom controls
//    (addControl/removeControl). Add-once and position-keyed; expose as
//    `Config` flags or `Scene` entries.
//
// 7. Popups & richer markers — the Popup class (setHTML/setLngLat, anchor,
//    offset, closeOnClick) as scene content; and marker options we omit:
//    draggable (+ drag events), anchor, offset, rotation, color, opacity,
//    setPopup. Extend `Marker` and the marker reconciler.
//
// 8. Style & runtime visuals — setStyle (swap basemap at runtime), addImage/
//    loadImage (icons for symbol layers), setProjection({type:'globe'}) and its
//    atmosphere, setTerrain (3D; needs a raster-dem source), setSky/setFog,
//    setLight. Globe/terrain apply only after style load — queue like the
//    scene. Custom WebGL layers (CustomLayerInterface) enable deck.gl/three.js.
//
// Outside the Map class, setRTLTextPlugin (RTL labels) and addProtocol (e.g.
// pmtiles) are global one-time registrations — best done in the host page, not
// the wrapper.
// ---------------------------------------------------------------------------
