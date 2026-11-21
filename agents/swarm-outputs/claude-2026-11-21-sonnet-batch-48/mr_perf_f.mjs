// fork2 mini renderer: node minirender.mjs <wgsl> <out.png> [size] [frames] [t_end] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]
import { chromium } from '/root/image_video_effects/node_modules/playwright/index.mjs';
import fs from 'fs';
import http from 'http';
import path from 'path';

const T0 = +(process.env.T0 || 0);
const SRCTEX = process.env.SRC === 'tex'; const RIPS = process.env.RIPPLES ? process.env.RIPPLES.split(';').map(r=>r.split(',').map(Number)) : []; const SRCIMG = process.env.SRC === 'img' || SRCTEX; const A16 = process.env.A16 === '1'; const MPATH = process.env.MPATH ? JSON.parse(process.env.MPATH) : null; const SRCFLAT = process.env.SRCFLAT ? +process.env.SRCFLAT : null; const SEEDC = process.env.SEEDC ? process.env.SEEDC.split(',').map(Number) : null; const CPROC = process.env.CPROC === '1'; const NOFB = process.env.NOFB === '1'; const MULT = process.env.MULT ? +process.env.MULT : 1; // optional start time: frames span [T0, T0 + tEnd]
const [wgslPath, outPng, sizeS = '160', framesS = '20', tEndS = '1.5', paramsS = '', mouseS = '0.5,0.5,0', audioS = '0,0,0'] = process.argv.slice(2);
const shaderDir = path.dirname(wgslPath);
let src = fs.readFileSync(wgslPath, 'utf8');
src = src.replace(/#include\s+"([^"]+)"/g, (_, f) => fs.readFileSync(path.join(shaderDir, f), 'utf8'));
if (process.env.A16 === '1') { src = src.replace(/(dataTexture[AB]: texture_storage_2d<)rgba32float/g, '$1rgba16float'); }
const params = paramsS ? paramsS.split(',').map(Number) : [1, 1, 1, 1];
const mouse = mouseS.split(',').map(Number);
const audio = audioS.split(',').map(Number);

const html = '<!doctype html><html><body></body></html>';
const server = http.createServer((q, r) => { r.writeHead(200, { 'content-type': 'text/html' }); r.end(html); });
await new Promise(res => server.listen(0, '127.0.0.1', res));
const port = server.address().port;
const browser = await chromium.launch({ headless: true, args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-webgpu-adapter=swiftshader', '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--no-sandbox'] });
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${port}/`);
const t0 = Date.now();
const result = await page.evaluate(async ({ src, size, frames, tEnd, params, mouse, audio, T0, SRCIMG, SRCTEX, RIPS, A16, MPATH, SRCFLAT, SEEDC, CPROC, NOFB }) => {
  const adapter = await navigator.gpu.requestAdapter();
  const hasF32Filt = adapter.features.has('float32-filterable');
  const device = await adapter.requestDevice({ requiredFeatures: hasF32Filt ? ['float32-filterable'] : [] });
  const mod = device.createShaderModule({ code: src });
  const info = await mod.getCompilationInfo();
  const errs = info.messages.filter(m => m.type === 'error').map(m => `${m.lineNum}:${m.message}`);
  if (errs.length) return { errs };
  device.pushErrorScope('validation');
  const tc0 = performance.now();
  // Explicit layout mirroring src/renderer/webgpu/pipeline.ts (computeBGL): depth (4) is
  // unfilterable-float, so sampling it with the filtering u_sampler fails like in the app.
  const fST = hasF32Filt ? 'float' : 'unfilterable-float';
  const V = GPUShaderStage.COMPUTE;
  const layout = device.createBindGroupLayout({ entries: [
    { binding: 0, visibility: V, sampler: { type: 'filtering' } },
    { binding: 1, visibility: V, texture: { sampleType: fST } },
    { binding: 2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
    { binding: 3, visibility: V, buffer: { type: 'uniform' } },
    { binding: 4, visibility: V, texture: { sampleType: 'unfilterable-float' } },
    { binding: 5, visibility: V, sampler: { type: 'non-filtering' } },
    { binding: 6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
    { binding: 7, visibility: V, storageTexture: { access: 'write-only', format: A16 ? 'rgba16float' : 'rgba32float' } },
    { binding: 8, visibility: V, storageTexture: { access: 'write-only', format: A16 ? 'rgba16float' : 'rgba32float' } },
    { binding: 9, visibility: V, texture: { sampleType: A16 ? 'float' : fST } },
    { binding: 10, visibility: V, buffer: { type: 'storage' } },
    { binding: 11, visibility: V, sampler: { type: 'comparison' } },
    { binding: 12, visibility: V, buffer: { type: 'read-only-storage' } },
    { binding: 13, visibility: V, texture: { sampleType: fST, viewDimension: '2d-array' } },
  ] });
  let pipe;
  try { pipe = await device.createComputePipelineAsync({ layout: device.createPipelineLayout({ bindGroupLayouts: [layout] }), compute: { module: mod, entryPoint: 'main' } }); } catch (e) { return { errs: ['pipeline: ' + e.message] }; }
  { const pe = await device.popErrorScope(); if (pe) return { errs: ['pipeline: ' + pe.message] }; device.pushErrorScope('validation'); }
  const compileMs = performance.now() - tc0;
  const _wh = String(size).split("x").map(Number); const W = _wh[0], H = _wh[1] || _wh[0];
  const tex = (fmt, usage) => device.createTexture({ size: [W, H], format: fmt, usage });
  const S = GPUTextureUsage;
  const writeT = tex('rgba32float', S.STORAGE_BINDING | S.COPY_SRC);
  const depthW = tex('r32float', S.STORAGE_BINDING);
  const A = tex(A16 ? 'rgba16float' : 'rgba32float', S.STORAGE_BINDING | S.COPY_SRC);
  const B = tex(A16 ? 'rgba16float' : 'rgba32float', S.STORAGE_BINDING);
  const C = tex(A16 ? 'rgba16float' : 'rgba32float', S.TEXTURE_BINDING | S.COPY_DST);
  const readT = tex('rgba32float', S.TEXTURE_BINDING | S.COPY_DST);
  const readD = tex('r32float', S.TEXTURE_BINDING | S.COPY_DST);
  if (SRCIMG) {
    const d = new Float32Array(W * H * 4);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const u = x / W, v = y / H;
      let L = 0.5 + 0.35 * Math.sin(u * 9.0) * Math.sin(v * 7.0) + 0.15 * Math.sin(u * 40) * Math.sin(v * 33);
      const dd = Math.hypot(u - 0.7, v - 0.3); if (dd < 0.18) L = 0.95;
      if (Math.hypot(u - 0.25, v - 0.7) < 0.12) L = 0.04;
      if (SRCTEX) {
        const h = (a, b) => { const q = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return q - Math.floor(q); };
        // oriented gratings in four quadrants (0,45,90,135 deg), thin ridge + dark line, steps, noise speckle
        const qx = u < 0.5 ? 0 : 1, qy = v < 0.5 ? 0 : 1, ang = (qy * 2 + qx) * Math.PI / 4;
        const px = x, py = y, k = 2 * Math.PI / (W / 22);
        L = 0.5 + 0.28 * Math.sin(k * (px * Math.cos(ang) + py * Math.sin(ang)));
        if (u > 0.28 && u < 0.72 && v > 0.28 && v < 0.72) { L = 0.55 + 0.35 * Math.sign(Math.sin(u * 14) * Math.sin(v * 14)); }
        if (Math.abs(u - 0.5) < 1.2 / W) L = 0.97;
        if (Math.abs(v - 0.5) < 1.2 / H) L = 0.03;
        if (Math.hypot(u - 0.2, v - 0.8) < 0.09) L = 0.96;
        L += (h(x, y) - 0.5) * 0.14;
        if (h(x + 9, y + 3) > 0.995) L = 1.0; if (h(x + 4, y + 8) < 0.005) L = 0.0;
      }
      L = Math.max(0, Math.min(1, L));
      const i = (y * W + x) * 4; d[i] = L * (0.6 + 0.4 * u); d[i + 1] = L * (0.9 - 0.3 * u); d[i + 2] = L * (0.5 + 0.5 * v); d[i + 3] = 1;
      if (SRCFLAT !== null) { d[i] = SRCFLAT; d[i+1] = SRCFLAT; d[i+2] = SRCFLAT; }
    }
    device.queue.writeTexture({ texture: readT }, d, { bytesPerRow: W * 16 }, [W, H]);
    if (CPROC) {
      const dc = new Float32Array(W * H * 4);
      const R = 2;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        let s0 = 0, s1 = 0, s2 = 0, n = 0;
        for (let j = -R; j <= R; j++) for (let i2 = -R; i2 <= R; i2++) {
          const xx = Math.min(W - 1, Math.max(0, x + i2)), yy = Math.min(H - 1, Math.max(0, y + j));
          const q = (yy * W + xx) * 4; s0 += d[q]; s1 += d[q + 1]; s2 += d[q + 2]; n++;
        }
        const o = (y * W + x) * 4; const post = v => Math.round(v * 4) / 4;
        dc[o] = post(s1 / n); dc[o + 1] = post(s2 / n); dc[o + 2] = post(s0 / n); dc[o + 3] = 1;
      }
      device.queue.writeTexture({ texture: C }, dc, { bytesPerRow: W * 16 }, [W, H]);
    }
  }
  if (SEEDC) { const dc = new Float32Array(W*H*4); for (let i = 0; i < W*H; i++) { dc[i*4]=SEEDC[0]; dc[i*4+1]=SEEDC[1]; dc[i*4+2]=SEEDC[2]; dc[i*4+3]=SEEDC[3]; } device.queue.writeTexture({ texture: C }, dc, { bytesPerRow: W*16 }, [W,H]); }
  if (SRCIMG) { // synthetic depth: near disc (0.7,0.3), far disc (0.25,0.7), gentle ramp elsewhere
    const dd = new Float32Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const u = x / W, v = y / H;
      let Z = 0.35 + 0.25 * v + 0.1 * Math.sin(u * 6.0);
      const a = Math.hypot(u - 0.7, v - 0.3); if (a < 0.22) Z = 0.9 - a * 0.8;
      const b = Math.hypot(u - 0.25, v - 0.7); if (b < 0.15) Z = 0.1 + b * 0.5;
      dd[y * W + x] = Math.max(0, Math.min(1, Z));
    }
    device.queue.writeTexture({ texture: readD }, dd, { bytesPerRow: W * 4 }, [W, H]);
  }
  const ubuf = device.createBuffer({ size: 16 * 3 + 16 * 50, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const extra = device.createBuffer({ size: 256 * 4, usage: GPUBufferUsage.STORAGE });
  const plasma = device.createBuffer({ size: 16 * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(plasma, 0, new Float32Array([audio[0], audio[1], audio[2], 0]));
  const samp = device.createSampler({ magFilter: 'linear', minFilter: 'linear' });
  const nf = device.createSampler();
  const cmp = device.createSampler({ compare: 'less' });
  const hist = device.createTexture({ size: [W, H, 1], format: 'rgba32float', usage: GPUTextureUsage.TEXTURE_BINDING });
  const all = {
    0: samp, 1: readT.createView(), 2: writeT.createView(), 3: { buffer: ubuf }, 4: readD.createView(), 5: nf,
    6: depthW.createView(), 7: A.createView(), 8: B.createView(), 9: C.createView(), 10: { buffer: extra }, 11: cmp, 12: { buffer: plasma },
    13: hist.createView({ dimension: '2d-array' }),
  };
  // 'auto' layout drops unused bindings; try each and keep the ones accepted.
  let entries = Object.entries(all).map(([b, r]) => ({ binding: +b, resource: r }));
  let bg = null;
  for (let tries = 0; tries < 14 && !bg; tries++) {
    device.pushErrorScope('validation');
    const cand = device.createBindGroup({ layout, entries });
    const e = await device.popErrorScope();
    if (!e) { bg = cand; break; }
    const m = /binding (?:index )?(\d+)/i.exec(e.message);
    if (!m) return { errs: ['bindgroup: ' + e.message] };
    entries = entries.filter(x => x.binding !== +m[1]);
  }
  if (!bg) return { errs: ['no bindgroup'] };
  const tf0 = performance.now();
  for (let f = 0; f < frames; f++) {
    const t = T0 + (frames > 1 ? tEnd * (f + 1) / frames : tEnd);
    const ub = new Float32Array(12 + 200);
    let mm = mouse; if (MPATH) { const a = frames > 1 ? f / (frames - 1) : 1; mm = [0,1,2].map(k => MPATH[0][k] + (MPATH[1][k] - MPATH[0][k]) * a); }
    ub.set([t, RIPS.length, W, H, t, mm[0], mm[1], mm[2], ...params]); RIPS.forEach((r, i) => ub.set([r[0], r[1], t - r[2], 0], 12 + i * 4));
    device.queue.writeBuffer(ubuf, 0, ub);
    const enc = device.createCommandEncoder();
    const pass = enc.beginComputePass();
    pass.setPipeline(pipe); pass.setBindGroup(0, bg);
    pass.dispatchWorkgroups(Math.ceil(W / 16), Math.ceil(H / 16), 1);
    pass.end();
    if (!NOFB) enc.copyTextureToTexture({ texture: A }, { texture: C }, [W, H]);
    const tq0 = performance.now();
    device.queue.submit([enc.finish()]);
    await device.queue.onSubmittedWorkDone();
    (globalThis.__ft = globalThis.__ft || []).push(performance.now() - tq0);
  }
  const rb = device.createBuffer({ size: W * H * 16, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  const enc = device.createCommandEncoder();
  enc.copyTextureToBuffer({ texture: writeT }, { buffer: rb, bytesPerRow: W * 16 }, [W, H]);
  device.queue.submit([enc.finish()]);
  await rb.mapAsync(GPUMapMode.READ);
  const data = Array.from(new Float32Array(rb.getMappedRange()));
  const vErr = await device.popErrorScope();
  return { ft: globalThis.__ft || [], compileMs, frameMs: (performance.now() - tf0) / frames, data, W, H, verr: vErr ? vErr.message : null };
}, { src, size: sizeS, frames: +framesS, tEnd: +tEndS, params, mouse, audio, T0, SRCIMG, SRCTEX, RIPS, A16, MPATH, SRCFLAT, SEEDC, CPROC, NOFB });
await browser.close(); server.close();
if (result.ft) { const f = result.ft.slice(1).sort((a,b)=>a-b); console.log('PERF ' + JSON.stringify({min: +f[0].toFixed(1), p25: +f[Math.floor(f.length*0.25)].toFixed(1), med: +f[Math.floor(f.length/2)].toFixed(1)})); }
if (result.errs) { console.log('ERRORS', result.errs.join('\n')); process.exit(1); }
const { W, H, data } = result;
// raw rgb | composite over white with alpha | alpha
const out = Buffer.alloc(W * 3 * H * 3);
let nan = 0, sum = 0, sum2 = 0, asum = 0;
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const i = (y * W + x) * 4;
  let [r, g, b, a] = data.slice(i, i + 4);
  if (![r, g, b, a].every(Number.isFinite)) { nan++; r = 1; g = 0; b = 1; a = 1; }
  const cl = v => Math.max(0, Math.min(255, Math.round(v * 255)));
  const L = (r + g + b) / 3; sum += L; sum2 += L * L; asum += a;
  const o = (y * W * 3 + x) * 3;
  out.set([cl(r), cl(g), cl(b)], o);
  const ac = Math.max(0, Math.min(1, a));
  out.set([cl(r * ac + 1 - ac), cl(g * ac + 1 - ac), cl(b * ac + 1 - ac)], o + W * 3);
  out.set([cl(a), cl(a), cl(a)], o + W * 6);
}
const n = W * H;
fs.writeFileSync(outPng + '.rgb', out);
const { execFileSync } = await import('child_process');
execFileSync('python3', ['-c', `import sys;from PIL import Image;d=open(sys.argv[1],'rb').read();Image.frombytes('RGB',(${W * 3},${H}),d).save(sys.argv[2])`, outPng + '.rgb', outPng]);
fs.unlinkSync(outPng + '.rgb');
if (process.env.RAW) fs.writeFileSync(process.env.RAW, Buffer.from(new Float32Array(data).buffer));
console.log(JSON.stringify({ compileMs: Math.round(result.compileMs), frameMs: Math.round(result.frameMs), nan, meanL: +(sum / n).toFixed(3), stdL: +Math.sqrt(sum2 / n - (sum / n) ** 2).toFixed(3), meanA: +(asum / n).toFixed(3), verr: result.verr, wall: Date.now() - t0 }));
