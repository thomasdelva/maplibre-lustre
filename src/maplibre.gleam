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
////     attributes ([`on_marker_click`](#on_marker_click),
////     [`on_map_click`](#on_map_click), and [`on_move`](#on_move), which
////     reports the visible [`Bounds`](#Bounds) as the camera settles).
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
import gleam/list
import gleam/result
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event
import maplibre/reconcile

/// A longitude/latitude pair, in degrees. Note the field order: MapLibre works
/// in `[lng, lat]`, and so does this type.
pub type LngLat {
  LngLat(lng: Float, lat: Float)
}

/// A geographic bounding box: its south-west and north-east corners. This is
/// what [`on_move`](#on_move) reports as the visible area. Serialise one with
/// [`bounds_to_json`](#bounds_to_json) to persist a viewport and restore it
/// later by opening the map [`Fitted`](#View) to it.
pub type Bounds {
  Bounds(sw: LngLat, ne: LngLat)
}

/// How the map is first framed — the *initial* camera only. After creation the
/// map owns its camera (move it with [`fit_bounds`](#fit_bounds)).
///
///   - `Centered` opens at a point and zoom level.
///   - `Fitted` opens already fitted to a [`Bounds`](#Bounds) (plus `padding`
///     pixels on every side), applied at construction with **no animation**.
///     Read a saved viewport synchronously and open `Fitted` to it, so the map
///     appears where the user left it instead of flying there after load.
pub type View {
  Centered(center: LngLat, zoom: Float)
  Fitted(bounds: Bounds, padding: Int)
}

/// How the map is first created.
///
/// `style_url` is a MapLibre style document URL — for example
/// `"https://tiles.openfreemap.org/styles/bright"`, which needs no API key.
///
/// `view` is the initial camera (see [`View`](#View)).
pub type Config {
  Config(style_url: String, view: View)
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
      // The scene crosses as a DOM *property*, not a stringified attribute: on
      // the JavaScript target a `Json` is already a plain object, so the element
      // receives it without a `json.to_string`/`JSON.parse` round-trip, and
      // Lustre re-sets it only when the scene actually changed (structural diff).
      attribute.property("scene", encode_scene(scene)),
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

/// Fires with the map's visible [`Bounds`](#Bounds) each time the camera settles
/// after a pan or zoom (MapLibre's `moveend`). Persist it — e.g. with
/// [`bounds_to_json`](#bounds_to_json) and the `maplibre/storage` helper — and
/// open the map [`Fitted`](#View) to it next time, so it reopens where the user
/// left it.
pub fn on_move(handler: fn(Bounds) -> msg) -> Attribute(msg) {
  let decoder = {
    use sw_lng <- decode.subfield(["detail", "sw_lng"], decode.float)
    use sw_lat <- decode.subfield(["detail", "sw_lat"], decode.float)
    use ne_lng <- decode.subfield(["detail", "ne_lng"], decode.float)
    use ne_lat <- decode.subfield(["detail", "ne_lat"], decode.float)
    decode.success(
      handler(Bounds(
        sw: LngLat(lng: sw_lng, lat: sw_lat),
        ne: LngLat(lng: ne_lng, lat: ne_lat),
      )),
    )
  }
  event.on("maplibre:moveend", decoder)
}

/// Frame a bounding box, animating the camera so the box (plus `padding` pixels
/// on every side) is visible. A one-shot command: applied when the effect runs,
/// never re-asserted, and queued until the map for `id` exists.
///
/// (To open the map *already* framed to a box — e.g. restoring a saved
/// viewport — use a [`Fitted`](#View) view instead; that applies at creation
/// with no animation.)
///
/// Runs via `after_paint`, so the `<maplibre-map>` element is guaranteed to be
/// in the DOM when looked up — even when called from `init`, before the first
/// paint, where a plain effect would find no element and be a silent no-op.
pub fn fit_bounds(
  id: String,
  sw: LngLat,
  ne: LngLat,
  padding: Int,
) -> Effect(msg) {
  use _dispatch, _root <- effect.after_paint
  do_fit_bounds(id, sw.lng, sw.lat, ne.lng, ne.lat, padding)
}

/// Serialise [`Bounds`](#Bounds) to a compact JSON string, ready to hand to a
/// store such as `maplibre/storage`. Round-trips with
/// [`bounds_from_json`](#bounds_from_json).
pub fn bounds_to_json(bounds: Bounds) -> String {
  json.to_string(
    json.object([
      #("sw", encode_lng_lat(bounds.sw)),
      #("ne", encode_lng_lat(bounds.ne)),
    ]),
  )
}

/// Parse [`Bounds`](#Bounds) produced by [`bounds_to_json`](#bounds_to_json).
/// Returns `Error(Nil)` if the string is missing or malformed, so a corrupt or
/// absent saved value simply falls back to your default view.
pub fn bounds_from_json(encoded: String) -> Result(Bounds, Nil) {
  json.parse(encoded, bounds_decoder())
  |> result.replace_error(Nil)
}

fn bounds_decoder() -> decode.Decoder(Bounds) {
  use sw <- decode.field("sw", lng_lat_decoder())
  use ne <- decode.field("ne", lng_lat_decoder())
  decode.success(Bounds(sw:, ne:))
}

fn lng_lat_decoder() -> decode.Decoder(LngLat) {
  use lng <- decode.field("lng", decode.float)
  use lat <- decode.field("lat", decode.float)
  decode.success(LngLat(lng:, lat:))
}

fn encode_lng_lat(p: LngLat) -> Json {
  json.object([#("lng", json.float(p.lng)), #("lat", json.float(p.lat))])
}

fn encode_config(config: Config) -> Json {
  let view = case config.view {
    Centered(center:, zoom:) -> [
      #("kind", json.string("centered")),
      #("lng", json.float(center.lng)),
      #("lat", json.float(center.lat)),
      #("zoom", json.float(zoom)),
    ]
    Fitted(bounds:, padding:) -> [
      #("kind", json.string("fitted")),
      #("sw_lng", json.float(bounds.sw.lng)),
      #("sw_lat", json.float(bounds.sw.lat)),
      #("ne_lng", json.float(bounds.ne.lng)),
      #("ne_lat", json.float(bounds.ne.lat)),
      #("padding", json.int(padding)),
    ]
  }
  json.object([#("style_url", json.string(config.style_url)), ..view])
}

// Flatten the public `Scene` into the reconciler's wire rows; `reconcile` owns
// the JSON shape, so the field names live there, not here.
fn encode_scene(scene: Scene) -> Json {
  reconcile.encode_scene(
    list.map(scene.markers, fn(entry) {
      let #(key, marker) = entry
      reconcile.Entry(
        key:,
        lng: marker.position.lng,
        lat: marker.position.lat,
        html: marker.html,
      )
    }),
  )
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
// basemap (`Config`: style + a `View` that opens centred or fitted to bounds),
// show keyed HTML markers, report marker/map taps and camera moves
// (`on_move`), and `fit_bounds`. Everything below is unwrapped, grouped by area
// and ordered roughly by value.
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
