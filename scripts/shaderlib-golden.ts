/// <reference types="@webgpu/types" />
/**
 * shaderlib-golden.ts — run the shader standard library golden cases on a GPU.
 *
 * Builds one compute shader from public/shaders/_std (composeStdModules) that
 * evaluates every case in src/contracts/shaderlib_golden.json, runs it on
 * SwiftShader WebGPU in headless Chromium, and compares the results.
 *
 *   npm run shaderlib:golden              # check (exit 1 on any mismatch)
 *   npm run shaderlib:golden -- --update  # (re)capture non-analytic cases;
 *                                          # analytic cases must still match
 *
 * The naga-only half of this (every module and the harness validate) runs in
 * the unit suite: src/shaderlib/stdlib.test.ts. This script needs Chromium,
 * which the Cloud VM and CI's Playwright image have; it needs no hardware GPU.
 */
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import type { AddressInfo } from 'node:net';
import { chromium } from 'playwright';
import {
  buildGoldenHarness,
  diffGolden,
  GoldenCase,
  parseStdModule,
  STD_DIR,
  STD_MODULE_NAMES,
  StdModule,
  stdFileName,
} from '../src/shaderlib/stdlib';

const ROOT = path.resolve(__dirname, '..');
const GOLDEN = path.join(ROOT, 'src/contracts/shaderlib_golden.json');

// AGENTS.md: all six flags are needed for a working SwiftShader WebGPU adapter.
const SWIFTSHADER_ARGS = [
  '--enable-unsafe-webgpu',
  '--enable-features=Vulkan',
  '--use-vulkan=swiftshader',
  '--use-webgpu-adapter=swiftshader',
  '--enable-unsafe-swiftshader',
  '--use-angle=swiftshader',
];

interface GoldenFile {
  version: number;
  description: string;
  cases: (GoldenCase & { analytic: boolean })[];
}

function loadModules(): Map<string, StdModule> {
  const m = new Map<string, StdModule>();
  for (const n of STD_MODULE_NAMES) {
    m.set(n, parseStdModule(fs.readFileSync(path.join(ROOT, STD_DIR, stdFileName(n)), 'utf8')));
  }
  return m;
}

async function runOnGpu(wgsl: string, floats: number): Promise<Float32Array> {
  // WebGPU needs a secure context; about:blank is not one, localhost is.
  const server = http.createServer((_q, s) => {
    s.setHeader('content-type', 'text/html');
    s.end('<!doctype html><title>shaderlib golden</title>');
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  // The Cloud VM preinstalls one Chromium at /opt/pw-browsers/chromium, which a
  // pinned @playwright/test version may not find by itself (AGENTS.md).
  const preinstalled = '/opt/pw-browsers/chromium';
  const executablePath =
    process.env.PW_CHROMIUM_PATH ?? (fs.existsSync(preinstalled) && !fs.existsSync(chromium.executablePath()) ? preinstalled : undefined);
  const browser = await chromium.launch({ args: SWIFTSHADER_ARGS, executablePath });
  try {
    const page = await browser.newPage();
    await page.goto(`http://localhost:${(server.address() as AddressInfo).port}/`);
    const out = await page.evaluate(
      async ({ code, n }) => {
        const adapter = await navigator.gpu?.requestAdapter();
        if (!adapter) throw new Error('no WebGPU adapter (SwiftShader flags?)');
        const device = await adapter.requestDevice();
        device.pushErrorScope('validation');
        const module = device.createShaderModule({ code });
        const info = await module.getCompilationInfo();
        const errs = info.messages.filter((m) => m.type === 'error');
        if (errs.length) throw new Error(errs.map((e) => `${e.lineNum}:${e.linePos} ${e.message}`).join('\n'));
        const size = n * 4;
        const buf = device.createBuffer({ size, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
        const rb = device.createBuffer({ size, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
        const pipeline = device.createComputePipeline({ layout: 'auto', compute: { module, entryPoint: 'std_golden_main' } });
        const bg = device.createBindGroup({
          layout: pipeline.getBindGroupLayout(0),
          entries: [{ binding: 0, resource: { buffer: buf } }],
        });
        const enc = device.createCommandEncoder();
        const pass = enc.beginComputePass();
        pass.setPipeline(pipeline);
        pass.setBindGroup(0, bg);
        pass.dispatchWorkgroups(1);
        pass.end();
        enc.copyBufferToBuffer(buf, 0, rb, 0, size);
        device.queue.submit([enc.finish()]);
        const err = await device.popErrorScope();
        if (err) throw new Error(err.message);
        await rb.mapAsync(GPUMapMode.READ);
        return Array.from(new Uint32Array(rb.getMappedRange().slice(0)));
      },
      { code: wgsl, n: floats },
    );
    return new Float32Array(Uint32Array.from(out).buffer);
  } finally {
    await browser.close();
    server.close();
  }
}

async function main(): Promise<void> {
  const update = process.argv.includes('--update');
  const golden = JSON.parse(fs.readFileSync(GOLDEN, 'utf8')) as GoldenFile;
  const modules = loadModules();
  const { wgsl, offsets, floats } = buildGoldenHarness(modules, golden.cases);
  const out = await runOnGpu(wgsl, floats);
  const u = new Uint32Array(out.buffer);

  if (update) {
    golden.cases.forEach((c, i) => {
      if (c.analytic) return;
      const o = offsets[i] ?? 0;
      const w = c.type === 'f32' || c.type === 'u32' ? 1 : Number(c.type.slice(3));
      c.expected = Array.from({ length: w }, (_, k) =>
        c.type === 'u32' ? (u[o + k] ?? 0) : Number((out[o + k] ?? NaN).toPrecision(9)),
      );
    });
    fs.writeFileSync(GOLDEN, JSON.stringify(golden, null, 2) + '\n');
  }

  const bad = diffGolden(golden.cases, offsets, out);
  if (bad.length) {
    console.error(`shaderlib golden: ${bad.length} of ${golden.cases.length} cases differ\n  ${bad.join('\n  ')}`);
    process.exit(1);
  }
  console.log(`shaderlib golden: ${golden.cases.length} cases match${update ? ' (non-analytic cases recaptured)' : ''}`);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
