/**
 * rendererUrl.ts
 *
 * Dependency-free `?renderer=` readers. Kept apart from backendLifecycle.ts so UI chrome
 * (status pill, debug panel) can read the URL without importing the renderer graph.
 */

import type { RendererType } from './backendLifecycle';

/**
 * Read the preferred renderer type from the URL query string.
 *
 * Supported values for the `renderer` parameter:
 *   - `wasm`   → C++ Emscripten WASM renderer (**experimental** — see WASM_BACKEND_POLICY.md)
 *   - `webgpu` → TypeScript native WebGPU renderer (default)
 *   - `js`     → Canvas 2D fallback (no shaders)
 *
 * Example: `http://localhost:3000/?renderer=wasm`
 *
 * Related: `?no_gpu_compute` forces gpu-chores (Tier 4b) onto the TS backend.
 * See docs/GPU_CHORES.md — it does not switch the renderer.
 */
export function getRendererTypeFromURL(): RendererType | null {
  try {
    const params = new URLSearchParams(window.location.search);
    const value = params.get('renderer');
    if (value === 'wasm' || value === 'webgpu' || value === 'js') {
      return value as RendererType;
    }
    // Render-thread selectors still mean the TS WebGPU backend.
    if (value === 'worker' || value === 'main') return 'webgpu';
  } catch {
    // Not in a browser context (e.g. tests)
  }
  return null;
}

/**
 * True only when the URL explicitly forces the WASM backend (`?renderer=wasm`).
 * WASM is frozen R&D (#1080): the UI never offers it otherwise.
 */
export function isWasmForcedByURL(): boolean {
  return getRendererTypeFromURL() === 'wasm';
}
