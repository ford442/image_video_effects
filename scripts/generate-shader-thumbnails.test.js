/**
 * Unit tests for thumbnail generator CLI helpers (node --test).
 */
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  parseArgs,
  hasExistingThumbnail,
  classifyFailure,
  extractDefaultParams,
  warmupFramesForShader,
  WARMUP_SHADER_IDS,
  applyAttractPriority,
  hasFourLiveParams,
  loadAttractPriorityIds,
  readShaderSource,
  chromiumArgs,
  captureHostFor,
  withListCategory,
  loadAllCatalogShaders,
  capturedOn,
} = require('./generate-shader-thumbnails');
const { SWIFTSHADER_WEBGPU_ARGS } = require('./lib/swiftshaderArgs');
const path = require('path');
const frameAnalysis = require('./lib/thumbnailFrameAnalysis');

describe('generate-shader-thumbnails', () => {
  it('parseArgs defaults to app engine and all-catalog', () => {
    const args = parseArgs([]);
    assert.equal(args.engine, 'app');
    assert.equal(args.category, 'all-catalog');
    assert.equal(args.frames, 60);
    assert.equal(args.size, 256);
    assert.equal(args.quality, 'battery');
  });

  it('parseArgs --priority=attract', () => {
    const args = parseArgs(['--priority=attract']);
    assert.equal(args.priority, 'attract');
  });

  it('parseArgs --missing sets skipExisting', () => {
    const args = parseArgs(['--missing']);
    assert.equal(args.missing, true);
    assert.equal(args.skipExisting, true);
  });

  it('parseArgs --force is distinct from missing', () => {
    const args = parseArgs(['--force', '--missing']);
    assert.equal(args.force, true);
    assert.equal(args.skipExisting, true);
  });

  it('parseArgs shard and engine', () => {
    const args = parseArgs(['--shard=1/4', '--engine=minimal', '--limit=10']);
    assert.equal(args.shardIndex, 1);
    assert.equal(args.shardCount, 4);
    assert.equal(args.engine, 'minimal');
    assert.equal(args.limit, 10);
  });

  it('minimal engine is documented and constrained to generative captures', () => {
    const source = require('fs').readFileSync(
      require('path').join(__dirname, 'generate-shader-thumbnails.js'),
      'utf8',
    );
    assert.match(source, /args\.engine === 'minimal'/);
    assert.match(source, /args\.category !== 'generative'/);
  });

  it('parseArgs accepts an explicit retry ID list', () => {
    const args = parseArgs(['--force', '--ids=alpha-hdr-bloom-chain, gen-barnsley-fern']);
    assert.equal(args.force, true);
    assert.deepEqual(args.ids, ['alpha-hdr-bloom-chain', 'gen-barnsley-fern']);
  });

  it('hasExistingThumbnail requires manifest and png', () => {
    const fs = require('fs');
    const path = require('path');
    const pngPath = path.join(__dirname, '..', 'public', 'thumbnails');
    const existing = fs.readdirSync(pngPath).find(f => f.endsWith('.png'));
    if (existing) {
      const id = existing.replace('.png', '');
      assert.equal(hasExistingThumbnail(id, { [id]: {} }), true);
    }
    assert.equal(hasExistingThumbnail('nonexistent-shader-id-xyz', { foo: {} }), false);
  });

  it('classifyFailure maps compile and error frame reasons', () => {
    assert.equal(classifyFailure('compile: line 1 error'), 'compile');
    assert.equal(classifyFailure('black_frame'), 'black_frame');
    assert.equal(classifyFailure('magenta_frame'), 'magenta_frame');
    assert.equal(classifyFailure('error_frame'), 'error_frame');
    assert.equal(classifyFailure('no GPU adapter'), 'gpu_unavailable');
  });

  it('warmupFramesForShader boosts simulation and multipass shaders', () => {
    assert.equal(warmupFramesForShader({ id: 'plasma', category: 'generative' }, 60), 60);
    assert.equal(warmupFramesForShader({ id: 'wave-tank', category: 'simulation' }, 60), 120);
    const multipassId = WARMUP_SHADER_IDS.size > 0 ? [...WARMUP_SHADER_IDS][0] : 'ripple-tank';
    assert.equal(warmupFramesForShader({ id: multipassId, category: 'distortion' }, 60), 120);
  });

  it('isErrorFrame detects black and magenta frames', () => {
    assert.equal(frameAnalysis.isErrorFrame({ meanLuminance: 0, activePixelRatio: 0 }), true);
    assert.equal(
      frameAnalysis.isErrorFrame({ meanLuminance: 0.5, activePixelRatio: 0.5, magentaPixelRatio: 0.9 }),
      true,
    );
    assert.equal(
      frameAnalysis.isErrorFrame({ meanLuminance: 0.5, activePixelRatio: 0.5, magentaPixelRatio: 0.01 }),
      false,
    );
    assert.equal(
      frameAnalysis.isErrorFrame({ meanLuminance: 0.2, activePixelRatio: 0.4, magentaPixelRatio: 0.2 }),
      false,
      'intentional partial magenta palettes are not error frames',
    );
  });

  it('applyAttractPriority puts attract pool ids first', () => {
    const priority = loadAttractPriorityIds();
    assert.ok(priority.length > 0);
    const shaders = [
      { id: 'long-tail-z', category: 'image', params: [] },
      { id: priority[0], category: 'generative', params: [] },
      {
        id: 'gen-four-params-example',
        category: 'generative',
        params: [
          { mapping: 'zoom_params.x' },
          { mapping: 'zoom_params.y' },
          { mapping: 'zoom_params.z' },
          { mapping: 'zoom_params.w' },
        ],
      },
    ];
    const ordered = applyAttractPriority(shaders);
    assert.equal(ordered[0].id, priority[0]);
    assert.equal(ordered[1].id, 'gen-four-params-example');
    assert.equal(ordered[2].id, 'long-tail-z');
    assert.equal(hasFourLiveParams(shaders[2]), true);
  });

  it('extractDefaultParams reads zoom_params mappings', () => {
    const params = extractDefaultParams({
      params: [
        { mapping: 'zoom_params.x', default: 0.3 },
        { mapping: 'zoom_params.y', default: 0.7 },
      ],
    });
    assert.equal(params[0], 0.3);
    assert.equal(params[1], 0.7);
  });

  it('--adapter=swiftshader adds the SwiftShader flags, a 512 page and scale 0.25', () => {
    const args = parseArgs(['--adapter=swiftshader']);
    assert.equal(args.adapter, 'swiftshader');
    assert.equal(args.viewport, 512);
    assert.equal(args.renderScale, 0.25);
    for (const flag of SWIFTSHADER_WEBGPU_ARGS) assert.ok(chromiumArgs('swiftshader').includes(flag), flag);
    assert.ok(!chromiumArgs('default').includes('--use-webgpu-adapter=swiftshader'));
    assert.equal(parseArgs([]).viewport, null);
    assert.throws(() => parseArgs(['--adapter=llvmpipe']), /Unknown --adapter/);
  });

  it('captures are tagged with their host; --recapture-host selects them', () => {
    assert.equal(captureHostFor('swiftshader'), 'swiftshader');
    assert.equal(captureHostFor('default'), 'gpu');
    const manifest = { a: { capture_host: 'swiftshader' }, b: { capture_host: 'gpu' }, c: {} };
    assert.deepEqual(['a', 'b', 'c'].filter(id => capturedOn(id, manifest, 'swiftshader')), ['a']);
    assert.equal(parseArgs(['--recapture-host=swiftshader']).recaptureHost, 'swiftshader');
  });

  it('entries without a category take their list name (input source depends on it)', () => {
    assert.equal(withListCategory({ id: 'x' }, 'distortion').category, 'distortion');
    assert.equal(withListCategory({ id: 'x', category: 'image' }, 'distortion').category, 'image');
    const catalog = loadAllCatalogShaders();
    assert.ok(catalog.length > 1000);
    assert.deepEqual(catalog.filter(s => !s.category).map(s => s.id), []);
  });

  it('flat frames are errors; black wins over flat', () => {
    const flat = { meanLuminance: 0.5, activePixelRatio: 1, magentaPixelRatio: 0, maxChannelStd: 0.002 };
    assert.equal(frameAnalysis.classifyErrorFrame(flat), 'flat_frame');
    assert.equal(frameAnalysis.classifyErrorFrame({ ...flat, meanLuminance: 0, activePixelRatio: 0 }), 'black_frame');
    assert.equal(frameAnalysis.classifyErrorFrame({ ...flat, maxChannelStd: 0.2 }), null);
    assert.equal(classifyFailure('flat_frame'), 'flat_frame');
  });

  it('statsFromPngBuffer measures the committed PNG bytes', async () => {
    const sharp = require('sharp');
    const raw = Buffer.alloc(8 * 8 * 4);
    for (let i = 0; i < 64; i++) raw.set(i % 2 ? [250, 20, 20, 255] : [10, 10, 200, 255], i * 4);
    const png = await sharp(raw, { raw: { width: 8, height: 8, channels: 4 } }).png().toBuffer();
    const stats = await frameAnalysis.statsFromPngBuffer(png);
    assert.equal(stats.width, 8);
    assert.ok(stats.maxChannelStd > 0.3);
    assert.equal(frameAnalysis.classifyErrorFrame(stats), null);
  });

  it('harness: every non-generative category gets the image input; list urls resolve', async () => {
    const harness = await import('./lib/thumbnailHarness.mjs');
    assert.equal(harness.inputSourceForCategory('generative'), 'generative');
    for (const c of ['image', 'distortion', 'visual-effects', 'artistic', 'simulation']) {
      assert.equal(harness.inputSourceForCategory(c), 'image', c);
    }
    assert.equal(harness.localShaderUrl('ripple-tank', 'shaders/ripple-tank-step.wgsl'), './shaders/ripple-tank-step.wgsl');
    assert.equal(harness.localShaderUrl('x', '/shaders/x_y.wgsl'), './shaders/x_y.wgsl');
    assert.equal(harness.localShaderUrl('plasma'), './shaders/plasma.wgsl');
    assert.equal(harness.localShaderUrl('remote', 'https://cdn.example/remote.wgsl'), './shaders/remote.wgsl');
    assert.ok(require('fs').existsSync(path.join(__dirname, '..', 'public', harness.THUMBNAIL_FIXTURE)));
  });

  it('readShaderSource expands #include for the minimal engine', async () => {
    const shaders = path.join(__dirname, '..', 'public', 'shaders');
    const expanded = await readShaderSource(path.join(shaders, 'gray-scott-step.wgsl'));
    assert.match(expanded, /@group\(0\) @binding\(3\) var<uniform> u: Uniforms;/);
    assert.doesNotMatch(expanded, /^#include/m);

    const plainPath = path.join(shaders, '_hash_library.wgsl');
    assert.equal(await readShaderSource(plainPath), require('fs').readFileSync(plainPath, 'utf8'));
  });
});
