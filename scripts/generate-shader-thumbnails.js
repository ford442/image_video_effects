#!/usr/bin/env node
/**
 * generate-shader-thumbnails.js
 *
 * Batch-render shader thumbnails via Playwright + WebGPU.
 *
 * Default engine (`app`): production build + __pixelocity__ test harness (multipass-safe).
 * Legacy engine (`minimal`): inline WebGPU compute (fast, generative-only).
 *
 * Usage:
 *   npm run thumbs:generate -- --missing
 *   npm run thumbs:generate -- --category=generative --limit=50
 *   npm run thumbs:generate -- --shard=0/4 --force
 *   npm run thumbs:generate:minimal -- --category=generative --limit=10
 *
 * Requires a real WebGPU host — see docs/THUMBNAIL_PIPELINE.md
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SHADERS_DIR = path.join(ROOT, 'public', 'shaders');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const OUT_DIR = path.join(ROOT, 'public', 'thumbnails');
const MANIFEST_PATH = path.join(OUT_DIR, 'manifest.json');
const BUILD_DIR = path.join(ROOT, 'build');
const DEFAULT_REPORT = path.join(ROOT, 'reports', 'thumbnail-failures.json');
const MULTIPASS_REGISTRY_PATH = path.join(ROOT, 'src', 'renderer', 'multipassRegistry.ts');
const { loadThumbnailSkipIds } = require('./lib/thumbnailSkipAllowlist');

const DEFAULT_SIZE = 256;
const DEFAULT_FRAMES = 60;
const SIM_WARMUP_FRAMES = 120;
const DEFAULT_TIME = 1.5;
const DEFAULT_QUALITY = 'battery';

// ── CLI args ────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = {
    category: 'all-catalog',
    limit: null,
    ids: null,
    headless: true,
    skipExisting: false,
    missing: false,
    force: false,
    shardIndex: null,
    shardCount: null,
    engine: 'app',
    frames: DEFAULT_FRAMES,
    size: DEFAULT_SIZE,
    quality: DEFAULT_QUALITY,
    report: DEFAULT_REPORT,
    time: DEFAULT_TIME,
    priority: null,
  };
  for (const arg of argv) {
    const eq = arg.indexOf('=');
    const key = eq >= 0 ? arg.slice(2, eq) : arg.replace(/^--/, '');
    const val = eq >= 0 ? arg.slice(eq + 1) : 'true';
    if (key === 'category') out.category = val;
    else if (key === 'limit') out.limit = parseInt(val, 10);
    else if (key === 'ids') out.ids = val.split(',').map(s => s.trim()).filter(Boolean);
    else if (key === 'headless') out.headless = val !== 'false';
    else if (key === 'skip-existing') out.skipExisting = val !== 'false';
    else if (key === 'missing') out.missing = val !== 'false';
    else if (key === 'force') out.force = val !== 'false';
    else if (key === 'engine') out.engine = val;
    else if (key === 'frames') out.frames = parseInt(val, 10);
    else if (key === 'size') out.size = parseInt(val, 10);
    else if (key === 'quality') out.quality = val;
    else if (key === 'report') out.report = val;
    else if (key === 'time') out.time = parseFloat(val);
    else if (key === 'priority') out.priority = val;
    else if (key === 'shard') {
      const [idx, count] = val.split('/').map(s => parseInt(s, 10));
      out.shardIndex = idx;
      out.shardCount = count;
    }
  }
  if (out.missing) out.skipExisting = true;
  return out;
}

function loadAllCatalogShaders() {
  const files = fs.readdirSync(LISTS_DIR).filter(f => f.endsWith('.json'));
  const byId = new Map();
  for (const file of files) {
    const list = JSON.parse(fs.readFileSync(path.join(LISTS_DIR, file), 'utf8'));
    for (const entry of list) {
      if (entry && entry.id) byId.set(entry.id, entry);
    }
  }
  return Array.from(byId.values());
}

function loadShaderList(category) {
  if (category === 'all-catalog') return loadAllCatalogShaders();
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

function loadAttractPriorityIds() {
  const attractPath = path.join(ROOT, 'src', 'app', 'constants', 'attractShowcasePool.ts');
  if (!fs.existsSync(attractPath)) return [];
  const source = fs.readFileSync(attractPath, 'utf8');
  const ids = [];
  for (const block of source.matchAll(/export const ATTRACT_(?:SHOWCASE|PHYSICS_LAB)_IDS[^[]*\[([\s\S]*?)\];/g)) {
    for (const match of block[1].matchAll(/'([^']+)'/g)) ids.push(match[1]);
  }
  return [...new Set(ids)];
}

function hasFourLiveParams(shader) {
  const params = shader.params || [];
  if (params.length < 4) return false;
  const mappings = ['zoom_params.x', 'zoom_params.y', 'zoom_params.z', 'zoom_params.w'];
  return mappings.every((m, i) => params[i]?.mapping === m);
}

function applyAttractPriority(shaders) {
  const byId = new Map(shaders.map(s => [s.id, s]));
  const used = new Set();
  const ordered = [];
  for (const id of loadAttractPriorityIds()) {
    const shader = byId.get(id);
    if (shader) {
      ordered.push(shader);
      used.add(id);
    }
  }
  const rest = shaders.filter(s => !used.has(s.id));
  const genFour = rest.filter(s => s.category === 'generative' && hasFourLiveParams(s));
  const genFourIds = new Set(genFour.map(s => s.id));
  const tail = rest.filter(s => !genFourIds.has(s.id));
  return [...ordered, ...genFour, ...tail];
}

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

function hasExistingThumbnail(id, manifest) {
  return !!(manifest[id] && fs.existsSync(path.join(OUT_DIR, `${id}.png`)));
}

function classifyFailure(error) {
  const msg = String(error || '');
  if (msg.startsWith('compile:')) return 'compile';
  if (msg.startsWith('pipeline:')) return 'pipeline';
  if (msg === 'black_frame' || msg === 'magenta_frame' || msg === 'error_frame') return msg;
  if (msg.includes('no GPU') || msg.includes('navigator.gpu')) return 'gpu_unavailable';
  if (msg.includes('loadShader failed')) return 'load_failed';
  return 'unknown';
}

function emptySummary() {
  return { success: 0, failed: 0, skipped: 0, black_frame: 0, magenta_frame: 0, error_frame: 0, compile: 0 };
}

function bumpErrorSummary(summary, reason) {
  if (reason === 'black_frame') summary.black_frame++;
  else if (reason === 'magenta_frame') summary.magenta_frame++;
  else if (reason === 'error_frame') summary.error_frame++;
}

/** Parse multipass + graph registry ids from generated TS for warmup heuristics. */
function loadWarmupShaderIds() {
  const ids = new Set();
  if (!fs.existsSync(MULTIPASS_REGISTRY_PATH)) return ids;
  const src = fs.readFileSync(MULTIPASS_REGISTRY_PATH, 'utf8');
  const multipassBlock = src.match(/export const MULTIPASS_REGISTRY[^=]*=\s*\{([\s\S]*?)\n\};/);
  if (multipassBlock) {
    const passRe = /"([^"]+)":\s*\{[^}]*"pass":\s*(\d+)/g;
    let m;
    while ((m = passRe.exec(multipassBlock[1])) !== null) {
      ids.add(m[1]);
    }
  }
  const graphBlock = src.match(/export const GRAPH_REGISTRY[^=]*=\s*\{([\s\S]*?)\n\};/);
  if (graphBlock) {
    const graphRe = /"([^"]+)":\s*\{/g;
    let m;
    while ((m = graphRe.exec(graphBlock[1])) !== null) {
      ids.add(m[1]);
    }
  }
  return ids;
}

const WARMUP_SHADER_IDS = loadWarmupShaderIds();

function warmupFramesForShader(shader, defaultFrames) {
  const category = shader.category || '';
  if (category === 'simulation' || WARMUP_SHADER_IDS.has(shader.id)) {
    return Math.max(defaultFrames, SIM_WARMUP_FRAMES);
  }
  return defaultFrames;
}

function recordErrorFrameFailure(failures, summary, shaderId, stats, harness) {
  const reason = harness.classifyErrorFrame(stats) || 'error_frame';
  bumpErrorSummary(summary, reason);
  summary.failed++;
  const detail = harness.formatFrameStats(stats);
  failures.push({ id: shaderId, reason, detail, stats });
  return { reason, detail };
}

function writeFailureReport(reportPath, payload) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify(payload, null, 2));
}

function updateManifestEntry(manifest, id, zoomParams) {
  manifest[id] = {
    thumbnail_url: `thumbnails/${id}.png`,
    generated_at: new Date().toISOString(),
    params_snapshot: zoomParams,
  };
}

// ── Minimal engine: inline WebGPU ─────────────────────────────────────────────

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

      const UNIFORM_FLOATS = 12 + 50 * 4;
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

      device.queue.writeBuffer(extraBuf, 0, new Float32Array(256));

      const readbackBuf = device.createBuffer({
        size: size * size * 16,
        usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
      });

      ctx = {
        device, pipelineLayout, bindGroup, uniformBuf, writeTex, readbackBuf,
        pipelineCache: new Map(),
      };
      window.__thumbCtx = ctx;
    }

    const { device, pipelineLayout, bindGroup, uniformBuf, writeTex, readbackBuf, pipelineCache } = ctx;

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

    const UNIFORM_FLOATS = 12 + 50 * 4;
    const u = new Float32Array(UNIFORM_FLOATS);
    u[0] = time; u[1] = 0; u[2] = size; u[3] = size;
    u[4] = time; u[5] = 0.5; u[6] = 0.5; u[7] = 0;
    u[8] = zoomParams[0]; u[9] = zoomParams[1]; u[10] = zoomParams[2]; u[11] = zoomParams[3];
    device.queue.writeBuffer(uniformBuf, 0, u);

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

async function runMinimalEngine(args, shaders, manifest) {
  const summary = emptySummary();
  const failures = [];

  const browser = await chromium.launch({
    headless: args.headless,
    args: ['--enable-unsafe-webgpu', '--no-sandbox', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  await page.setContent('<html><body></body></html>');
  let hasGpu = await page.evaluate(() => !!navigator.gpu);
  if (!hasGpu) {
    await page.goto('chrome://gpu');
    await page.waitForTimeout(500);
    hasGpu = await page.evaluate(() => !!navigator.gpu);
  }
  if (!hasGpu) {
    await browser.close();
    throw new Error('gpu_unavailable: WebGPU is unavailable in this browser/environment');
  }

  for (let i = 0; i < shaders.length; i++) {
    const shader = shaders[i];
    const progress = `[${i + 1}/${shaders.length}]`;
    const wgslPath = path.join(SHADERS_DIR, `${shader.id}.wgsl`);
    if (!fs.existsSync(wgslPath)) {
      console.log(`${progress} ${shader.id}: SKIP (no .wgsl file)`);
      summary.skipped++;
      failures.push({ id: shader.id, reason: 'no_wgsl', detail: 'missing .wgsl file' });
      continue;
    }
    const wgsl = fs.readFileSync(wgslPath, 'utf8');
    const zoomParams = extractDefaultParams(shader);
    const result = await page.evaluate(renderThumbnailInPage, {
      wgsl, zoomParams, size: args.size, time: args.time, id: shader.id,
    });

    if (result.ok) {
      const outPath = path.join(OUT_DIR, `${shader.id}.png`);
      fs.writeFileSync(outPath, Buffer.from(result.png, 'base64'));
      updateManifestEntry(manifest, shader.id, zoomParams);
      console.log(`${progress} ${shader.id}: OK`);
      summary.success++;
    } else {
      const reason = classifyFailure(result.error);
      if (reason === 'compile') summary.compile++;
      console.log(`${progress} ${shader.id}: FAIL (${result.error})`);
      failures.push({ id: shader.id, reason, detail: result.error });
      summary.failed++;
    }
  }

  await browser.close();
  return { summary, failures };
}

// ── App engine: production build + test harness ─────────────────────────────

async function runAppEngine(args, shaders, manifest) {
  const harness = await import('./lib/thumbnailHarness.mjs');
  const summary = emptySummary();
  const failures = [];

  if (!fs.existsSync(path.join(BUILD_DIR, 'index.html'))) {
    throw new Error(
      `Missing ${path.join(BUILD_DIR, 'index.html')}. Run "SKIP_WASM_BUILD=1 npm run build" first.`,
    );
  }

  await harness.startStaticServer(BUILD_DIR);

  const browser = await chromium.launch({
    headless: args.headless,
    args: ['--enable-unsafe-webgpu', '--no-sandbox', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  const { criticalErrors } = harness.attachConsoleCollector(page);

  const appUrl = harness.buildAppUrl({
    renderer: 'webgpu',
    renderQuality: args.quality,
  });
  await page.goto(appUrl, { waitUntil: 'networkidle' });
  await harness.waitForTestApi(page);

  const backend = await harness.getActiveBackend(page);
  if (backend !== 'webgpu') {
    await browser.close();
    await harness.stopStaticServer();
    throw new Error(`gpu_unavailable: expected webgpu backend, got "${backend}"`);
  }

  const imageUrl = harness.imageFixtureUrl();

  for (let i = 0; i < shaders.length; i++) {
    const shader = shaders[i];
    const progress = `[${i + 1}/${shaders.length}]`;
    const wgslPath = path.join(SHADERS_DIR, `${shader.id}.wgsl`);
    if (!fs.existsSync(wgslPath)) {
      console.log(`${progress} ${shader.id}: SKIP (no .wgsl file)`);
      summary.skipped++;
      failures.push({ id: shader.id, reason: 'no_wgsl', detail: 'missing .wgsl file' });
      continue;
    }

    const zoomParams = extractDefaultParams(shader);
    const inputSource = harness.inputSourceForCategory(shader.category || '');
    const shaderUrl = harness.localShaderUrl(shader.id);

    try {
      await harness.loadShaderOnSlot(
        page,
        { id: shader.id, url: shaderUrl, slot: 0 },
        inputSource,
        inputSource === 'image' ? imageUrl : null,
      );
      await harness.applyTestState(page, {
        time: args.time,
        mouseX: 0.5,
        mouseY: 0.5,
        mouseDown: 0,
      });
      const frameCount = warmupFramesForShader(shader, args.frames);
      await harness.waitFrames(page, frameCount);

      const stats = await harness.captureCanvasStats(page);
      if (harness.isErrorFrame(stats)) {
        const { reason, detail } = recordErrorFrameFailure(failures, summary, shader.id, stats, harness);
        console.log(`${progress} ${shader.id}: FAIL (${reason} ${detail})`);
        continue;
      }

      const pngB64 = await harness.captureThumbnailPng(page, args.size);
      // app engine: gpu-chores downsample_2d when WebGPU is live; canvas fallback otherwise.
      if (!pngB64) {
        summary.failed++;
        console.log(`${progress} ${shader.id}: FAIL (capture failed)`);
        failures.push({ id: shader.id, reason: 'capture_failed', detail: 'captureThumbnailPng returned null' });
        continue;
      }

      const outPath = path.join(OUT_DIR, `${shader.id}.png`);
      fs.writeFileSync(outPath, Buffer.from(pngB64, 'base64'));
      updateManifestEntry(manifest, shader.id, zoomParams);
      console.log(`${progress} ${shader.id}: OK`);
      summary.success++;
    } catch (err) {
      const detail = err.message || String(err);
      const reason = classifyFailure(detail);
      if (reason === 'compile') summary.compile++;
      if (criticalErrors.length > 0 && reason === 'unknown') {
        failures.push({ id: shader.id, reason: 'pipeline', detail: criticalErrors.join(' | ') });
      } else {
        failures.push({ id: shader.id, reason, detail });
      }
      summary.failed++;
      console.log(`${progress} ${shader.id}: FAIL (${detail})`);
      criticalErrors.length = 0;
    }
  }

  await browser.close();
  await harness.stopStaticServer();
  return { summary, failures };
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.engine === 'minimal' && args.category !== 'generative') {
    throw new Error(
      `The minimal engine supports only the generative category; got "${args.category}". ` +
      'Use --engine=app for the full catalog.',
    );
  }
  let shaders = loadShaderList(args.category);
  if (args.priority === 'attract') {
    shaders = applyAttractPriority(shaders);
  }
  const skipIds = loadThumbnailSkipIds();
  shaders = shaders.filter(s => !skipIds.has(s.id));
  if (args.ids) shaders = shaders.filter(s => args.ids.includes(s.id));
  if (args.shardIndex !== null && args.shardCount !== null) {
    shaders = shaders.filter((_, i) => i % args.shardCount === args.shardIndex);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const manifest = fs.existsSync(MANIFEST_PATH)
    ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
    : {};

  if (args.skipExisting && !args.force) {
    shaders = shaders.filter(s => !hasExistingThumbnail(s.id, manifest));
  }

  if (args.limit) shaders = shaders.slice(0, args.limit);

  if (shaders.length === 0) {
    console.log('No shaders to process.');
    return;
  }

  if (skipIds.size > 0) {
    console.log(`[thumbnails] Skipping ${skipIds.size} allowlisted shader(s)`);
  }

  console.log(
    `[thumbnails] Generating ${shaders.length} thumbnail(s) ` +
    `(engine=${args.engine}, category=${args.category}, size=${args.size}, frames=${args.frames}, t=${args.time})`,
  );

  let summary;
  let failures;
  try {
    if (args.engine === 'minimal') {
      ({ summary, failures } = await runMinimalEngine(args, shaders, manifest));
    } else if (args.engine === 'app') {
      ({ summary, failures } = await runAppEngine(args, shaders, manifest));
    } else {
      throw new Error(`Unknown engine "${args.engine}" — use app or minimal`);
    }
  } catch (err) {
    const reason = classifyFailure(err.message);
    const payload = {
      generated_at: new Date().toISOString(),
      engine: args.engine,
      summary: emptySummary(),
      failures: [{ id: '*', reason, detail: err.message }],
    };
    writeFailureReport(args.report, payload);
    throw err;
  }

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));

  const payload = {
    generated_at: new Date().toISOString(),
    engine: args.engine,
    summary,
    failures,
  };
  if (failures.length > 0) {
    writeFailureReport(args.report, payload);
  }

  console.log('');
  console.log(`[thumbnails] Done. success=${summary.success} failed=${summary.failed} skipped=${summary.skipped}`);
  if (summary.black_frame > 0) console.log(`[thumbnails] black_frame=${summary.black_frame}`);
  if (summary.magenta_frame > 0) console.log(`[thumbnails] magenta_frame=${summary.magenta_frame}`);
  if (summary.error_frame > 0) console.log(`[thumbnails] error_frame=${summary.error_frame}`);
  if (summary.compile > 0) console.log(`[thumbnails] compile=${summary.compile}`);
  console.log(`[thumbnails] Manifest: ${MANIFEST_PATH}`);
  if (failures.length > 0) console.log(`[thumbnails] Failures: ${args.report}`);
}

if (require.main === module) {
  main().catch(e => {
    console.error('[thumbnails] Fatal error:', e.message || e);
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  hasExistingThumbnail,
  classifyFailure,
  extractDefaultParams,
  warmupFramesForShader,
  emptySummary,
  WARMUP_SHADER_IDS,
  applyAttractPriority,
  hasFourLiveParams,
  loadAttractPriorityIds,
};
