/**
 * The renderer the render worker hosts. Kept out of render.worker.ts (which
 * wires `self` on import) so the thread it reports can be tested.
 */

import type { RendererConfig } from '../Renderer';
import { WebGPURenderer } from '../WebGPURenderer';

export function createWorkerRenderer(config: RendererConfig): WebGPURenderer {
  return new WebGPURenderer(config, { thread: 'worker' });
}
