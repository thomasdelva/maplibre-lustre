import gleeunit/should
import maplibre/reconcile.{
  Add, Entry, Move, Remove, SetHtml, diff, diff_json,
}

// Fixtures. `a_moved`/`a_rehtml`/`a_both` share key "a" with `a` but change one
// or both mutable fields, so the diff has to tell move from set_html.
const a = Entry(key: "a", lng: 1.0, lat: 2.0, html: "<a/>")

const b = Entry(key: "b", lng: 3.0, lat: 4.0, html: "<b/>")

const c = Entry(key: "c", lng: 5.0, lat: 6.0, html: "<c/>")

const d = Entry(key: "d", lng: 7.0, lat: 8.0, html: "<d/>")

const a_moved = Entry(key: "a", lng: 9.0, lat: 9.0, html: "<a/>")

const a_rehtml = Entry(key: "a", lng: 1.0, lat: 2.0, html: "<a2/>")

const a_both = Entry(key: "a", lng: 9.0, lat: 9.0, html: "<a2/>")

pub fn empty_to_empty_test() {
  diff([], []) |> should.equal([])
}

pub fn add_test() {
  diff([], [a]) |> should.equal([Add("a", 1.0, 2.0, "<a/>")])
}

pub fn remove_test() {
  diff([a], []) |> should.equal([Remove("a")])
}

pub fn identical_is_noop_test() {
  diff([a], [a]) |> should.equal([])
}

pub fn move_test() {
  diff([a], [a_moved]) |> should.equal([Move("a", 9.0, 9.0)])
}

pub fn set_html_test() {
  diff([a], [a_rehtml]) |> should.equal([SetHtml("a", "<a2/>")])
}

pub fn move_and_set_html_test() {
  diff([a], [a_both])
  |> should.equal([Move("a", 9.0, 9.0), SetHtml("a", "<a2/>")])
}

pub fn disjoint_keys_test() {
  // b is unchanged and carried over untouched; a goes, c arrives.
  diff([a, b], [b, c])
  |> should.equal([Remove("a"), Add("c", 5.0, 6.0, "<c/>")])
}

pub fn reorder_only_is_noop_test() {
  // Marker order is irrelevant, so swapping with no field change yields nothing.
  diff([a, b], [b, a]) |> should.equal([])
}

pub fn mixed_test() {
  // Removes first (prev order), then upserts (next order): c removed, b kept, a
  // both moved and re-htmled, d added.
  diff([a, b, c], [b, a_both, d])
  |> should.equal([
    Remove("c"),
    Move("a", 9.0, 9.0),
    SetHtml("a", "<a2/>"),
    Add("d", 7.0, 8.0, "<d/>"),
  ])
}

pub fn diff_json_round_trip_test() {
  // The JSON contract the JS shell relies on: scene-shaped input in, ops JSON
  // array out, with object keys in declaration order.
  let prev = "{\"markers\":[{\"key\":\"a\",\"lng\":1.0,\"lat\":2.0,\"html\":\"x\"}]}"
  let next = "{\"markers\":[{\"key\":\"a\",\"lng\":9.0,\"lat\":9.0,\"html\":\"x\"}]}"
  diff_json(prev, next)
  |> should.equal("[{\"op\":\"move\",\"key\":\"a\",\"lng\":9,\"lat\":9}]")
}
