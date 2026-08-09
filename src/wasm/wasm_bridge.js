// CANONICAL WASM bridge barrel.
/**
 * Pixelocity WASM Renderer Bridge
 *
 * This module provides a JavaScript interface to the C++ WebGPU renderer.
 * It re-exports modular ES bridge units for drop-in compatibility.
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
