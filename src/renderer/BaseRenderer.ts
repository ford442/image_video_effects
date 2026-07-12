// Re-export canonical renderer types (IRenderer supersedes this module's legacy name).
export type { IRenderer, Renderer, RendererConfig } from './Renderer';
export { DEFAULT_CONFIG } from './Renderer';

/** @deprecated Use IRenderer from './Renderer'. */
export type BaseRenderer = import('./Renderer').IRenderer;
