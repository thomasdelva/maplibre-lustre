//// The **functional core** of the marker reconciler: a pure, typed keyed diff
//// over the scene's markers, plus a thin wrapper that is the only thing the
//// JavaScript shell (`maplibre_ffi.mjs`) calls. There are no `@external`
//// declarations here, so this module never imports the FFI — the import goes
//// one way (shell -> compiled `reconcile.mjs`) and there is no cycle.
////
//// The shell owns the *imperative* half: it turns each [`Op`](#Op) into a
//// MapLibre call (create/remove/move a real marker, rewrite its HTML). Keeping
//// the decision (what changed) here, separate from the application (how to
//// apply it), is what makes the logic unit-testable under `gleeunit` with no
//// DOM or `maplibregl` mock.
////
//// The shell hands each scene across as the `scene` DOM property — a plain JS
//// value Lustre sets without a JSON round-trip — so [`diff_dynamic`](#diff_dynamic)
//// takes the scenes as [`Dynamic`](https://hexdocs.pm/gleam_stdlib/gleam/dynamic.html#Dynamic)
//// and decodes them with `decode.run`. Only `Dynamic` in and a JSON `String`
//// out cross the boundary: no Gleam list/record is ever marshalled at the JS
//// call site.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list

/// A single reconciliation step: the minimal change to turn the previous marker
/// set into the next one. [`diff`](#diff) emits an ordered list of these; the
/// shell applies them in order. (It's a list, not a set, because layers — a
/// future `Scene` addition — will be order-sensitive even though markers are
/// not.)
pub type Op {
  Add(key: String, lng: Float, lat: Float, html: String)
  Remove(key: String)
  Move(key: String, lng: Float, lat: Float)
  SetHtml(key: String, html: String)
}

/// One decoded marker row, matching the scene JSON shape
/// `{markers:[{key,lng,lat,html}]}` produced by `maplibre.encode_scene`. Keep
/// the two in lockstep: this is the contract the reconciler decodes.
pub type Entry {
  Entry(key: String, lng: Float, lat: Float, html: String)
}

/// Diff two marker lists by key, returning the minimal ordered ops to get from
/// `prev` to `next`.
///
/// Determinism (so tests can assert exact lists): `Remove`s come first, in
/// `prev` order, for keys absent from `next`; then add/update ops in `next`
/// order. A key present in both yields a `Move` if its position changed and a
/// `SetHtml` if its HTML changed (both may fire). Marker order is irrelevant —
/// reordering with no field change yields no ops. The dict is used only for
/// membership/lookup; output order always comes from iterating the input lists.
pub fn diff(prev: List(Entry), next: List(Entry)) -> List(Op) {
  let prev_by_key = index(prev)
  let next_by_key = index(next)

  let removes =
    list.filter_map(prev, fn(entry) {
      case dict.has_key(next_by_key, entry.key) {
        True -> Error(Nil)
        False -> Ok(Remove(entry.key))
      }
    })

  let upserts =
    list.flat_map(next, fn(entry) {
      case dict.get(prev_by_key, entry.key) {
        Error(_) -> [Add(entry.key, entry.lng, entry.lat, entry.html)]
        Ok(old) -> {
          // Exact float equality is safe: both sides are JSON-decoded here, so
          // they share one representation (we never compare against a raw Gleam
          // float that skipped the JSON round-trip).
          let moved = case old.lng == entry.lng && old.lat == entry.lat {
            True -> []
            False -> [Move(entry.key, entry.lng, entry.lat)]
          }
          let rehtml = case old.html == entry.html {
            True -> []
            False -> [SetHtml(entry.key, entry.html)]
          }
          list.append(moved, rehtml)
        }
      }
    })

  list.append(removes, upserts)
}

/// The FFI boundary. The shell passes the previous and next scenes as the
/// already-parsed JS values it holds (the `scene` DOM property), so they arrive
/// as `Dynamic` and are decoded with `decode.run` — no `json.parse`. Only
/// `Dynamic` crosses in and a JSON `String` crosses out, so no Gleam
/// list/custom-type marshalling happens at the JS call site. Decode both scenes
/// into `List(Entry)`, [`diff`](#diff) them, and encode the ops back to a JSON
/// array. Malformed input decodes to an empty marker list (treated as "no
/// markers").
pub fn diff_dynamic(prev: Dynamic, next: Dynamic) -> String {
  let ops = diff(decode_scene(prev), decode_scene(next))
  json.to_string(json.array(ops, encode_op))
}

fn index(entries: List(Entry)) -> Dict(String, Entry) {
  list.fold(entries, dict.new(), fn(acc, entry) {
    dict.insert(acc, entry.key, entry)
  })
}

fn decode_scene(value: Dynamic) -> List(Entry) {
  case decode.run(value, scene_decoder()) {
    Ok(entries) -> entries
    Error(_) -> []
  }
}

fn scene_decoder() -> decode.Decoder(List(Entry)) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use lng <- decode.field("lng", decode.float)
    use lat <- decode.field("lat", decode.float)
    use html <- decode.field("html", decode.string)
    decode.success(Entry(key:, lng:, lat:, html:))
  }
  use markers <- decode.field("markers", decode.list(entry_decoder))
  decode.success(markers)
}

fn encode_op(op: Op) -> Json {
  case op {
    Add(key:, lng:, lat:, html:) ->
      json.object([
        #("op", json.string("add")),
        #("key", json.string(key)),
        #("lng", json.float(lng)),
        #("lat", json.float(lat)),
        #("html", json.string(html)),
      ])
    Remove(key:) ->
      json.object([#("op", json.string("remove")), #("key", json.string(key))])
    Move(key:, lng:, lat:) ->
      json.object([
        #("op", json.string("move")),
        #("key", json.string(key)),
        #("lng", json.float(lng)),
        #("lat", json.float(lat)),
      ])
    SetHtml(key:, html:) ->
      json.object([
        #("op", json.string("set_html")),
        #("key", json.string(key)),
        #("html", json.string(html)),
      ])
  }
}
