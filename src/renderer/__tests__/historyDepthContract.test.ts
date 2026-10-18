import fs from 'fs';
import path from 'path';

// History ring contract (#1307). Binding 13 (historyTexture) is allocated
// as 8, 4 or 1 layers after the VRAM probe (historyTexProbe.ts), and both
// hosts wrap the write head at the ALLOCATED count (webgpu/frame.ts,
// wasm_renderer/frame.cpp). A shader that wraps its reads at a literal 8
// asks for layers that do not exist on a smaller ring; WGSL clamps those to
// the last layer, so ages come back scrambled, silently. The depth must
// come from textureNumLayers(historyTexture).
const repoRoot = process.cwd();
const shaderDir = path.join(repoRoot, 'public', 'shaders');

const declaresHistory = /\bvar\s+historyTexture\s*:/;
const samplesHistory = /\btexture(?:SampleLevel|Load)\s*\(\s*historyTexture\b/;
const readsNumLayers = /\btextureNumLayers\s*\(\s*historyTexture\s*\)/;
const literalModulus = /%\s*8u?\b/;

const lineOf = (src: string, index: number) => src.slice(0, index).split('\n').length;

const historyShaders = fs
  .readdirSync(shaderDir)
  .filter((name) => name.endsWith('.wgsl') && !name.startsWith('_'))
  .filter((name) => declaresHistory.test(fs.readFileSync(path.join(shaderDir, name), 'utf8')))
  .sort();

describe('history ring depth contract', () => {
  it('finds the binding-13 history-ring shaders', () => {
    expect(historyShaders.length).toBeGreaterThanOrEqual(11);
  });

  test.each(historyShaders)('%s wraps the ring at textureNumLayers', (name) => {
    const src = fs.readFileSync(path.join(shaderDir, name), 'utf8');
    const problems: string[] = [];

    // 1. No HISTORY_DEPTH token anywhere, comments included.
    for (const m of src.matchAll(/\bHISTORY_DEPTH\b/g)) {
      problems.push(`${name}:${lineOf(src, m.index ?? 0)} mentions HISTORY_DEPTH`);
    }

    // 2. No literal 8 as the ring modulus. Only statements that also use
    //    historyHead count, so FFT-bin `% 8u` indexing is left alone.
    let offset = 0;
    for (const stmt of src.split(';')) {
      if (/\bhistoryHead\b/.test(stmt) && literalModulus.test(stmt)) {
        const at = offset + stmt.search(literalModulus);
        problems.push(`${name}:${lineOf(src, at)} wraps historyHead with a literal % 8`);
      }
      offset += stmt.length + 1;
    }

    // 3. Sampling the ring requires reading its real depth.
    const sample = src.search(samplesHistory);
    if (sample >= 0 && !readsNumLayers.test(src)) {
      problems.push(`${name}:${lineOf(src, sample)} samples historyTexture but never calls textureNumLayers(historyTexture)`);
    }

    expect(problems).toEqual([]);
  });
});
