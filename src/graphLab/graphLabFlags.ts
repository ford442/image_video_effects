// Main-bundle side of the Graph Lab: flag parsing only. The workspace itself
// (components/graphLab/) is a lazy "graph-lab" chunk. Keep this file import-free.

export const GRAPH_LAB_STORAGE_KEY = 'vj_graphlab_enabled';

/**
 * `?graphlab` / `?graphlab=1` / `?graphlab=true` → true, `?graphlab=0` /
 * `?graphlab=false` / `?graphlab=off` → false, absent → null (use the stored choice).
 */
export function graphLabFlagFromSearch(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
): boolean | null {
  let params: URLSearchParams;
  try {
    params = new URLSearchParams(search);
  } catch {
    return null;
  }
  if (!params.has('graphlab')) return null;
  const v = (params.get('graphlab') ?? '').trim().toLowerCase();
  return !(v === '0' || v === 'false' || v === 'off');
}

function readStored(): boolean {
  try {
    return window.localStorage.getItem(GRAPH_LAB_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

/** The URL flag wins and is remembered; otherwise the remembered choice applies. */
export function readGraphLabEnabled(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
): boolean {
  const fromUrl = graphLabFlagFromSearch(search);
  if (fromUrl === null) return typeof window !== 'undefined' && readStored();
  try {
    window.localStorage.setItem(GRAPH_LAB_STORAGE_KEY, fromUrl ? '1' : '0');
  } catch {
    // Private window / blocked storage: the flag still applies to this page load.
  }
  return fromUrl;
}
