// ═══════════════════════════════════════════════════════════════════════════════
//  vjPresets.ts
//  Per-shader param presets + randomizer for the AI VJ shader stack.
// ═══════════════════════════════════════════════════════════════════════════════

import { CatalogShader } from './shaderCatalog';

export interface VJPreset {
  id: string;
  name: string;
  shaderIds: string[];
  params: Record<string, number>[];
  timestamp: number;
}

const STORAGE_KEY = 'vj_presets';
const MAX_ENTRIES = 50;

export function savePreset(
  name: string,
  shaderIds: string[],
  params: Record<string, number>[]
): VJPreset {
  const presets = loadPresets();
  const newPreset: VJPreset = {
    id: crypto.randomUUID(),
    name: name.trim(),
    shaderIds,
    params,
    timestamp: Date.now(),
  };
  presets.unshift(newPreset);
  if (presets.length > MAX_ENTRIES) {
    presets.length = MAX_ENTRIES;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(presets));
  return newPreset;
}

export function loadPresets(): VJPreset[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    return [];
  }
}

export function deletePreset(id: string): void {
  const presets = loadPresets().filter(p => p.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(presets));
}

export function randomizeParams(
  shaderIds: string[],
  catalog: CatalogShader[]
): Record<string, number>[] {
  return shaderIds.map(id => {
    const shader = catalog.find(s => s.id === id);
    if (!shader) return {};

    const params: Record<string, number> = {};
    for (const param of shader.params) {
      const raw = Math.random() * (param.max - param.min) + param.min;
      if (param.step !== undefined && param.step > 0) {
        const steps = Math.round((raw - param.min) / param.step);
        let snapped = param.min + steps * param.step;
        // Clamp to [min, max] to guard against floating-point overshoot
        snapped = Math.max(param.min, Math.min(param.max, snapped));
        params[param.id] = snapped;
      } else {
        params[param.id] = raw;
      }
    }
    return params;
  });
}
