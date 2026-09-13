/**
 * @jest-environment jsdom
 *
 * Regression for #1234: Jest must resolve the TypeScript WASM barrel
 * (explicit .js specifiers → .ts) without a GPU or emcc.
 * Fails if craco's mapper stops mapping ./bridge/api.js to api.ts.
 */

import * as staticBridge from '../wasm/wasm_bridge';

describe('WASM bridge Jest resolution', () => {
  it('resolves a static import of the TypeScript barrel', () => {
    expect(typeof staticBridge.initWasmRenderer).toBe('function');
    expect(typeof staticBridge.setInputSource).toBe('function');
    expect(staticBridge.default).toBeTruthy();
    expect(typeof staticBridge.default.initWasmRenderer).toBe('function');
  });

  it('resolves a dynamic import after resetModules (same path as uniforms tests)', async () => {
    jest.resetModules();
    const bridge = await import('../wasm/wasm_bridge');
    expect(typeof bridge.initWasmRenderer).toBe('function');
    expect(typeof bridge.setInputSource).toBe('function');
    expect(bridge.default).toBeTruthy();
    expect(typeof bridge.default.initWasmRenderer).toBe('function');
  });
});
