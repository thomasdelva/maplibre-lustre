//// A tiny demo that exercises the whole `maplibre_lustre` surface end to end:
////
////   - render an OpenFreeMap basemap (no API key),
////   - declare ~4 markers, at least one of which is a bespoke SVG "pie" pin,
////   - turn a marker tap into a message that updates an on-screen label,
////   - place new markers by tapping the map (in "Add pin" mode) — appending to
////     the model re-renders the scene, and the element's keyed diff adds just
////     the one new pin,
////   - clear the selection by tapping empty space,
////   - frame all the points with a "Fit all" button.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import maplibre.{type LngLat, Config, LngLat, Marker}

// The id of the map element. Stable for the lifetime of the app.
const map_id = "map"

const map_config = Config(
  style_url: "https://tiles.openfreemap.org/styles/bright",
  center: LngLat(lng: -9.139, lat: 38.722),
  zoom: 12.5,
)

// A handful of real-ish spots around Lisbon. These seed the model; the user
// can then drop more by tapping the map in "Add pin" mode.
const initial_places = [
  Place(
    id: "belem",
    name: "Torre de Belém",
    position: LngLat(lng: -9.216, lat: 38.6916),
    pie: Some(#("#e4002b", "#f8b500")),
  ),
  Place(
    id: "alfama",
    name: "Alfama",
    position: LngLat(lng: -9.13, lat: 38.712),
    pie: Some(#("#0072ce", "#00a651")),
  ),
  Place(
    id: "praca",
    name: "Praça do Comércio",
    position: LngLat(lng: -9.1366, lat: 38.7077),
    pie: None,
  ),
  Place(
    id: "gulbenkian",
    name: "Museu Gulbenkian",
    position: LngLat(lng: -9.153, lat: 38.7376),
    pie: None,
  ),
]

type Place {
  // `pie: Some(#(colour_a, colour_b))` renders a two-slice pie marker;
  // `None` renders a plain coloured dot.
  Place(
    id: String,
    name: String,
    position: LngLat,
    pie: Option(#(String, String)),
  )
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  // `places` grows at runtime as pins are dropped. `adding` toggles "tap the
  // map to drop a pin" mode, and `next_id` keeps dropped pins uniquely
  // identified.
  Model(
    places: List(Place),
    selected: Option(String),
    adding: Bool,
    next_id: Int,
  )
}

type Msg {
  MarkerClicked(id: String)
  MapClicked(position: LngLat)
  ToggleAdding
  FitAllClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // Nothing to do up front: the map is created by the `<maplibre-map>` element
  // when `view` renders it, and the markers are part of the scene.
  let model =
    Model(places: initial_places, selected: None, adding: False, next_id: 1)
  #(model, effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    MarkerClicked(id) -> #(Model(..model, selected: Some(id)), effect.none())

    // A tap on the map background: either drop a new pin (in "Add pin" mode)
    // or, otherwise, clear the current selection. Both are pure model changes —
    // the scene re-renders and the element reconciles it.
    MapClicked(position) ->
      case model.adding {
        True -> add_pin(model, position)
        False -> #(Model(..model, selected: None), effect.none())
      }

    ToggleAdding -> #(Model(..model, adding: !model.adding), effect.none())

    FitAllClicked -> {
      let #(sw, ne) = bounds(model.places)
      #(model, maplibre.fit_bounds(map_id, sw, ne, 60))
    }
  }
}

// Drop a new pin at `position` and select it. Appending to `places` changes the
// scene, and the keyed diff adds exactly one marker.
fn add_pin(model: Model, position: LngLat) -> #(Model, Effect(Msg)) {
  let id = "pin-" <> int.to_string(model.next_id)
  let place =
    Place(
      id: id,
      name: "Dropped pin " <> int.to_string(model.next_id),
      position: position,
      pie: None,
    )
  let model =
    Model(
      ..model,
      places: list.append(model.places, [place]),
      selected: Some(id),
      next_id: model.next_id + 1,
    )
  #(model, effect.none())
}

fn view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.style("position", "relative"), attribute.style("height", "100%")],
    [
      // The map fills the area; give it an explicit size via CSS, render it with
      // no children, and hand it the scene derived from the model.
      maplibre.map(
        map_id,
        map_config,
        [
          attribute.style("position", "absolute"),
          attribute.style("inset", "0"),
          maplibre.on_marker_click(MarkerClicked),
          maplibre.on_map_click(MapClicked),
        ],
        scene(model),
      ),
      overlay(model),
    ],
  )
}

fn scene(model: Model) -> maplibre.Scene {
  let markers =
    list.map(model.places, fn(place) {
      #(place.id, Marker(position: place.position, html: marker_html(place)))
    })
  maplibre.scene(markers)
}

fn overlay(model: Model) -> Element(Msg) {
  let label = case model.selected {
    Some(id) ->
      case list.find(model.places, fn(p) { p.id == id }) {
        Ok(place) -> "Selected: " <> place.name
        Error(_) -> "Selected: " <> id
      }
    None ->
      case model.adding {
        True -> "Tap the map to drop a pin"
        False -> "Tap a pin to select it (tap empty space to clear)"
      }
  }

  let add_label = case model.adding {
    True -> "Adding…"
    False -> "Add pin"
  }
  let add_background = case model.adding {
    True -> "#e4002b"
    False -> "#444"
  }

  html.div(
    [
      attribute.style("position", "absolute"),
      attribute.style("top", "12px"),
      attribute.style("left", "12px"),
      attribute.style("right", "12px"),
      attribute.style("z-index", "1"),
      attribute.style("display", "flex"),
      attribute.style("gap", "8px"),
      attribute.style("align-items", "center"),
      attribute.style("font-family", "system-ui, sans-serif"),
    ],
    [
      html.div(
        [
          attribute.style("background", "white"),
          attribute.style("padding", "8px 12px"),
          attribute.style("border-radius", "8px"),
          attribute.style("box-shadow", "0 1px 4px rgba(0,0,0,0.3)"),
          attribute.style("flex", "1"),
        ],
        [html.text(label)],
      ),
      button(add_label, add_background, ToggleAdding),
      button("Fit all", "#0072ce", FitAllClicked),
    ],
  )
}

fn button(label: String, background: String, msg: Msg) -> Element(Msg) {
  html.button(
    [
      event.on_click(msg),
      attribute.style("padding", "8px 12px"),
      attribute.style("border", "0"),
      attribute.style("border-radius", "8px"),
      attribute.style("background", background),
      attribute.style("color", "white"),
      attribute.style("box-shadow", "0 1px 4px rgba(0,0,0,0.3)"),
      attribute.style("cursor", "pointer"),
    ],
    [html.text(label)],
  )
}

fn marker_html(place: Place) -> String {
  case place.pie {
    Some(#(a, b)) -> pie_two(a, b)
    None -> dot("#444")
  }
}

// A two-slice pie marker, proving the arbitrary-HTML marker path. The library
// itself only ever sees the resulting string.
fn pie_two(c1: String, c2: String) -> String {
  "<svg width='24' height='24' viewBox='0 0 24 24'>"
  <> "<path d='M12,12 L12,0 A12,12 0 0 1 12,24 Z' fill='"
  <> c1
  <> "'/>"
  <> "<path d='M12,12 L12,24 A12,12 0 0 1 12,0 Z' fill='"
  <> c2
  <> "'/>"
  <> "<circle cx='12' cy='12' r='11' fill='none' stroke='white' stroke-width='2'/>"
  <> "</svg>"
}

fn dot(colour: String) -> String {
  "<svg width='20' height='20' viewBox='0 0 20 20'>"
  <> "<circle cx='10' cy='10' r='8' fill='"
  <> colour
  <> "' stroke='white' stroke-width='2'/>"
  <> "</svg>"
}

// Compute a south-west / north-east bounding box covering all places.
fn bounds(places: List(Place)) -> #(LngLat, LngLat) {
  let lngs = list.map(places, fn(p) { p.position.lng })
  let lats = list.map(places, fn(p) { p.position.lat })
  let sw = LngLat(lng: min(lngs), lat: min(lats))
  let ne = LngLat(lng: max(lngs), lat: max(lats))
  #(sw, ne)
}

fn min(xs: List(Float)) -> Float {
  list.fold(xs, 1.0e9, float.min)
}

fn max(xs: List(Float)) -> Float {
  list.fold(xs, -1.0e9, float.max)
}
