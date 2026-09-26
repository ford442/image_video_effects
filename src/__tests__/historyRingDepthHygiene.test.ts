import fs from 'fs';
import path from 'path';

const repoRoot = process.cwd();
const shaderDir = path.join(repoRoot, 'public', 'shaders');

// Any shader that samples binding 13 (historyTexture) must wrap its ring
// reads at textureNumLayers(historyTexture) — the ring is allocated as
// 8, 4 or 1 layers depending on the VRAM probe (renderer/webgpu/frame.ts),
// and the write head wraps at that allocated count. A shader that instead
// hardcodes a literal ring depth (e.g. `const HISTORY_DEPTH: u32 = 8u`)
// will read out-of-range layers on a 4- or 1-layer device; WGSL clamps
// those to the last layer, so ages come back scrambled — silently.
const findWgslFiles = (dir: string): string[] => {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...findWgslFiles(entryPath));
      continue;
    }
    if (entry.name.endsWith('.wgsl')) {
      files.push(entryPath);
    }
  }
  return files;
};

describe('history ring depth hygiene', () => {
  const historyShaders = findWgslFiles(shaderDir).filter((file) => {
    const src = fs.readFileSync(file, 'utf8');
    // Only shaders that actually declare the binding-13 var — a doc file
    // like _prelude.wgsl can mention "historyTexture" in prose without
    // using it.
    return /@group\(0\)\s*@binding\(13\)\s*var\s+historyTexture\s*:/.test(src);
  });

  it('finds at least the known binding-13 history-ring shaders', () => {
    expect(historyShaders.length).toBeGreaterThanOrEqual(10);
  });

  it('never hardcodes a literal history ring depth next to historyTexture', () => {
    const offenders = historyShaders
      .filter((file) => /\bHISTORY_DEPTH\b\s*:\s*u32\s*=/.test(fs.readFileSync(file, 'utf8')))
      .map((file) => path.relative(repoRoot, file));
    expect(offenders).toEqual([]);
  });

  it('wraps every history-ring read at textureNumLayers(historyTexture)', () => {
    const offenders = historyShaders
      .filter((file) => !/textureNumLayers\s*\(\s*historyTexture\s*\)/.test(fs.readFileSync(file, 'utf8')))
      .map((file) => path.relative(repoRoot, file));
    expect(offenders).toEqual([]);
  });
});
