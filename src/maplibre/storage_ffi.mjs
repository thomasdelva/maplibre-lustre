// A tiny, defensive wrapper around window.localStorage.
//
// Storage access can throw (private mode, disabled cookies) or be absent
// entirely, so every call is guarded. Reads yield `undefined` on miss/failure
// (which the Gleam side decodes to `Error(Nil)`); writes are dropped silently.

export function getItem(key) {
  try {
    return globalThis.localStorage?.getItem(key) ?? undefined;
  } catch (_) {
    return undefined;
  }
}

export function setItem(key, value) {
  try {
    globalThis.localStorage?.setItem(key, value);
  } catch (_) {
    // Ignore: persistence is best-effort.
  }
}

export function removeItem(key) {
  try {
    globalThis.localStorage?.removeItem(key);
  } catch (_) {
    // Ignore: persistence is best-effort.
  }
}
