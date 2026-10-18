/**
 * shaderWarmupSink.ts
 *
 * Decouples "the user is looking at these shaders" (ShaderGallery) from the
 * renderer that can pre-compile them, without threading a callback through
 * AppShell's prop tree. One handler at a time; the app registers it.
 */

export type ShaderWarmupHandler = (ids: string[]) => void;

let handler: ShaderWarmupHandler | null = null;

/** Register the warm-up handler; returns an unregister function. */
export function setShaderWarmupHandler(next: ShaderWarmupHandler): () => void {
  handler = next;
  return () => {
    if (handler === next) handler = null;
  };
}

/** Ask for these shader ids to be compiled ahead of use (most important first). */
export function requestShaderWarmup(ids: string[]): void {
  if (ids.length > 0) handler?.(ids);
}
