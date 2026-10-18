// Main-bundle side of the OSC bridge: flag parsing + the lazy chunk loader.
// Everything else (decoder, router, socket) lives in the "osc" chunk.

/** Local storage_manager (uvicorn default port 7860) with OSC_RELAY_ENABLED=1. */
export const DEFAULT_OSC_WS_URL = 'ws://127.0.0.1:7860/osc/ws';
export const OSC_ENABLED_STORAGE_KEY = 'vj_osc_enabled';
export const OSC_URL_STORAGE_KEY = 'vj_osc_ws_url';

function params(search: string): URLSearchParams | null {
  try {
    return new URLSearchParams(search);
  } catch {
    return null;
  }
}

/**
 * `?osc` / `?osc=1` / `?osc=true` → true, `?osc=0` / `?osc=false` → false,
 * absent → null (fall back to the persisted Studio toggle).
 */
export function oscFlagFromSearch(search: string = typeof window !== 'undefined' ? window.location.search : ''): boolean | null {
  const p = params(search);
  if (!p || !p.has('osc')) return null;
  const v = (p.get('osc') ?? '').trim().toLowerCase();
  if (v === '0' || v === 'false' || v === 'off') return false;
  return true;
}

/** `?osc_ws=ws://host:port/path` override; only ws:/wss: URLs are honoured. */
export function oscWsUrlFromSearch(search: string = typeof window !== 'undefined' ? window.location.search : ''): string | null {
  const raw = params(search)?.get('osc_ws');
  if (!raw) return null;
  try {
    const u = new URL(raw);
    return u.protocol === 'ws:' || u.protocol === 'wss:' ? u.toString() : null;
  } catch {
    return null;
  }
}

type OscBridgeModule = typeof import('./oscBridge');
let modulePromise: Promise<OscBridgeModule> | null = null;

/** Lazy "osc" chunk — never in the 320 KiB main budget. */
export function loadOscBridge(): Promise<OscBridgeModule> {
  if (!modulePromise) {
    modulePromise = import(/* webpackChunkName: "osc" */ './oscBridge').catch((err) => {
      modulePromise = null;
      throw err;
    });
  }
  return modulePromise;
}
