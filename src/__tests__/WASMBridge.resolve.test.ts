/**
 * @vitest-environment jsdom
 *
 * Regression for #1234: Vitest must resolve the TypeScript WASM barrel
 * (explicit .js specifiers → .ts) without a GPU or emcc.
 * Fails if `.js` ESM specifiers stop resolving to their `.ts` sources.
 */

import * as staticBridge from '../wasm/wasm_bridge';

describe('WASM bridge test resolution', () => {
  it('resolves a static import of the TypeScript barrel', () => {
    expect(typeof staticBridge.initWasmRenderer).toBe('function');
    expect(typeof staticBridge.setInputSource).toBe('function');
    expect(staticBridge.default).toBeTruthy();
    expect(typeof staticBridge.default.initWasmRenderer).toBe('function');
  });

  it('resolves a dynamic import after resetModules (same path as uniforms tests)', async () => {
    vi.resetModules();
    const bridge = await import('../wasm/wasm_bridge');
    expect(typeof bridge.initWasmRenderer).toBe('function');
    expect(typeof bridge.setInputSource).toBe('function');
    expect(bridge.default).toBeTruthy();
    expect(typeof bridge.default.initWasmRenderer).toBe('function');
  });
});
