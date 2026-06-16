//// A tiny convenience wrapper around the browser's `localStorage`, for
//// persisting small bits of serialisable state between visits — for example
//// the map's last viewport (pair it with [`maplibre.bounds_to_json`](../maplibre.html#bounds_to_json)).
////
//// JavaScript only. Everything degrades gracefully: if `localStorage` is
//// unavailable (private mode, disabled cookies, …) reads return `Error(Nil)`
//// and writes are silently dropped, so callers never have to guard for it.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result
import lustre/effect.{type Effect}

/// Read the string stored under `key`. Returns `Error(Nil)` if the key is
/// absent or storage is unavailable — fall back to a default in that case.
///
/// This is a plain function (not an effect) so it can be used while building
/// your initial model, e.g. to choose the map's starting [`View`](../maplibre.html#View).
pub fn get(key: String) -> Result(String, Nil) {
  decode.run(do_get(key), decode.string)
  |> result.replace_error(Nil)
}

/// Store `value` under `key`, as an effect. Returns no message.
pub fn set(key: String, value: String) -> Effect(msg) {
  use _dispatch <- effect.from
  do_set(key, value)
}

/// Remove `key`, as an effect. Returns no message.
pub fn remove(key: String) -> Effect(msg) {
  use _dispatch <- effect.from
  do_remove(key)
}

@external(javascript, "./storage_ffi.mjs", "getItem")
fn do_get(key: String) -> Dynamic

@external(javascript, "./storage_ffi.mjs", "setItem")
fn do_set(key: String, value: String) -> Nil

@external(javascript, "./storage_ffi.mjs", "removeItem")
fn do_remove(key: String) -> Nil
