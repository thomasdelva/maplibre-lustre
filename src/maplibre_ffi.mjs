// The `<maplibre-map>` custom element: the live, mutable MapLibre `Map` lives
// here, never in the Gleam model. Lustre renders the element and sets two
// string attributes — `config` (init-only) and `scene` (a JSON description of
// the markers) — and the element reconciles the scene into the map, adding,
// moving, and removing only the markers that changed.
//
// MapLibre is loaded by the host page via a CDN <script>, exposing the global
// `window.maplibregl`. We read it lazily (inside the element) so this module
// can be imported before the CDN script has run.

// The keyed diff is a pure Gleam function (the functional core). The element
// is the imperative shell: it asks `diff_json` what changed between two scene
// JSON strings, then applies the resulting ops to the live map. `reconcile`
// has no FFI externs, so this import is one-way (no cycle).
import { diff_json } from "./maplibre/reconcile.mjs";

function maplibre() {
  const gl = globalThis.maplibregl;
  if (!gl) {
    throw new Error(
      "maplibre-lustre: window.maplibregl is not defined. Did you include the " +
        "MapLibre GL JS <script> (and its CSS) from a CDN before your app?",
    );
  }
  return gl;
}

class MaplibreMap extends HTMLElement {
  static get observedAttributes() {
    return ["config", "scene"];
  }

  #map = null;
  #ready = false;
  #config = null;
  // key -> live maplibregl.Marker. The diff against the previous scene decides
  // which of these to add, move, remove, or re-html.
  #markers = new Map();
  // The previous scene as the raw JSON string we last applied; `diff_json`
  // diffs it against each incoming string. Kept in lockstep with `#markers`.
  #prevJson = '{"markers":[]}';
  // A scene (raw JSON string) that arrived before the style finished loading,
  // applied on `load`.
  #pendingScene = null;
  // A camera command issued before the map was ready, run once it loads.
  #pendingCamera = null;

  attributeChangedCallback(name, _oldValue, value) {
    if (value == null) return;

    if (name === "config") {
      this.#config = JSON.parse(value);
      this.#init();
    } else if (name === "scene") {
      // Pass the raw string through: only Strings cross the FFI, so the
      // decode/diff/encode all happen inside Gleam.
      if (this.#ready) this.#applyScene(value);
      else this.#pendingScene = value;
    }
  }

  connectedCallback() {
    this.#init();
  }

  disconnectedCallback() {
    if (this.#map) {
      this.#map.remove();
      this.#map = null;
    }
    this.#markers.clear();
    // Reset the diff baseline too, so a future reconnect re-adds from scratch
    // instead of issuing moves/updates against markers that no longer exist.
    this.#prevJson = '{"markers":[]}';
    this.#ready = false;
  }

  // Create the map once both the config and the DOM connection are in place.
  #init() {
    if (this.#map || !this.#config || !this.isConnected) return;

    // The element is the map container; it must be a sized block.
    if (!this.style.display) this.style.display = "block";

    const cfg = this.#config;
    this.#map = new (maplibre().Map)({
      container: this,
      style: cfg.style_url,
      center: [cfg.lng, cfg.lat],
      zoom: cfg.zoom,
    });

    this.#map.on("load", () => {
      this.#ready = true;
      if (this.#pendingScene) {
        this.#applyScene(this.#pendingScene);
        this.#pendingScene = null;
      }
      if (this.#pendingCamera) {
        this.#pendingCamera();
        this.#pendingCamera = null;
      }
    });

    // A tap on the map background (not a marker — marker taps stopPropagation).
    this.#map.on("click", (e) => {
      this.dispatchEvent(
        new CustomEvent("maplibre:click", {
          detail: { lng: e.lngLat.lng, lat: e.lngLat.lat },
        }),
      );
    });
  }

  // Reconcile to a new scene. The decision (what changed) is the pure Gleam
  // `diff_json`; this shell only applies the resulting ops to the live map.
  #applyScene(json) {
    const ops = JSON.parse(diff_json(this.#prevJson, json));
    this.#apply(ops);
    this.#prevJson = json;
  }

  // Apply the ordered ops in sequence. Move/remove/set_html guard on the marker
  // existing so a stray op can never throw.
  #apply(ops) {
    for (const op of ops) {
      switch (op.op) {
        case "add":
          this.#addMarker(op);
          break;
        case "remove": {
          const marker = this.#markers.get(op.key);
          if (marker) {
            marker.remove();
            this.#markers.delete(op.key);
          }
          break;
        }
        case "move": {
          const marker = this.#markers.get(op.key);
          if (marker) marker.setLngLat([op.lng, op.lat]);
          break;
        }
        case "set_html": {
          const marker = this.#markers.get(op.key);
          if (marker) marker.getElement().innerHTML = op.html;
          break;
        }
      }
    }
  }

  #addMarker({ key, lng, lat, html }) {
    const el = document.createElement("div");
    el.innerHTML = html; // arbitrary SVG/HTML
    el.style.cursor = "pointer";
    el.addEventListener("click", (event) => {
      // Keep a marker tap from also reaching the map's background `click`, so
      // selecting a pin never doubles as a place/deselect gesture.
      event.stopPropagation();
      this.dispatchEvent(
        new CustomEvent("maplibre:markerclick", { detail: { id: key } }),
      );
    });

    const marker = new (maplibre().Marker)({ element: el })
      .setLngLat([lng, lat])
      .addTo(this.#map);

    this.#markers.set(key, marker);
  }

  // Camera command. Queued until the map is ready.
  fitBounds(swLng, swLat, neLng, neLat, padding) {
    const run = () =>
      this.#map.fitBounds(
        [
          [swLng, swLat],
          [neLng, neLat],
        ],
        { padding },
      );
    if (this.#ready) run();
    else this.#pendingCamera = run;
  }
}

if (
  typeof customElements !== "undefined" &&
  !customElements.get("maplibre-map")
) {
  customElements.define("maplibre-map", MaplibreMap);
}

// The camera command crosses the FFI as a plain call keyed by the element id;
// the element instance is the handle.
export function fitBounds(id, swLng, swLat, neLng, neLat, padding) {
  const el = document.getElementById(id);
  if (el && el.fitBounds) el.fitBounds(swLng, swLat, neLng, neLat, padding);
}
