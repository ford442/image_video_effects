/**
 * wasmBackend.ts
 *
 * Type guard for the R&D-frozen WASM renderer. Everything outside the
 * `?renderer=wasm` branch uses this guard (not an instanceof check) so
 * the renderer (and the bridge it drags in) stays out of the main bundle: this
 * module only has a type import of it.
 */

import type { WASMRenderer } from './WASMRenderer';

export function isWasmBackend(renderer: unknown): renderer is WASMRenderer {
  return !!renderer && (renderer as { backendKind?: unknown }).backendKind === 'wasm';
}
