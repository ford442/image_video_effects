import * as fs from 'fs';
import * as path from 'path';
import { isWasmBackend } from './wasmBackend';

describe('isWasmBackend', () => {
  it('recognises only the wasm backendKind', () => {
    expect(isWasmBackend({ backendKind: 'wasm' })).toBe(true);
    expect(isWasmBackend({ backendKind: 'webgpu' })).toBe(false);
    expect(isWasmBackend({})).toBe(false);
    expect(isWasmBackend(null)).toBe(false);
    expect(isWasmBackend(undefined)).toBe(false);
  });
});

/**
 * The WASM renderer is R&D-frozen (`?renderer=wasm` only, #1329) and the main bundle has
 * almost no budget left, so nothing may import it as a value except through `import()`.
 * Type-only imports are erased and fine.
 */
describe('WASMRenderer stays out of the main bundle', () => {
  const SRC = path.join(__dirname, '..');
  const OWN = path.join(SRC, 'renderer', 'WASMRenderer.ts');

  function sourceFiles(dir: string, out: string[] = []): string[] {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === '__tests__' || entry.name === 'wasm' || entry.name === 'node_modules') continue;
        sourceFiles(full, out);
      } else if (/\.(ts|tsx)$/.test(entry.name) && !/\.(test|spec)\.(ts|tsx)$/.test(entry.name)) {
        out.push(full);
      }
    }
    return out;
  }

  const files = sourceFiles(SRC).filter((f) => f !== OWN);

  it('scans the app source', () => {
    expect(files.length).toBeGreaterThan(100);
  });

  it('has no value import or re-export of WASMRenderer', () => {
    const valueImport = /^\s*(?:import|export)\s+(?!type\b)[^;]*?from\s+['"][^'"]*\/WASMRenderer['"]/m;
    const offenders = files.filter((f) => valueImport.test(fs.readFileSync(f, 'utf8')));
    expect(offenders.map((f) => path.relative(SRC, f))).toEqual([]);
  });

  it('never uses instanceof WASMRenderer (use isWasmBackend)', () => {
    const offenders = files.filter((f) => /instanceof\s+WASMRenderer/.test(fs.readFileSync(f, 'utf8')));
    expect(offenders.map((f) => path.relative(SRC, f))).toEqual([]);
  });
});
