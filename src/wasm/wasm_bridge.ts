/**
 * Pixelocity WASM Renderer Bridge
 *
 * Hand-edited TypeScript barrel. Generated ESM copies live in
 * wasm_renderer/ and public/wasm/. Do not edit those copies.
 */

import wasmBridge from './bridge/api.js';

export * from './bridge/state.js';
export * from './bridge/diagnostics.js';
export * from './bridge/init.js';
export * from './bridge/wgslFormat.js';
export * from './bridge/shader.js';
export * from './bridge/uniforms.js';
export * from './bridge/capture.js';
export * from './bridge/recording.js';

export default wasmBridge;
