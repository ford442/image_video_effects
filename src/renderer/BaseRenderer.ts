// Re-export canonical renderer types.
export type { Renderer, RendererConfig } from './Renderer';
export { DEFAULT_CONFIG } from './Renderer';

/** @deprecated Use Renderer from './Renderer'. */
export type BaseRenderer = import('./Renderer').Renderer;
