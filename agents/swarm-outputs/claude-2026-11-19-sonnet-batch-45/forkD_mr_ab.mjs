// forkD A/B timing: one device, N shader variants with PRIVATE texture sets, dispatches alternated
// frame by frame (A,B,C,A,B,C,...) with the queue drained after each, so machine-load noise is shared.
// usage: node mr_ab.mjs <size> <cycles> <p1,p2,p3,p4> <mx,my,down> <bass,mid,treb> <wgsl0> <wgsl1> ...
// prints min / p25 / median ms per variant and ratio vs variant 0. Env: SRC=img for a synthetic source.
import { chromium } from '/root/image_video_effects/node_modules/playwright/index.mjs';
import fs from 'fs';
import http from 'http';
import path from 'path';

const [sizeS, cyclesS, paramsS, mouseS, audioS, ...files] = process.argv.slice(2);
const SRCIMG = process.env.SRC === 'img';
const srcs = files.map(f => {
  const dir = path.dirname(f);
  return fs.readFileSync(f, 'utf8').replace(/#include\s+"([^"]+)"/g, (_, n) => fs.readFileSync(path.join(dir, n), 'utf8'));
});
const params = paramsS.split(',').map(Number), mouse = mouseS.split(',').map(Number), audio = audioS.split(',').map(Number);
const server = http.createServer((q, r) => { r.writeHead(200, { 'content-type': 'text/html' }); r.end('<!doctype html><body></body>'); });
await new Promise(res => server.listen(0, '127.0.0.1', res));
const browser = await chromium.launch({ headless: true, args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-webgpu-adapter=swiftshader', '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--no-sandbox'] });
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${server.address().port}/`);
const result = await page.evaluate(async ({ srcs, size, cycles, params, mouse, audio, SRCIMG }) => {
  const adapter = await navigator.gpu.requestAdapter();
  const f32f = adapter.features.has('float32-filterable');
  const device = await adapter.requestDevice({ requiredFeatures: f32f ? ['float32-filterable'] : [] });
  const fST = f32f ? 'float' : 'unfilterable-float';
  const V = GPUShaderStage.COMPUTE, S = GPUTextureUsage;
  const layout = device.createBindGroupLayout({ entries: [
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
  ] });
  const W = size, H = size;
  const tex = (fmt, usage) => device.createTexture({ size: [W, H], format: fmt, usage });
  const samp = device.createSampler({ magFilter: 'linear', minFilter: 'linear' }), nf = device.createSampler(), cmp = device.createSampler({ compare: 'less' });
  const variants = [];
  for (const src of srcs) {
    const mod = device.createShaderModule({ code: src });
    const info = await mod.getCompilationInfo();
    const errs = info.messages.filter(m => m.type === 'error').map(m => `${m.lineNum}:${m.message}`);
    if (errs.length) return { errs };
    const pipe = await device.createComputePipelineAsync({ layout: device.createPipelineLayout({ bindGroupLayouts: [layout] }), compute: { module: mod, entryPoint: 'main' } });
    const writeT = tex('rgba32float', S.STORAGE_BINDING | S.COPY_SRC), depthW = tex('r32float', S.STORAGE_BINDING);
    const A = tex('rgba32float', S.STORAGE_BINDING | S.COPY_SRC), B = tex('rgba32float', S.STORAGE_BINDING);
    const C = tex('rgba32float', S.TEXTURE_BINDING | S.COPY_DST), readT = tex('rgba32float', S.TEXTURE_BINDING | S.COPY_DST), readD = tex('r32float', S.TEXTURE_BINDING | S.COPY_DST);
    if (SRCIMG) {
      const d = new Float32Array(W * H * 4), dd = new Float32Array(W * H);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const u = x / W, v = y / H;
        let L = 0.5 + 0.35 * Math.sin(u * 9) * Math.sin(v * 7) + 0.15 * Math.sin(u * 40) * Math.sin(v * 33);
        if (Math.hypot(u - 0.7, v - 0.3) < 0.18) L = 0.95;
        if (Math.hypot(u - 0.25, v - 0.7) < 0.12) L = 0.04;
        L = Math.max(0, Math.min(1, L));
        const i = (y * W + x) * 4; d[i] = L * (0.6 + 0.4 * u); d[i + 1] = L * (0.9 - 0.3 * u); d[i + 2] = L * (0.5 + 0.5 * v); d[i + 3] = 1;
        dd[y * W + x] = Math.max(0, Math.min(1, 0.35 + 0.25 * v));
      }
      device.queue.writeTexture({ texture: readT }, d, { bytesPerRow: W * 16 }, [W, H]);
      device.queue.writeTexture({ texture: readD }, dd, { bytesPerRow: W * 4 }, [W, H]);
    }
    const ubuf = device.createBuffer({ size: 16 * 3 + 16 * 50, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
    const extra = device.createBuffer({ size: 256 * 4, usage: GPUBufferUsage.STORAGE });
    const plasma = device.createBuffer({ size: 64, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
    device.queue.writeBuffer(plasma, 0, new Float32Array([audio[0], audio[1], audio[2], 0]));
    const hist = device.createTexture({ size: [W, H, 1], format: 'rgba32float', usage: S.TEXTURE_BINDING });
    const all = { 0: samp, 1: readT.createView(), 2: writeT.createView(), 3: { buffer: ubuf }, 4: readD.createView(), 5: nf, 6: depthW.createView(), 7: A.createView(), 8: B.createView(), 9: C.createView(), 10: { buffer: extra }, 11: cmp, 12: { buffer: plasma }, 13: hist.createView({ dimension: '2d-array' }) };
    let entries = Object.entries(all).map(([b, r]) => ({ binding: +b, resource: r })), bg = null;
    for (let t = 0; t < 14 && !bg; t++) {
      device.pushErrorScope('validation');
      const cand = device.createBindGroup({ layout, entries });
      const e = await device.popErrorScope();
      if (!e) { bg = cand; break; }
      const m = /binding (?:index )?(\d+)/i.exec(e.message);
      if (!m) return { errs: ['bindgroup: ' + e.message] };
      entries = entries.filter(x => x.binding !== +m[1]);
    }
    variants.push({ pipe, bg, A, C, ubuf, times: [] });
  }
  for (let f = 0; f < cycles; f++) {
    const t = 0.1 * (f + 1);
    for (const v of variants) {
      const ub = new Float32Array(12 + 200);
      ub.set([t, 0, W, H, t, mouse[0], mouse[1], mouse[2], ...params]);
      device.queue.writeBuffer(v.ubuf, 0, ub);
      const t0 = performance.now();
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass();
      pass.setPipeline(v.pipe); pass.setBindGroup(0, v.bg);
      pass.dispatchWorkgroups(Math.ceil(W / 16), Math.ceil(H / 16), 1);
      pass.end();
      enc.copyTextureToTexture({ texture: v.A }, { texture: v.C }, [W, H]);
      device.queue.submit([enc.finish()]);
      await device.queue.onSubmittedWorkDone();
      v.times.push(performance.now() - t0);
    }
  }
  return { times: variants.map(v => v.times) };
}, { srcs, size: +sizeS, cycles: +cyclesS, params, mouse, audio, SRCIMG });
await browser.close(); server.close();
if (result.errs) { console.log('ERRORS', result.errs.join('\n')); process.exit(1); }
const stat = a => { const s = a.slice(3).sort((x, y) => x - y); return { min: s[0], p25: s[Math.floor(s.length * 0.25)], med: s[Math.floor(s.length / 2)] }; };
const st = result.times.map(stat);
// paired per-cycle ratio vs variant 0 (adjacent in time -> shared load)
const paired = result.times.map(t => { const r = t.slice(3).map((x, i) => x / result.times[0][i + 3]).sort((a, b) => a - b); return r[Math.floor(r.length / 2)]; });
st.forEach((s, i) => console.log(`${path.basename(path.dirname(files[i]))}/${path.basename(files[i])}  min ${s.min.toFixed(1)}  p25 ${s.p25.toFixed(1)}  med ${s.med.toFixed(1)}  | ratio min ${(s.min / st[0].min).toFixed(2)} p25 ${(s.p25 / st[0].p25).toFixed(2)} paired-median ${paired[i].toFixed(2)}`));
