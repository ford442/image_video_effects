import fs from 'fs';
import path from 'path';

const SRC_ROOT = path.join(__dirname, '..');
// Removed renderer demo/toggle modules (they loaded a nonexistent /wasm/wasm_renderer_test.js).
// Backend switching lives in RendererManager + useRendererBackend.
// RendererSwitcher / RendererBackendPanel: Controls toggle removed when WASM froze as R&D (#1080);
// WASM is reachable only via ?renderer=wasm.
const REMOVED_MODULES = [
  'RendererToggle',
  'RendererContext',
  'ShaderDemo',
  'WASMToggle',
  'useWASM',
  'RendererSwitcher',
  'RendererBackendPanel',
];

function collectSourceFiles(dir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '__tests__') continue;
      files.push(...collectSourceFiles(fullPath));
      continue;
    }
    if (/\.(ts|tsx)$/.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

describe('removed renderer toggle modules', () => {
  test.each(REMOVED_MODULES)('%s is not imported anywhere in src', (name) => {
    const importRe = new RegExp(`from\\s+['"][^'"]*/${name}['"]`);
    const offenders = collectSourceFiles(SRC_ROOT)
      .filter((file) => importRe.test(fs.readFileSync(file, 'utf8')))
      .map((file) => path.relative(SRC_ROOT, file));
    expect(offenders).toEqual([]);
  });
});
