// The `<maplibre-map>` custom element: the live, mutable MapLibre `Map` lives
// here, never in the Gleam model. Lustre renders the element, sets the `config`
// (init-only) string attribute and the `scene` DOM *property* (a plain object
// describing the markers), and the element reconciles the scene into the map,
// adding, moving, and removing only the markers that changed.
//
// `scene` is a DOM property (not a string attribute), so the object crosses
// without a JSON round-trip.
//
// MapLibre is loaded by the host page via a CDN <script>, exposing the global
// `window.maplibregl`. We read it lazily (inside the element) so this module
// can be imported before the CDN script has run.

// The keyed diff is a pure Gleam function (the functional core). The element
// is the imperative shell: it asks `diff_dynamic` what changed between two
// scene objects, then applies the resulting ops to the live map. `reconcile`
// has no FFI externs, so this import is one-way (no cycle).
import { diff_dynamic } from "./maplibre/reconcile.mjs";

// The baseline `diff_dynamic` diffs the first scene against, and what the diff
// resets to on disconnect: an empty marker set.
const EMPTY_SCENE = { markers: [] };

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
    return ["config"];
  }

  #map = null;
  #ready = false;
  #config = null;
  // key -> live maplibregl.Marker. The diff against the previous scene decides
  // which of these to add, move, remove, or re-html.
  #markers = new Map();
  // The previous scene object we last applied; `diff_dynamic` diffs it against
  // each incoming scene. Kept in lockstep with `#markers`.
  #prevScene = EMPTY_SCENE;
  // The most recent scene assigned via the property, reflected back by `get
  // scene`.
  #scene = EMPTY_SCENE;
  // A scene object that arrived before the style finished loading, applied on
  // `load`.
  #pendingScene = null;
  // A camera command issued before the map was ready, run once it loads.
  #pendingCamera = null;

  // The `scene` DOM property: frameworks (Lustre included) assign a plain
  // object, so nothing is stringified on the way in.
  set scene(scene) {
    this.#scene = scene;
    if (this.#ready) this.#applyScene(scene);
    else this.#pendingScene = scene;
  }

  get scene() {
    return this.#scene;
  }

  attributeChangedCallback(name, _oldValue, value) {
    if (name === "config" && value != null) {
      this.#config = JSON.parse(value);
      this.#init();
    }
  }

  connectedCallback() {
    // A property assigned before the element was upgraded shadows this accessor
    // with an own data property; reclaim it so the assignment isn't lost.
    this.#upgradeProperty("scene");
    this.#init();
  }

  #upgradeProperty(name) {
    if (Object.prototype.hasOwnProperty.call(this, name)) {
      const value = this[name];
      delete this[name];
      this[name] = value;
    }
  }

  disconnectedCallback() {
    if (this.#map) {
      this.#map.remove();
      this.#map = null;
    }
    this.#markers.clear();
    // Reset the diff baseline too, so a future reconnect re-adds from scratch
    // instead of issuing moves/updates against markers that no longer exist.
    this.#prevScene = EMPTY_SCENE;
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
  // `diff_dynamic`; this shell only applies the resulting ops to the live map.
  #applyScene(scene) {
    const ops = JSON.parse(diff_dynamic(this.#prevScene, scene));
    this.#apply(ops);
    this.#prevScene = scene;
  }

  // Apply the ordered ops in sequence. Every op but `add` targets an existing
  // marker, so we look it up once and skip if it's gone — a stray op can never
  // throw.
  #apply(ops) {
    for (const op of ops) {
      if (op.op === "add") {
        this.#addMarker(op);
        continue;
      }

      const marker = this.#markers.get(op.key);
      if (!marker) continue;

      switch (op.op) {
        case "remove":
          marker.remove();
          this.#markers.delete(op.key);
          break;
        case "move":
          marker.setLngLat([op.lng, op.lat]);
          break;
        case "set_html":
          marker.getElement().innerHTML = op.html;
          break;
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
