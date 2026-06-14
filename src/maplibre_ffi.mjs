// Imperative MapLibre GL JS calls, kept on the JS side of the FFI boundary.
//
// MapLibre is loaded by the host page via a CDN <script>, exposing the global
// `window.maplibregl`. We read it lazily (inside the functions) so this module
// can be imported before the CDN script has run.

// containerId -> { map, markers: [] }
//
// The live, mutable map lives here, never in the Gleam model. Gleam effects
// look it up by id and mutate it. Callers are expected to run `init` before
// `setMarkers`/`fitBounds` for a given id (sequenced via the `on_ready`
// message); if the map is missing those calls are no-ops.
const registry = new Map();

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

  registry.set(id, { map, markers: [] });
}

export function setMarkers(id, markersJson, onClick) {
  const entry = registry.get(id);
  if (!entry) return;

  for (const m of entry.markers) m.remove();
  entry.markers = [];

  for (const data of JSON.parse(markersJson)) {
    const el = document.createElement("div");
    el.innerHTML = data.html; // arbitrary SVG/HTML
    el.style.cursor = "pointer";
    el.addEventListener("click", () => onClick(data.id));

    const marker = new (maplibre().Marker)({ element: el })
      .setLngLat([data.lng, data.lat])
      .addTo(entry.map);

    entry.markers.push(marker);
  }
}

export function fitBounds(id, swLng, swLat, neLng, neLat, padding) {
  const entry = registry.get(id);
  if (!entry) return;

  entry.map.fitBounds(
    [
      [swLng, swLat],
      [neLng, neLat],
    ],
    { padding },
  );
}
