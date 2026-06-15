// The `<maplibre-map>` custom element: the live, mutable MapLibre `Map` lives
// here, never in the Gleam model. Lustre renders the element and sets two
// string attributes — `config` (init-only) and `scene` (a JSON description of
// the markers) — and the element reconciles the scene into the map, adding,
// moving, and removing only the markers that changed.
//
// MapLibre is loaded by the host page via a CDN <script>, exposing the global
// `window.maplibregl`. We read it lazily (inside the element) so this module
// can be imported before the CDN script has run.

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
  // key -> { marker, data }, so successive scenes can be diffed by key.
  #markers = new Map();
  // A scene that arrived before the style finished loading, applied on `load`.
  #pendingScene = null;
  // The latest camera command issued before the map was ready (last one wins).
  #pendingCamera = null;

  attributeChangedCallback(name, _oldValue, value) {
    if (value == null) return;

    if (name === "config") {
      this.#config = JSON.parse(value);
      this.#init();
    } else if (name === "scene") {
      const scene = JSON.parse(value);
      if (this.#ready) this.#applyScene(scene);
      else this.#pendingScene = scene;
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

  // The keyed diff: the heart of the reconciler. Compare the incoming markers
  // (by key) against the live ones and issue the minimal set of changes.
  #applyScene(scene) {
    const next = new Map((scene.markers || []).map((m) => [m.key, m]));

    for (const [key, entry] of this.#markers) {
      if (!next.has(key)) {
        entry.marker.remove();
        this.#markers.delete(key);
      }
    }

    for (const [key, data] of next) {
      const existing = this.#markers.get(key);
      if (!existing) {
        this.#addMarker(key, data);
      } else {
        if (existing.data.lng !== data.lng || existing.data.lat !== data.lat) {
          existing.marker.setLngLat([data.lng, data.lat]);
        }
        if (existing.data.html !== data.html) {
          existing.marker.getElement().innerHTML = data.html;
        }
        existing.data = data;
      }
    }
  }

  #addMarker(key, data) {
    const el = document.createElement("div");
    el.innerHTML = data.html; // arbitrary SVG/HTML
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
      .setLngLat([data.lng, data.lat])
      .addTo(this.#map);

    this.#markers.set(key, { marker, data });
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
// the element instance (not a registry) is the handle.
export function fitBounds(id, swLng, swLat, neLng, neLat, padding) {
  const el = document.getElementById(id);
  if (el && el.fitBounds) el.fitBounds(swLng, swLat, neLng, neLat, padding);
}
