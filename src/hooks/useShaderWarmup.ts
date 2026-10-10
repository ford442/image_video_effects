import { RefObject, useEffect } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { ShaderEntry } from '../renderer/types';
import { setShaderWarmupHandler } from '../renderer/shaderWarmupSink';

/** Route gallery warm-up requests (ids) to the renderer with their catalog URLs. */
export function useShaderWarmup(
  rendererRef: RefObject<RendererManager | null>,
  availableModesRef: RefObject<ShaderEntry[]>,
): void {
  useEffect(
    () =>
      setShaderWarmupHandler((ids) => {
        const byId = new Map((availableModesRef.current ?? []).map((m) => [m.id, m]));
        const entries = ids.flatMap((id) => {
          const entry = byId.get(id);
          return entry?.url ? [{ id, url: entry.url }] : [];
        });
        rendererRef.current?.warmShaders(entries);
      }),
    [rendererRef, availableModesRef],
  );
}
