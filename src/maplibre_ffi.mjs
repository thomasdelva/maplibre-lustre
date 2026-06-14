// Imperative MapLibre GL JS calls, kept on the JS side of the FFI boundary.
//
// MapLibre is loaded by the host page via a CDN <script>, exposing the global
// `window.maplibregl`. We read it lazily (inside the functions) so this module
// can be imported before the CDN script has run.

// containerId -> { map, markers: [] }
//
// The live, mutable map lives here, never in the Gleam model. Gleam effects
// look it up by id and mutate it.
const registry = new Map();

// containerId -> { markers?: {json, onClick}, fit?: {bounds, padding} }
//
// `set_markers`/`fit_bounds` and `init` are all dispatched as `after_paint`
// effects, and Lustre does not guarantee that a batched `init` runs before the
// `set_markers` batched with it. So a call can arrive before the map exists; we
// stash the most recent request here and flush it when `init` creates the map.
const pending = new Map();

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

export function init(id, styleUrl, lng, lat, zoom) {
  // Re-initialising the same container would leak the old map, so tear it down.
  const existing = registry.get(id);
  if (existing) existing.map.remove();

  const map = new (maplibre().Map)({
    container: id,
    style: styleUrl,
    center: [lng, lat],
    zoom: zoom,
  });

  const entry = { map, markers: [] };
  registry.set(id, entry);

  // Apply anything that was requested before the map existed.
  const queued = pending.get(id);
  if (queued) {
    pending.delete(id);
    if (queued.markers) {
      applyMarkers(entry, queued.markers.json, queued.markers.onClick);
    }
    if (queued.fit) map.fitBounds(queued.fit.bounds, { padding: queued.fit.padding });
  }
}

export function setMarkers(id, markersJson, onClick) {
  const entry = registry.get(id);
  if (!entry) {
    const queued = pending.get(id) ?? {};
    queued.markers = { json: markersJson, onClick };
    pending.set(id, queued);
    return;
  }
  applyMarkers(entry, markersJson, onClick);
}

function applyMarkers(entry, markersJson, onClick) {
  for (const m of entry.markers) m.remove();
  entry.markers = [];

  for (const data of JSON.parse(markersJson)) {
    const el = document.createElement("div");
    el.innerHTML = data.html; // arbitrary SVG/HTML (e.g. the pie marker)
    el.style.cursor = "pointer";
    el.addEventListener("click", () => onClick(data.id));

    const marker = new (maplibre().Marker)({ element: el })
      .setLngLat([data.lng, data.lat])
      .addTo(entry.map);

    entry.markers.push(marker);
  }
}

export function fitBounds(id, swLng, swLat, neLng, neLat, padding) {
  const bounds = [
    [swLng, swLat],
    [neLng, neLat],
  ];

  const entry = registry.get(id);
  if (!entry) {
    const queued = pending.get(id) ?? {};
    queued.fit = { bounds, padding };
    pending.set(id, queued);
    return;
  }

  entry.map.fitBounds(bounds, { padding });
}
