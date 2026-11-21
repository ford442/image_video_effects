/**
 * Golden frames through the offline render path (#1401).
 *
 * The stepped clock makes `renderFrameAt(t, input)` byte-stable per adapter, so a shader's
 * frames 0 / 30 / 120 (at 30 fps, 256², on a fixed input) can be committed and compared on
 * every run. This replaces "did it change?" eyeballing for shader upgrade PRs.
 *
 *   - 6 Physics Lab flagships (Tier C graphs + optical flow) and 10 catalog shaders
 *   - exact SHA-256 match → pass; otherwise DSSIM (structure) and mean ΔE (colour) against
 *     the committed PNG, per-shader thresholds in tests/golden-frames/manifest.json
 *   - two renders of the same shader in one page give identical hashes (determinism)
 *   - a deliberately edited shader (one colour constant) fails the comparison
 *   - the VJ Studio → Render job exports MP4 / WebM whose frame count ffprobe confirms
 *
 * Needs a production build: `npm run build && npm run test:engine2 -- golden-frames`.
 * Regenerate after an intended change: `UPDATE_GOLDENS=1 npm run test:engine2 -- golden-frames`.
 * Render thread: the worker (default) or `PX_RENDER_THREAD=main`.
 */
import { execFileSync } from 'child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';
import { expect, test, type Browser, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  EQUIVALENT_DELTA_E,
  GOLDEN_FRAME_DSSIM,
  imageDeltaE,
  imageDssim,
} from '../src/renderer/testing/goldenTolerance';
import { installGpuUncapturedErrorHook, startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3480;
const GOLDEN_DIR = resolve(__dirname, 'golden-frames');
const MANIFEST_PATH = join(GOLDEN_DIR, 'manifest.json');
const FIXTURE = resolve(__dirname, '../public/fixtures/thumbnail-scene.png');
const UPDATE = process.env.UPDATE_GOLDENS === '1';
const THREAD: 'main' | 'worker' = process.env.PX_RENDER_THREAD === 'main' ? 'main' : 'worker';
const SIZE = 256;
const FPS = 30;
const FRAMES = [0, 30, 120];
/** Render quality for every golden: fixes the internal format and the pass budget. */
const QUALITY = 'ultra';

/** The six texture-grid Physics Lab flagships (docs/PHYSICS_LAB.md). */
const PHYSICS_LAB_FLAGSHIPS = [
  'ripple-tank',
  'fabric-of-reality',
  'photonic-caustics-graph',
  'chromatographic-fluid',
  'gray-scott-tank',
  'optical-flow-dream',
];

/** Ten catalog shaders across categories (image, generative, sim, distortion, feedback). */
const CATALOG_GOLDENS = [
  'liquid',
  'aurora-curtain',
  'bio_lenia_continuous',
  'chrono-slit-scan',
  'black-hole',
  'ink-marbling',
  'anisotropic-kuwahara',
  'cinematic-flare',
  'datamosh',
  'ascii-lens',
];

const GOLDEN_SHADERS = [...PHYSICS_LAB_FLAGSHIPS, ...CATALOG_GOLDENS];

interface FrameCapture {
  frame: number;
  sha256: string;
  png: string;
}

interface Manifest {
  version: 1;
  size: number;
  fps: number;
  frames: number[];
  quality: string;
  /** Where the committed goldens were rendered (informational). */
  generatedOn: { adapter: string; renderThread: string; date: string };
  /** Per-shader overrides of GOLDEN_FRAME_DSSIM / EQUIVALENT_DELTA_E. */
  thresholds: Record<string, { dssim?: number; deltaE?: number }>;
  shaders: Record<string, Record<string, { sha256: string }>>;
}

function readManifest(): Manifest | null {
  return existsSync(MANIFEST_PATH) ? (JSON.parse(readFileSync(MANIFEST_PATH, 'utf8')) as Manifest) : null;
}

/** id → URL from the generated shader lists (graph ids resolve to their first pass). */
function shaderUrls(): Map<string, string> {
  const dir = resolve(__dirname, '../public/shader-lists');
  const urls = new Map<string, string>();
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    const list = JSON.parse(readFileSync(join(dir, file), 'utf8')) as Array<{ id: string; url?: string }>;
    for (const s of Array.isArray(list) ? list : []) {
      if (s.id && s.url && !urls.has(s.id)) urls.set(s.id, s.url.startsWith('.') ? s.url : `./${s.url}`);
    }
  }
  return urls;
}

const URLS = shaderUrls();
const urlOf = (id: string) => URLS.get(id) ?? `./shaders/${id}.wgsl`;
const pngPath = (id: string, frame: number) => join(GOLDEN_DIR, `${id}.f${String(frame).padStart(3, '0')}.png`);

async function rgba(png: Buffer): Promise<{ data: Buffer; width: number; height: number }> {
  const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height };
}

async function boot(page: Page): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  // Remote images (the app's random start image) become the fixture: nothing from the network.
  const fixture = readFileSync(FIXTURE);
  await page.context().route(/^https?:\/\/(?!localhost)[^/]+\/.*\.(png|jpe?g|webp)(\?.*)?$/i, (route) =>
    route.fulfill({ status: 200, contentType: 'image/png', body: fixture }),
  );
  await page.goto(`http://localhost:${PORT}/?renderer=${THREAD}&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const w = window as any;
      return w.webgpuProbe != null && w.__pixelocity__?.renderer != null;
    },
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
  // The app's boot puts Liquid in slot 0 once the lists load; wait for it so it cannot land later.
  await page
    .waitForFunction(() => /^liquid(-original)?$/.test((window as any).__pixelocity__.getSlotState(0)?.shaderId ?? ''), null, {
      timeout: 60_000,
      polling: 250,
    })
    .catch(() => undefined);
  await page.evaluate((quality) => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(1);
    api.setInputSource('image');
    api.setRenderQuality(quality);
  }, QUALITY);
}

async function renderFrames(page: Page, shaderId: string, url = urlOf(shaderId)): Promise<FrameCapture[]> {
  return page.evaluate(
    (req) => (window as any).__pixelocity__.renderOfflineFrames(req),
    { shaderId, url, size: SIZE, fps: FPS, frames: FRAMES, source: 'pattern' },
  );
}

interface Comparison {
  frame: number;
  exact: boolean;
  dssim: number;
  worstBlock: number;
  deltaE: number;
  pass: boolean;
}

type Limits = { dssim: number; deltaE: number };

const limitsFor = (manifest: Manifest | null, id: string): Limits =>
  ({ dssim: GOLDEN_FRAME_DSSIM, deltaE: EQUIVALENT_DELTA_E, ...manifest?.thresholds[id] });

/** Frame-by-frame: exact hash, else DSSIM (structure) + mean ΔE (colour) within `limits`. */
async function compareCaptures(
  expected: Array<{ frame: number; sha256: string; png: () => Buffer }>,
  captures: FrameCapture[],
  limits: Limits,
): Promise<Comparison[]> {
  const out: Comparison[] = [];
  for (const c of captures) {
    const e = expected.find((x) => x.frame === c.frame);
    expect(e, `no expected frame ${c.frame}`).toBeTruthy();
    if (e!.sha256 === c.sha256) {
      out.push({ frame: c.frame, exact: true, dssim: 0, worstBlock: 0, deltaE: 0, pass: true });
      continue;
    }
    const golden = await rgba(e!.png());
    const actual = await rgba(Buffer.from(c.png, 'base64'));
    expect(actual.width).toBe(golden.width);
    const s = imageDssim(golden.data, actual.data, golden.width, golden.height);
    const deltaE = imageDeltaE(golden.data, actual.data).mean;
    out.push({
      frame: c.frame,
      exact: false,
      dssim: s.dssim,
      worstBlock: s.worst,
      deltaE,
      pass: s.dssim <= limits.dssim && deltaE <= limits.deltaE,
    });
  }
  return out;
}

function compareToGolden(manifest: Manifest, id: string, captures: FrameCapture[]): Promise<Comparison[]> {
  const frames = manifest.shaders[id];
  expect(frames, `${id}: no committed golden (UPDATE_GOLDENS=1 to create it)`).toBeTruthy();
  const expected = Object.entries(frames!).map(([frame, { sha256 }]) => ({
    frame: Number(frame),
    sha256,
    png: () => readFileSync(pngPath(id, Number(frame))),
  }));
  return compareCaptures(expected, captures, limitsFor(manifest, id));
}

const asExpected = (captures: FrameCapture[]) =>
  captures.map((c) => ({ frame: c.frame, sha256: c.sha256, png: () => Buffer.from(c.png, 'base64') }));

test.describe.serial(`golden frames via renderFrameAt (${THREAD} thread)`, () => {
  let browser: Browser;
  let page: Page;
  const committed = readManifest();
  const manifest: Manifest = committed ?? {
    version: 1,
    size: SIZE,
    fps: FPS,
    frames: FRAMES,
    quality: QUALITY,
    generatedOn: { adapter: '', renderThread: THREAD, date: '' },
    thresholds: {},
    shaders: {},
  };

  test.beforeAll(async ({ browser: b }) => {
    test.setTimeout(240_000);
    await startStaticServer(PORT);
    browser = b;
    page = await browser.newPage();
    await boot(page);
    if (committed && !UPDATE) {
      expect({ size: manifest.size, fps: manifest.fps, frames: manifest.frames }).toEqual({ size: SIZE, fps: FPS, frames: FRAMES });
    }
  });

  test.afterAll(async () => {
    // Only a run that captured something rewrites the manifest (a broken adapter must not empty it).
    if (UPDATE && Object.keys(manifest.shaders).length > 0) {
      const adapter: string = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.adapterInfo
        ?? (window as any).webgpuProbe?.adapterSummary ?? 'unknown').catch(() => 'unknown');
      manifest.generatedOn = { adapter: String(adapter).slice(0, 160), renderThread: THREAD, date: new Date().toISOString().slice(0, 10) };
      mkdirSync(GOLDEN_DIR, { recursive: true });
      writeFileSync(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
    }
    await page?.close();
    await stopStaticServer();
  });

  for (const id of GOLDEN_SHADERS) {
    test(`${id}: frames ${FRAMES.join(' / ')} match the committed goldens`, async () => {
      test.setTimeout(300_000);
      const captures = await renderFrames(page, id);
      expect(captures.map((c) => c.frame)).toEqual(FRAMES);
      // A shader that moves must not render the same picture at 0 and 120 (a frozen clock).
      expect(new Set(captures.map((c) => c.sha256)).size, `${id}: frames 0 / 30 / 120 are identical`).toBeGreaterThan(1);
      // No goldens committed yet: they are produced on a working SwiftShader host with
      // UPDATE_GOLDENS=1 (or the GPU_REQUIRED workflow's golden-frames-swiftshader suite).
      test.skip(!UPDATE && !committed?.shaders[id], `no committed golden for ${id}`);
      if (UPDATE) {
        mkdirSync(GOLDEN_DIR, { recursive: true });
        manifest.shaders[id] = {};
        for (const c of captures) {
          writeFileSync(pngPath(id, c.frame), Buffer.from(c.png, 'base64'));
          manifest.shaders[id]![String(c.frame)] = { sha256: c.sha256 };
        }
        return;
      }
      const results = await compareToGolden(manifest, id, captures);
      test.info().annotations.push({ type: 'golden', description: JSON.stringify({ id, results }) });
      for (const r of results) {
        expect.soft(r.pass, `${id} frame ${r.frame}: dssim ${r.dssim.toFixed(5)} (worst block ${r.worstBlock.toFixed(4)}), ΔE ${r.deltaE.toFixed(3)}`).toBe(true);
      }
    });
  }

  test('two offline renders of the same shader give identical frame hashes', async () => {
    test.setTimeout(600_000);
    for (const id of ['gray-scott-tank', 'liquid', 'datamosh']) {
      const first = await renderFrames(page, id);
      const second = await renderFrames(page, id);
      expect(second.map((c) => c.sha256), `${id}: second render differs`).toEqual(first.map((c) => c.sha256));
    }
  });

  test('a deliberately edited shader fails the comparison (and its unedited copy passes)', async () => {
    test.skip(UPDATE, 'goldens are being regenerated');
    test.setTimeout(300_000);
    const source = readFileSync(resolve(__dirname, '../public/shaders/black-hole.wgsl'), 'utf8');
    const target = 'vec4<f32>(display, a)';
    expect(source.includes(target), 'black-hole.wgsl changed: update the tamper target').toBe(true);
    // An 8 % cut of one colour channel: the kind of tweak a shader upgrade PR makes.
    const tampered = source.replace(target, 'vec4<f32>(display * vec3<f32>(1.0, 0.92, 1.0), a)');
    await page.context().route(/\/shaders\/golden-(control|tamper)\.wgsl$/, (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/plain',
        body: route.request().url().endsWith('golden-tamper.wgsl') ? tampered : source,
      }),
    );
    const control = await renderFrames(page, 'golden-control', './shaders/golden-control.wgsl');
    // The unedited copy is the catalog shader's golden, byte for byte where one is committed.
    if (committed?.shaders['black-hole']) {
      const vsGolden = await compareToGolden(manifest, 'black-hole', control);
      expect(vsGolden.every((r) => r.pass), `unedited copy vs golden: ${JSON.stringify(vsGolden)}`).toBe(true);
    }
    const edited = await compareCaptures(
      asExpected(control),
      await renderFrames(page, 'golden-tamper', './shaders/golden-tamper.wgsl'),
      limitsFor(committed, 'black-hole'),
    );
    test.info().annotations.push({ type: 'tamper', description: JSON.stringify(edited) });
    expect(edited.some((r) => !r.pass), `edited shader still matched: ${JSON.stringify(edited)}`).toBe(true);
  });

  test('VJ Studio → Render exports an MP4 and a WebM with exactly duration × fps frames', async () => {
    test.skip(UPDATE, 'goldens are being regenerated');
    test.setTimeout(600_000);
    const hasFfprobe = (() => {
      try {
        execFileSync('ffprobe', ['-version'], { stdio: 'ignore' });
        return true;
      } catch {
        return false;
      }
    })();
    const events: unknown[] = [
      { t: 0, slot: 0, kind: 'shader', value: 'aurora-curtain' },
      ...Array.from({ length: 41 }, (_, i) => ({ t: i * 50, slot: 0, kind: 'param', key: 'zoomParam1', value: i / 40 })),
      { t: 1000, slot: 0, kind: 'shader', value: 'bio_lenia_continuous' },
    ];
    const timeline = { hz: 20, durationMs: 2000, events };
    const shaders = { 'aurora-curtain': urlOf('aurora-curtain'), bio_lenia_continuous: urlOf('bio_lenia_continuous') };
    mkdirSync('test-results', { recursive: true });
    for (const container of ['mp4', 'webm'] as const) {
      const clip = await page.evaluate(
        (req) => (window as any).__pixelocity__.exportOfflineClip(req),
        { shaders, timeline, width: 320, height: 180, fps: 30, container },
      );
      test.info().annotations.push({ type: 'export', description: JSON.stringify({ container, ...clip, base64: undefined }) });
      expect(clip.frames).toBe(60);
      expect(clip.type).toBe(container === 'mp4' ? 'video/mp4' : 'video/webm');
      const file = join('test-results', `golden-export.${container}`);
      writeFileSync(file, Buffer.from(clip.base64, 'base64'));
      if (!hasFfprobe) continue;
      const probe = JSON.parse(execFileSync('ffprobe', [
        '-v', 'error', '-count_frames', '-select_streams', 'v:0',
        '-show_entries', 'stream=nb_read_frames,width,height,codec_name:format=duration',
        '-show_entries', 'frame=pts_time', '-of', 'json', file,
      ]).toString()) as { streams: Array<{ nb_read_frames: string; width: number; height: number }>; frames: Array<{ pts_time: string }>; format: { duration: string } };
      expect(Number(probe.streams[0]!.nb_read_frames), `${container}: ffprobe frame count`).toBe(60);
      expect(probe.streams[0]).toMatchObject({ width: 320, height: 180 });
      const pts = probe.frames.map((f) => Number(f.pts_time));
      expect(new Set(pts.map((p) => p.toFixed(4))).size, `${container}: duplicate timestamps`).toBe(60);
      for (let i = 1; i < pts.length; i++) expect(pts[i]! - pts[i - 1]!).toBeCloseTo(1 / 30, 3);
      expect(Number(probe.format.duration)).toBeCloseTo(2, 1);
    }
  });
});
