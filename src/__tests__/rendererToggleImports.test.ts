/**
 * #1311 WP-A item 7 — dead renderer code stays deleted.
 * The demo RendererToggle/RendererContext/ShaderDemo loaded a nonexistent /wasm/wasm_renderer_test.js,
 * useWASM was only imported by tests, and the boot probe ladder is the only adapter ladder.
 * (The live Controls renderer toggle is a different component — issue #1329.)
 */
import fs from 'fs';
import path from 'path';
import * as devicePolicy from '../renderer/webgpuDevicePolicy';

const SRC_ROOT = path.join(__dirname, '..');
const DELETED = [
  'components/shaders/RendererContext.tsx',
  'components/shaders/RendererToggle.tsx',
  'components/shaders/ShaderDemo.tsx',
  'hooks/useWASM.ts',
];

function collectSourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules') files.push(...collectSourceFiles(fullPath));
    } else if (/\.(ts|tsx)$/.test(entry.name) && fullPath !== __filename) {
      files.push(fullPath);
    }
  }
  return files;
}

describe('dead renderer code (#1311 WP-A)', () => {
  test.each(DELETED)('%s is deleted', (rel) => {
    expect(fs.existsSync(path.join(SRC_ROOT, rel))).toBe(false);
  });

  test('nothing imports the deleted modules or the nonexistent wasm_renderer_test.js', () => {
    const offenders = collectSourceFiles(SRC_ROOT).filter((file) => {
      const content = fs.readFileSync(file, 'utf8');
      return /from\s+['"][^'"]*\/(RendererToggle|RendererContext|ShaderDemo|useWASM)['"]/.test(content)
        || content.includes('wasm_renderer_test');
    });
    expect(offenders.map((f) => path.relative(SRC_ROOT, f))).toEqual([]);
  });

  test('webgpuDevicePolicy has no second adapter ladder', () => {
    expect('requestAdapterWithFallback' in devicePolicy).toBe(false);
  });

  test('WebGPUCanvas has no log-only video "buffering" effect and no empty WebGPURenderer.render()', () => {
    const canvas = fs.readFileSync(path.join(SRC_ROOT, 'components/WebGPUCanvas.tsx'), 'utf8');
    expect(canvas).not.toMatch(/Video Buffering|bufferingStartedRef/);
    const webgpu = fs.readFileSync(path.join(SRC_ROOT, 'renderer/WebGPURenderer.ts'), 'utf8');
    expect(webgpu).not.toMatch(/render\(\): void \{\}/);
  });
});
