/**
 * slotOrchestration.ts
 *
 * Pure seams for shader-slot enable/mode/params forwarding across WebGPU and WASM backends.
 * Duck-typed ShaderSlotRenderer resolution matches #887 WASM parity contract.
 */

import { ShaderSlotRenderer, SlotZoomParamsUpdate } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { Renderer } from './Renderer';
import { InputSource, RenderMode, ShaderEntry, SlotParams } from './types';
import { getGraphEntryIds, hasGraph } from './multipassRegistry';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';
import { resolveShaderId } from '../utils/resolveShaderId';

export const SLOT_COUNT = 3;

export interface ShaderLoadMeta {
  requiresDeepWorkgroup?: boolean;
  requiresHistoryRing?: boolean;
  requiresRgba32Float?: boolean;
}

export interface SlotOrchestrationPolicy {
  maxActiveSlots: number;
  preferNonDeepVariants: boolean;
}

export interface SlotOrchestrationCallbacks {
  onFp32Required: (shaderId: string) => void;
}

/** Returns the shader-capable backend, or null for Canvas2D fallback. */
export function resolveShaderBackend(renderer: Renderer | null): ShaderSlotRenderer | null {
  if (!renderer || renderer instanceof JSRenderer) return null;
  const candidate = renderer as ShaderSlotRenderer;
  if (
    typeof candidate.loadShader === 'function' &&
    typeof candidate.setSlotShader === 'function' &&
    typeof candidate.updateSlotParams === 'function'
  ) {
    return candidate;
  }
  return null;
}

export function supportsShaderEffects(renderer: Renderer | null): boolean {
  return resolveShaderBackend(renderer) !== null;
}

export function setSlotShader(
  backend: ShaderSlotRenderer | null,
  policy: SlotOrchestrationPolicy,
  index: number,
  id: string,
): void {
  if (!backend) return;
  if (id && index >= policy.maxActiveSlots) {
    console.warn(
      `[RendererManager] Slot ${index} exceeds quality cap (${policy.maxActiveSlots} max)`,
    );
    return;
  }
  backend.setSlotShader(index, id);
}

export function setSlotParams(
  backend: ShaderSlotRenderer | null,
  slotIndex: number,
  p1: number,
  p2: number,
  p3: number,
  p4: number,
): void {
  if (!backend) return;
  if (backend.setSlotParams) {
    backend.setSlotParams(slotIndex, p1, p2, p3, p4);
  } else {
    backend.updateSlotParams(
      { zoomParam1: p1, zoomParam2: p2, zoomParam3: p3, zoomParam4: p4 },
      slotIndex,
    );
  }
}

export function updateSlotParams(
  backend: ShaderSlotRenderer | null,
  params: SlotZoomParamsUpdate,
  slotIndex = 0,
): void {
  backend?.updateSlotParams(params, slotIndex);
}

export function syncAllSlotParams(
  backend: ShaderSlotRenderer | null,
  slotParams: SlotParams[],
  maxSlots = SLOT_COUNT,
): void {
  if (!backend || slotParams.length === 0) return;
  const count = Math.min(maxSlots, slotParams.length);
  for (let i = 0; i < count; i++) {
    const p = slotParams[i];
    updateSlotParams(
      backend,
      {
        zoomParam1: p.zoomParam1,
        zoomParam2: p.zoomParam2,
        zoomParam3: p.zoomParam3,
        zoomParam4: p.zoomParam4,
      },
      i,
    );
  }
}

export async function loadShaderForBackend(
  backend: ShaderSlotRenderer | null,
  policy: SlotOrchestrationPolicy,
  callbacks: SlotOrchestrationCallbacks,
  id: string,
  url: string,
  meta?: ShaderLoadMeta,
): Promise<boolean> {
  if (!backend) return false;

  if (meta?.requiresDeepWorkgroup && policy.preferNonDeepVariants) {
    console.log(
      `[RendererManager] Skipping "${id}" — deep-workgroup variant disabled by quality policy`,
    );
    return false;
  }

  if (meta?.requiresRgba32Float) {
    callbacks.onFp32Required(id);
  }

  try {
    const ok = await backend.loadShader(id, url);
    if (ok && hasGraph(id)) {
      const entries = getGraphEntryIds(id);
      await Promise.all(
        entries
          .filter((entryId) => entryId !== id)
          .map((entryId) =>
            backend.loadShader(entryId, resolveShaderUrl(`shaders/${entryId}.wgsl`)).catch(() => false),
          ),
      );
    }
    if (process.env.NODE_ENV === 'development' && ok && meta?.requiresHistoryRing) {
      console.log(`[RendererManager] Loaded history-ring shader "${id}" (binding 13)`);
    }
    return ok;
  } catch (err) {
    console.warn(`[RendererManager] loadShader("${id}") failed:`, err);
    return false;
  }
}

export async function loadShadersForBackend(
  backend: ShaderSlotRenderer | null,
  policy: SlotOrchestrationPolicy,
  callbacks: SlotOrchestrationCallbacks,
  shaders: ShaderEntry[],
  loadOne: (id: string, url: string, meta?: ShaderLoadMeta) => Promise<boolean>,
): Promise<void> {
  if (!backend) return;
  const results = await Promise.allSettled(
    shaders.map((s) =>
      loadOne(s.id, s.url, {
        requiresDeepWorkgroup: s.requiresDeepWorkgroup,
        requiresHistoryRing: s.requiresHistoryRing,
        requiresRgba32Float: s.requiresRgba32Float,
      }),
    ),
  );
  const failed = results.filter(
    (r) => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value),
  ).length;
  if (failed > 0) {
    console.warn(`[RendererManager] loadShaders: ${failed}/${shaders.length} shader(s) failed`);
  }
}

export async function resyncShaderStack(
  backend: ShaderSlotRenderer | null,
  policy: SlotOrchestrationPolicy,
  callbacks: SlotOrchestrationCallbacks,
  loadOne: (id: string, url: string, meta?: ShaderLoadMeta) => Promise<boolean>,
  setInputSource: (source: InputSource) => void,
  options: {
    modes: RenderMode[];
    slotParams: SlotParams[];
    resolveShader: (shaderId: string) => ShaderEntry | undefined;
    inputSource?: InputSource;
  },
): Promise<void> {
  if (!backend) return;

  if (options.inputSource) {
    setInputSource(options.inputSource);
  }

  for (let i = 0; i < Math.min(SLOT_COUNT, options.modes.length); i++) {
    const mode = options.modes[i];
    if (!mode || mode === 'none') {
      setSlotShader(backend, policy, i, '');
      continue;
    }

    const entry = options.resolveShader(resolveShaderId(mode));
    if (!entry) {
      console.warn(`[RendererManager] resyncShaderStack: no entry for "${mode}" on slot ${i}`);
      continue;
    }

    const ok = await loadOne(entry.id, entry.url, {
      requiresDeepWorkgroup: entry.requiresDeepWorkgroup,
      requiresHistoryRing: entry.requiresHistoryRing,
      requiresRgba32Float: entry.requiresRgba32Float,
    });
    if (ok) {
      setSlotShader(backend, policy, i, entry.id);
    } else {
      console.warn(`[RendererManager] resyncShaderStack: failed to load "${entry.id}" for slot ${i}`);
    }
  }

  syncAllSlotParams(backend, options.slotParams);
}

export function setSlotMode(
  backend: ShaderSlotRenderer | null,
  index: number,
  mode: 'chained' | 'parallel',
): void {
  backend?.setSlotMode(index, mode);
}

export function setActiveShader(backend: ShaderSlotRenderer | null, id: string): void {
  backend?.setActiveShader(id);
}

export function addRipple(backend: ShaderSlotRenderer | null, x: number, y: number): void {
  backend?.addRipple(x, y);
}

export function clearRipples(backend: ShaderSlotRenderer | null): void {
  backend?.clearRipples();
}

export async function reloadShaderOnBackend(
  renderer: Renderer | null,
  backend: ShaderSlotRenderer | null,
  id: string,
  url: string,
): Promise<boolean> {
  if (!backend) return false;
  const r = renderer as { reloadShaderFromURL?: (shaderId: string, shaderUrl: string) => Promise<boolean> } | null;
  if (r?.reloadShaderFromURL) {
    return r.reloadShaderFromURL(id, url);
  }
  return backend.loadShader(id, url);
}

export function firePlasmaOnBackend(
  renderer: Renderer | null,
  backend: ShaderSlotRenderer | null,
  x: number,
  y: number,
  vx: number,
  vy: number,
): void {
  const r = renderer as {
    firePlasma?: (px: number, py: number, pvx: number, pvy: number) => void;
  } | null;
  if (r?.firePlasma) {
    r.firePlasma(x, y, vx, vy);
    return;
  }
  addRipple(backend, x, y);
}
