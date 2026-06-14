//// A tiny demo that exercises the whole `maplibre_lustre` surface end to end:
////
////   - render an OpenFreeMap basemap (no API key),
////   - drop ~4 markers, at least one of which is a bespoke SVG "pie" pin,
////   - turn a marker tap into a message that updates an on-screen label,
////   - frame all the points with a "Fit all" button.

import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import maplibre.{type LngLat, type Marker, Config, LngLat, Marker}

// The id of the map container. Stable for the lifetime of the app.
const map_id = "map"

// A handful of real-ish spots around Lisbon.
const places = [
  Place(
    id: "belem",
    name: "Torre de Belém",
    position: LngLat(lng: -9.2160, lat: 38.6916),
    pie: Some(#("#e4002b", "#f8b500")),
  ),
  Place(
    id: "alfama",
    name: "Alfama",
    position: LngLat(lng: -9.1300, lat: 38.7120),
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
    position: LngLat(lng: -9.1530, lat: 38.7376),
    pie: None,
  ),
]

type Place {
  // `pie: Some(#(colour_a, colour_b))` renders a two-slice pie marker;
  // `None` renders a plain coloured dot.
  Place(id: String, name: String, position: LngLat, pie: Option(#(String, String)))
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  Model(selected: Option(String))
}

type Msg {
  MapReady
  MarkerClicked(id: String)
  FitAllClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  let config =
    Config(
      style_url: "https://tiles.openfreemap.org/styles/bright",
      center: LngLat(lng: -9.139, lat: 38.722),
      zoom: 12.5,
    )

  // Just create the map; `MapReady` is dispatched once it exists, and we place
  // the markers in response to it (see `update`).
  #(Model(selected: None), maplibre.init(map_id, config, MapReady))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    MapReady -> #(model, maplibre.set_markers(map_id, markers(), MarkerClicked))
    MarkerClicked(id) -> #(Model(selected: Some(id)), effect.none())
    FitAllClicked -> {
      let #(sw, ne) = bounds(places)
      #(model, maplibre.fit_bounds(map_id, sw, ne, 60))
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.style("position", "relative"), attribute.style("height", "100%")], [
    // The map fills the area; give the container an explicit height via CSS.
    maplibre.container(map_id, [
      attribute.style("position", "absolute"),
      attribute.style("inset", "0"),
    ]),
    overlay(model),
  ])
}

fn overlay(model: Model) -> Element(Msg) {
  let label = case model.selected {
    Some(id) ->
      case list.find(places, fn(p) { p.id == id }) {
        Ok(place) -> "Selected: " <> place.name
        Error(_) -> "Selected: " <> id
      }
    None -> "Tap a pin to select it"
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
      html.button(
        [
          event.on_click(FitAllClicked),
          attribute.style("padding", "8px 12px"),
          attribute.style("border", "0"),
          attribute.style("border-radius", "8px"),
          attribute.style("background", "#0072ce"),
          attribute.style("color", "white"),
          attribute.style("box-shadow", "0 1px 4px rgba(0,0,0,0.3)"),
          attribute.style("cursor", "pointer"),
        ],
        [html.text("Fit all")],
      ),
    ],
  )
}

fn markers() -> List(Marker) {
  list.map(places, fn(place) {
    let html = case place.pie {
      Some(#(a, b)) -> pie_two(a, b)
      None -> dot("#444")
    }
    Marker(id: place.id, position: place.position, html: html)
  })
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
