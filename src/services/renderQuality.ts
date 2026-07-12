import {
  RenderQualityMode,
  ResolvedPerformancePolicy,
  resolvePerformancePolicy,
  DevicePerformanceHints,
} from '../config/performancePolicy';

const STORAGE_KEY = 'px_render_quality';

const VALID_MODES: RenderQualityMode[] = ['battery', 'balanced', 'ultra', 'auto'];

export function isRenderQualityMode(value: unknown): value is RenderQualityMode {
  return typeof value === 'string' && (VALID_MODES as string[]).includes(value);
}

export function loadRenderQualityMode(): RenderQualityMode {
  if (typeof localStorage === 'undefined') return 'auto';
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (isRenderQualityMode(raw)) return raw;
  } catch {
    // ignore quota / privacy errors
  }
  return 'auto';
}

export function saveRenderQualityMode(mode: RenderQualityMode): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY, mode);
  } catch {
    // ignore
  }
}

export function buildResolvedPolicy(
  mode: RenderQualityMode,
  hints: DevicePerformanceHints,
): ResolvedPerformancePolicy {
  return resolvePerformancePolicy(mode, hints);
}
