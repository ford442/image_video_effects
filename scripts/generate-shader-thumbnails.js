#!/usr/bin/env node
/**
 * generate-shader-thumbnails.js
 *
 * Renders a single frame (t=1.5s) of generative / visual-effects WGSL shaders
 * using the same 13-binding compute contract as WebGPURenderer.ts, and saves
 * the result as a PNG thumbnail under public/thumbnails/.
 *
 * Uses Playwright (already a devDependency) to drive a real Chromium WebGPU
 * device — no new npm packages required.
 *
 * Usage:
 *   node scripts/generate-shader-thumbnails.js --category=generative
 *   node scripts/generate-shader-thumbnails.js --category=visual-effects
 *   node scripts/generate-shader-thumbnails.js --category=all --limit=10
 *   node scripts/generate-shader-thumbnails.js --ids=plasma-storm,4d-projection-dream-weavers
 *
 * On headless Linux without a GPU, run under Xvfb:
 *   xvfb-run -a node scripts/generate-shader-thumbnails.js --category=generative
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SHADERS_DIR = path.join(ROOT, 'public', 'shaders');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const OUT_DIR = path.join(ROOT, 'public', 'thumbnails');
const MANIFEST_PATH = path.join(OUT_DIR, 'manifest.json');

const SIZE = 256;       // thumbnail render resolution (square)
const RENDER_TIME = 1.5; // matches Phase 1 spec: render 1 frame at t=1.5

// ── CLI args ────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { category: 'generative', limit: null, ids: null, headless: false };
  for (const arg of argv) {
    const [key, val] = arg.replace(/^--/, '').split('=');
    if (key === 'category') out.category = val;
    else if (key === 'limit') out.limit = parseInt(val, 10);
    else if (key === 'ids') out.ids = val.split(',').map(s => s.trim()).filter(Boolean);
    else if (key === 'headless') out.headless = val !== 'false';
  }
  return out;
}

// ── Shader list loading ────────────────────────────────────────────────────

function loadShaderList(category) {
  if (category === 'all') {
    const generative = JSON.parse(fs.readFileSync(path.join(LISTS_DIR, 'generative.json'), 'utf8'));
    const visualEffects = JSON.parse(fs.readFileSync(path.join(LISTS_DIR, 'visual-effects.json'), 'utf8'));
    return [...generative, ...visualEffects];
  }
  const file = path.join(LISTS_DIR, `${category}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`No shader list found for category "${category}" (expected ${file})`);
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** Extract default zoom_params [p1,p2,p3,p4] from a shader's params definitions. */
function extractDefaultParams(shader) {
  const zoomParams = [0.5, 0.5, 0.5, 0.5];
  const slotMap = { x: 0, y: 1, z: 2, w: 3 };
  for (const p of shader.params || []) {
    const m = /^zoom_params\.([xyzw])$/.exec(p.mapping || '');
    if (m) {
      const idx = slotMap[m[1]];
      if (typeof p.default === 'number') zoomParams[idx] = p.default;
    }
  }
  return zoomParams;
}

// ── Browser-side rendering ─────────────────────────────────────────────────

/**
 * Runs entirely inside the page context. Sets up (once, cached on `window`)
 * a WebGPU device + the 13-binding compute bind group layout matching
 * WebGPURenderer.ts, then for each call: compiles the given WGSL, dispatches
 * one compute pass at t=RENDER_TIME, reads back writeTex, gamma-corrects it
 * (matching GENERATIVE_BLIT_WGSL), and returns a base64 PNG via Canvas2D.
 */
async function renderThumbnailInPage({ wgsl, zoomParams, size, time, id }) {
  try {
    if (!navigator.gpu) return { ok: false, error: 'navigator.gpu unavailable' };

    let ctx = window.__thumbCtx;
    if (!ctx) {
      const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
      if (!adapter) return { ok: false, error: 'no GPU adapter' };

      const hasF32Filt = adapter.features.has('float32-filterable');
      const device = await adapter.requestDevice({
        requiredFeatures: hasF32Filt ? ['float32-filterable'] : [],
      });

      const fST = hasF32Filt ? 'float' : 'unfilterable-float';
      const V = GPUShaderStage.COMPUTE;

      const bindGroupLayout = device.createBindGroupLayout({
        label: 'thumbBGL',
        entries: [
          { binding: 0, visibility: V, sampler: { type: 'filtering' } },
          { binding: 1, visibility: V, texture: { sampleType: fST } },
          { binding: 2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
          { binding: 3, visibility: V, buffer: { type: 'uniform' } },
          { binding: 4, visibility: V, texture: { sampleType: 'unfilterable-float' } },
          { binding: 5, visibility: V, sampler: { type: 'non-filtering' } },
          { binding: 6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
          { binding: 7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
          { binding: 8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
          { binding: 9, visibility: V, texture: { sampleType: fST } },
          { binding: 10, visibility: V, buffer: { type: 'storage' } },
          { binding: 11, visibility: V, sampler: { type: 'comparison' } },
          { binding: 12, visibility: V, buffer: { type: 'read-only-storage' } },
          { binding: 13, visibility: V, texture: { sampleType: fST, viewDimension: '2d-array' } },
        ],
      });
      const pipelineLayout = device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] });

      const HISTORY_DEPTH = 8;
      const USAGE_STANDARD = GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.STORAGE_BINDING |
        GPUTextureUsage.COPY_DST | GPUTextureUsage.COPY_SRC;
      const USAGE_SOURCE = GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST |
        GPUTextureUsage.COPY_SRC | GPUTextureUsage.RENDER_ATTACHMENT;

      const readTex = device.createTexture({ size: [size, size], format: 'rgba32float', usage: USAGE_STANDARD });
      const writeTex = device.createTexture({ size: [size, size], format: 'rgba32float', usage: USAGE_STANDARD });
      const dataTexA = device.createTexture({ size: [size, size], format: 'rgba32float', usage: USAGE_STANDARD });
      const dataTexB = device.createTexture({ size: [size, size], format: 'rgba32float', usage: USAGE_STANDARD });
      const dataTexC = device.createTexture({ size: [size, size], format: 'rgba32float', usage: USAGE_STANDARD });
      const depthRead = device.createTexture({ size: [size, size], format: 'r32float', usage: USAGE_SOURCE });
      const depthWrite = device.createTexture({ size: [size, size], format: 'r32float', usage: USAGE_STANDARD });
      const historyTex = device.createTexture({
        size: { width: size, height: size, depthOrArrayLayers: HISTORY_DEPTH },
        format: 'rgba32float',
        usage: USAGE_STANDARD,
      });

      const filterSampler = device.createSampler({
        magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear',
        addressModeU: 'repeat', addressModeV: 'repeat',
      });
      const nearestSampler = device.createSampler({
        magFilter: 'nearest', minFilter: 'nearest',
        addressModeU: 'clamp-to-edge', addressModeV: 'clamp-to-edge',
      });
      const compSampler = device.createSampler({ compare: 'less' });

      const UNIFORM_FLOATS = 12 + 50 * 4; // matches UniformBuffer.ts (212 floats)
      const uniformBuf = device.createBuffer({ size: UNIFORM_FLOATS * 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      const extraBuf = device.createBuffer({ size: 256 * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
      const plasmaBuf = device.createBuffer({ size: Math.max(50 * 48, 16), usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });

      const bindGroup = device.createBindGroup({
        layout: bindGroupLayout,
        entries: [
          { binding: 0, resource: filterSampler },
          { binding: 1, resource: readTex.createView() },
          { binding: 2, resource: writeTex.createView() },
          { binding: 3, resource: { buffer: uniformBuf } },
          { binding: 4, resource: depthRead.createView() },
          { binding: 5, resource: nearestSampler },
          { binding: 6, resource: depthWrite.createView() },
          { binding: 7, resource: dataTexA.createView() },
          { binding: 8, resource: dataTexB.createView() },
          { binding: 9, resource: dataTexC.createView() },
          { binding: 10, resource: { buffer: extraBuf } },
          { binding: 11, resource: compSampler },
          { binding: 12, resource: { buffer: plasmaBuf } },
          { binding: 13, resource: historyTex.createView({ dimension: '2d-array', baseArrayLayer: 0, arrayLayerCount: HISTORY_DEPTH }) },
        ],
      });

      // Zero out extraBuf (no audio reactivity for thumbnails)
      device.queue.writeBuffer(extraBuf, 0, new Float32Array(256));

      const readbackBuf = device.createBuffer({
        size: size * size * 16, // rgba32float
        usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
      });

      ctx = {
        device, pipelineLayout, bindGroup, uniformBuf, writeTex, readbackBuf,
        pipelineCache: new Map(),
      };
      window.__thumbCtx = ctx;
    }

    const { device, pipelineLayout, bindGroup, uniformBuf, writeTex, readbackBuf, pipelineCache } = ctx;

    // ── Compile (with cache) ─────────────────────────────────────────────
    let pipeline = pipelineCache.get(id);
    let wgSize = { x: 8, y: 8 };
    if (!pipeline) {
      const wgMatch = wgsl.match(/@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)/);
      if (wgMatch) wgSize = { x: parseInt(wgMatch[1], 10), y: parseInt(wgMatch[2], 10) };

      const module = device.createShaderModule({ label: id, code: wgsl });
      const info = await module.getCompilationInfo();
      const errors = info.messages.filter(m => m.type === 'error');
      if (errors.length > 0) {
        return { ok: false, error: 'compile: ' + errors.map(m => `${m.lineNum}:${m.linePos} ${m.message}`).join(' | ') };
      }
      try {
        pipeline = device.createComputePipeline({ label: id, layout: pipelineLayout, compute: { module, entryPoint: 'main' } });
      } catch (e) {
        return { ok: false, error: 'pipeline: ' + e.message };
      }
      pipelineCache.set(id, pipeline);
      pipelineCache.set(id + ':wg', wgSize);
    } else {
      wgSize = pipelineCache.get(id + ':wg');
    }

    // ── Uniforms ──────────────────────────────────────────────────────────
    const UNIFORM_FLOATS = 12 + 50 * 4;
    const u = new Float32Array(UNIFORM_FLOATS);
    u[0] = time; u[1] = 0; u[2] = size; u[3] = size;       // config: time, rippleCount, resW, resH
    u[4] = time; u[5] = 0.5; u[6] = 0.5; u[7] = 0;          // zoom_config: time, mouseX, mouseY, mouseDown
    u[8] = zoomParams[0]; u[9] = zoomParams[1]; u[10] = zoomParams[2]; u[11] = zoomParams[3];
    device.queue.writeBuffer(uniformBuf, 0, u);

    // ── Dispatch ──────────────────────────────────────────────────────────
    const encoder = device.createCommandEncoder({ label: 'thumb' });
    const pass = encoder.beginComputePass({ label: `thumb-${id}` });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(Math.ceil(size / wgSize.x), Math.ceil(size / wgSize.y), 1);
    pass.end();
    encoder.copyTextureToBuffer(
      { texture: writeTex },
      { buffer: readbackBuf, bytesPerRow: size * 16, rowsPerImage: size },
      [size, size, 1],
    );
    device.queue.submit([encoder.finish()]);

    // ── Readback + gamma-correct (matches GENERATIVE_BLIT_WGSL) ─────────────
    await readbackBuf.mapAsync(GPUMapMode.READ);
    const floats = new Float32Array(readbackBuf.getMappedRange().slice(0));
    readbackBuf.unmap();

    const rgba8 = new Uint8ClampedArray(size * size * 4);
    for (let i = 0; i < size * size; i++) {
      const r = floats[i * 4], g = floats[i * 4 + 1], b = floats[i * 4 + 2], a = floats[i * 4 + 3];
      rgba8[i * 4]     = Math.pow(Math.min(Math.max(r, 0), 1), 1 / 2.2) * 255;
      rgba8[i * 4 + 1] = Math.pow(Math.min(Math.max(g, 0), 1), 1 / 2.2) * 255;
      rgba8[i * 4 + 2] = Math.pow(Math.min(Math.max(b, 0), 1), 1 / 2.2) * 255;
      rgba8[i * 4 + 3] = Math.min(Math.max(a, 0), 1) * 255;
    }

    const canvas = document.createElement('canvas');
    canvas.width = size; canvas.height = size;
    const ctx2d = canvas.getContext('2d');
    ctx2d.putImageData(new ImageData(rgba8, size, size), 0, 0);
    const dataUrl = canvas.toDataURL('image/png');
    return { ok: true, png: dataUrl.replace(/^data:image\/png;base64,/, '') };
  } catch (e) {
    return { ok: false, error: e.message || String(e) };
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));
  let shaders = loadShaderList(args.category);
  if (args.ids) shaders = shaders.filter(s => args.ids.includes(s.id));
  if (args.limit) shaders = shaders.slice(0, args.limit);

  if (shaders.length === 0) {
    console.log('No shaders to process.');
    return;
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const manifest = fs.existsSync(MANIFEST_PATH)
    ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
    : {};

  console.log(`[thumbnails] Generating ${shaders.length} thumbnail(s) (category=${args.category}, size=${SIZE}x${SIZE}, t=${RENDER_TIME})`);

  const browser = await chromium.launch({
    headless: args.headless,
    args: ['--enable-unsafe-webgpu', '--no-sandbox', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();

  // navigator.gpu is unavailable on plain pages in some headless/sandboxed
  // setups; chrome://gpu is a normal DOM page that has it enabled.
  await page.setContent('<html><body></body></html>');
  let hasGpu = await page.evaluate(() => !!navigator.gpu);
  if (!hasGpu) {
    await page.goto('chrome://gpu');
    await page.waitForTimeout(500);
    hasGpu = await page.evaluate(() => !!navigator.gpu);
  }
  if (!hasGpu) {
    console.error('[thumbnails] WebGPU is unavailable in this browser/environment.');
    console.error('  On headless Linux, try: xvfb-run -a node scripts/generate-shader-thumbnails.js ...');
    await browser.close();
    process.exit(1);
  }

  let success = 0, failed = 0, skipped = 0;
  for (let i = 0; i < shaders.length; i++) {
    const shader = shaders[i];
    const progress = `[${i + 1}/${shaders.length}]`;
    const wgslPath = path.join(SHADERS_DIR, `${shader.id}.wgsl`);
    if (!fs.existsSync(wgslPath)) {
      console.log(`${progress} ${shader.id}: SKIP (no .wgsl file)`);
      skipped++;
      continue;
    }
    const wgsl = fs.readFileSync(wgslPath, 'utf8');
    const zoomParams = extractDefaultParams(shader);

    const result = await page.evaluate(renderThumbnailInPage, { wgsl, zoomParams, size: SIZE, time: RENDER_TIME, id: shader.id });

    if (result.ok) {
      const outPath = path.join(OUT_DIR, `${shader.id}.png`);
      fs.writeFileSync(outPath, Buffer.from(result.png, 'base64'));
      manifest[shader.id] = {
        thumbnail_url: `thumbnails/${shader.id}.png`,
        generated_at: new Date().toISOString(),
        params_snapshot: zoomParams,
      };
      console.log(`${progress} ${shader.id}: OK`);
      success++;
    } else {
      console.log(`${progress} ${shader.id}: FAIL (${result.error})`);
      failed++;
    }
  }

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
  await browser.close();

  console.log('');
  console.log(`[thumbnails] Done. success=${success} failed=${failed} skipped=${skipped}`);
  console.log(`[thumbnails] Manifest: ${MANIFEST_PATH}`);
}

main().catch(e => {
  console.error('[thumbnails] Fatal error:', e);
  process.exit(1);
});
