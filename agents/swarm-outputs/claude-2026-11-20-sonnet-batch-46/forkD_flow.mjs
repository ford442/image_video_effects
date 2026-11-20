// forkD: history-ring harness for optical-flow-tracer.
// node forkD_flow.mjs <wgsl> <out.png> [size=160] [frames=14] [p1,p2,p3,p4] [bass,mid,treb]
// env: VX,VY object velocity px/frame (default 3,1.5) | D ring depth (default 4) | PERF=1 drains each frame, prints PERF min
//      OBJ=0 static scene | NOISE sensor noise amplitude (default 0.0)
import { chromium } from '/root/image_video_effects/node_modules/playwright/index.mjs';
import fs from 'fs'; import http from 'http'; import path from 'path';
const [wgslPath, outPng, sizeS = '160', framesS = '14', paramsS = '', audioS = '0,0,0'] = process.argv.slice(2);
const VX = +(process.env.VX ?? 3), VY = +(process.env.VY ?? 1.5), D = +(process.env.D ?? 4), PERF = process.env.PERF === '1', OBJ = process.env.OBJ !== '0', NOISE = +(process.env.NOISE ?? 0);
const shaderDir = path.dirname(wgslPath);
let src = fs.readFileSync(wgslPath, 'utf8').replace(/#include\s+"([^"]+)"/g, (_, f) => fs.readFileSync(path.join(shaderDir, f), 'utf8'));
const params = paramsS ? paramsS.split(',').map(Number) : [0.6, 0.4, 0.5, 0.35];
const audio = audioS.split(',').map(Number);
const server = http.createServer((q, r) => { r.writeHead(200, { 'content-type': 'text/html' }); r.end('<!doctype html><body></body>'); });
await new Promise(res => server.listen(0, '127.0.0.1', res));
const browser = await chromium.launch({ headless: true, args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-webgpu-adapter=swiftshader', '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--no-sandbox'] });
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${server.address().port}/`);
const result = await page.evaluate(async ({ src, size, frames, params, audio, VX, VY, D, PERF, OBJ, NOISE }) => {
  const adapter = await navigator.gpu.requestAdapter();
  const hasF32Filt = adapter.features.has('float32-filterable');
  const device = await adapter.requestDevice({ requiredFeatures: hasF32Filt ? ['float32-filterable'] : [] });
  const mod = device.createShaderModule({ code: src });
  const info = await mod.getCompilationInfo();
  const errs = info.messages.filter(m => m.type === 'error').map(m => `${m.lineNum}:${m.message}`);
  if (errs.length) return { errs };
  device.pushErrorScope('validation');
  const fST = hasF32Filt ? 'float' : 'unfilterable-float'; const V = GPUShaderStage.COMPUTE;
  const layout = device.createBindGroupLayout({ entries: [
    { binding: 0, visibility: V, sampler: { type: 'filtering' } }, { binding: 1, visibility: V, texture: { sampleType: fST } },
    { binding: 2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } }, { binding: 3, visibility: V, buffer: { type: 'uniform' } },
    { binding: 4, visibility: V, texture: { sampleType: 'unfilterable-float' } }, { binding: 5, visibility: V, sampler: { type: 'non-filtering' } },
    { binding: 6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
    { binding: 7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } }, { binding: 8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
    { binding: 9, visibility: V, texture: { sampleType: fST } }, { binding: 10, visibility: V, buffer: { type: 'storage' } },
    { binding: 11, visibility: V, sampler: { type: 'comparison' } }, { binding: 12, visibility: V, buffer: { type: 'read-only-storage' } },
    { binding: 13, visibility: V, texture: { sampleType: fST, viewDimension: '2d-array' } } ] });
  let pipe;
  try { pipe = await device.createComputePipelineAsync({ layout: device.createPipelineLayout({ bindGroupLayouts: [layout] }), compute: { module: mod, entryPoint: 'main' } }); } catch (e) { return { errs: ['pipeline: ' + e.message] }; }
  { const pe = await device.popErrorScope(); if (pe) return { errs: ['pipeline: ' + pe.message] }; device.pushErrorScope('validation'); }
  const W = size, H = size, S = GPUTextureUsage;
  const tex = (fmt, usage) => device.createTexture({ size: [W, H], format: fmt, usage });
  const writeT = tex('rgba32float', S.STORAGE_BINDING | S.COPY_SRC), depthW = tex('r32float', S.STORAGE_BINDING);
  const A = tex('rgba32float', S.STORAGE_BINDING | S.COPY_SRC), B = tex('rgba32float', S.STORAGE_BINDING);
  const C = tex('rgba32float', S.TEXTURE_BINDING | S.COPY_DST), readT = tex('rgba32float', S.TEXTURE_BINDING | S.COPY_DST), readD = tex('r32float', S.TEXTURE_BINDING | S.COPY_DST);
  const hist = device.createTexture({ size: [W, H, D], format: 'rgba32float', usage: S.TEXTURE_BINDING | S.COPY_DST });
  const dd = new Float32Array(W * H).fill(0.5); device.queue.writeTexture({ texture: readD }, dd, { bytesPerRow: W * 4 }, [W, H]);
  const ubuf = device.createBuffer({ size: 16 * 3 + 16 * 50, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const extra = device.createBuffer({ size: 256 * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  const plasma = device.createBuffer({ size: 64, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(plasma, 0, new Float32Array([audio[0], audio[1], audio[2], 0]));
  const samp = device.createSampler({ magFilter: 'linear', minFilter: 'linear' }), nf = device.createSampler(), cmp = device.createSampler({ compare: 'less' });
  const all = { 0: samp, 1: readT.createView(), 2: writeT.createView(), 3: { buffer: ubuf }, 4: readD.createView(), 5: nf, 6: depthW.createView(), 7: A.createView(), 8: B.createView(), 9: C.createView(), 10: { buffer: extra }, 11: cmp, 12: { buffer: plasma }, 13: hist.createView({ dimension: '2d-array' }) };
  let entries = Object.entries(all).map(([b, r]) => ({ binding: +b, resource: r })), bg = null;
  for (let tries = 0; tries < 14 && !bg; tries++) {
    device.pushErrorScope('validation'); const cand = device.createBindGroup({ layout, entries }); const e = await device.popErrorScope();
    if (!e) { bg = cand; break; } const m = /binding (?:index )?(\d+)/i.exec(e.message); if (!m) return { errs: ['bindgroup: ' + e.message] }; entries = entries.filter(x => x.binding !== +m[1]);
  }
  if (!bg) return { errs: ['no bindgroup'] };
  const h = (a, b) => { const q = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return q - Math.floor(q); };
  const gen = (f) => { // static textured background + textured disc translating by (VX,VY) px/frame
    const d = new Float32Array(W * H * 4); const cx = 0.3 * W + VX * f, cy = 0.5 * H + VY * f, R = 0.17 * W;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const u = x / W, v = y / H; let L = 0.45 + 0.18 * Math.sin(u * 23 + v * 9) * Math.cos(v * 19) + 0.1 * Math.sin(u * 61) * Math.sin(v * 47);
      if (OBJ) { const r = Math.hypot(x - cx, y - cy); if (r < R) { L = 0.55 + 0.35 * Math.sin((x - cx) * 0.55) * Math.cos((y - cy) * 0.45 + 0.7) + 0.1 * Math.sin((x - cx) * 1.3 + (y - cy) * 0.9); if (r > R - 2) L = 0.95; } }
      L += NOISE * (h(x + f * 7.3, y + f * 3.1) - 0.5);
      L = Math.max(0, Math.min(1, L)); const i = (y * W + x) * 4; d[i] = L * (0.7 + 0.3 * u); d[i + 1] = L * (0.85 - 0.2 * u); d[i + 2] = L * (0.6 + 0.4 * v); d[i + 3] = 1;
    } return d; };
  const ft = []; const rbPrev = device.createBuffer({ size: W * H * 16, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  for (let f = 0; f < frames; f++) {
    device.queue.writeTexture({ texture: readT }, gen(f), { bytesPerRow: W * 16 }, [W, H]);
    const t = 0.05 * (f + 1); const ub = new Float32Array(12 + 200);
    ub.set([t, 0, W, H, t, 0.5, 0.5, 0, ...params]); device.queue.writeBuffer(ubuf, 0, ub);
    device.queue.writeBuffer(extra, 16, new Float32Array([f % D]));
    const enc = device.createCommandEncoder(); const pass = enc.beginComputePass(); pass.setPipeline(pipe); pass.setBindGroup(0, bg); pass.dispatchWorkgroups(Math.ceil(W / 16), Math.ceil(H / 16), 1); pass.end();
    enc.copyTextureToTexture({ texture: A }, { texture: C }, [W, H]);
    enc.copyTextureToTexture({ texture: writeT }, { texture: hist, origin: [0, 0, f % D] }, [W, H, 1]);
    if (f === frames - 2) enc.copyTextureToBuffer({ texture: A }, { buffer: rbPrev, bytesPerRow: W * 16 }, [W, H]);
    const tq = performance.now(); device.queue.submit([enc.finish()]); if (PERF || f === frames - 1) { await device.queue.onSubmittedWorkDone(); ft.push(performance.now() - tq); }
  }
  const rbs = [writeT, A].map(() => device.createBuffer({ size: W * H * 16, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ }));
  const enc = device.createCommandEncoder(); [writeT, A].forEach((tx, i) => enc.copyTextureToBuffer({ texture: tx }, { buffer: rbs[i], bytesPerRow: W * 16 }, [W, H])); device.queue.submit([enc.finish()]);
  await Promise.all([...rbs, rbPrev].map(r => r.mapAsync(GPUMapMode.READ)));
  const out = rbs.map(r => Array.from(new Float32Array(r.getMappedRange())));
  const flowPrev = Array.from(new Float32Array(rbPrev.getMappedRange()));
  const srcLast = Array.from(gen(frames - 1));
  const vErr = await device.popErrorScope();
  return { ft, data: out[0], flow: out[1], flowPrev, srcLast, W, H, verr: vErr ? vErr.message : null };
}, { src, size: +sizeS, frames: +framesS, params, audio, VX, VY, D, PERF, OBJ, NOISE });
await browser.close(); server.close();
if (result.errs) { console.log('ERRORS', result.errs.join('\n')); process.exit(1); }
if (PERF) { const f = result.ft.slice(1).sort((a, b) => a - b); console.log('PERF ' + JSON.stringify({ min: +f[0].toFixed(1), med: +f[Math.floor(f.length / 2)].toFixed(1) })); }
const { W, H, data, flow, flowPrev, srcLast } = result;
// --- flow quality metrics (px/frame; A.xy = flow*flowScale) ---
{ const fs_ = (0.05 + params[1] * 0.95) * (1 + audio[0] * 0.3); const fN = +framesS - 1; const cx = 0.3 * W + VX * fN, cy = 0.5 * H + VY * fN, R = 0.17 * W;
  let e2 = 0, ne = 0, halo = 0, nh = 0, far = 0, nf = 0, jit = 0, nj = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = (y * W + x) * 4; const r = Math.hypot(x - cx, y - cy); const fx = flow[i] / fs_, fy = flow[i + 1] / fs_; const m = Math.hypot(fx, fy);
    if (!Number.isFinite(m)) continue;
    if (OBJ && r < 0.7 * R) { e2 += (fx - VX) ** 2 + (fy - VY) ** 2; ne++; }
    else if (OBJ && r > R + 3 && r < R + 10) { halo += m; nh++; }
    else if (!OBJ || r > R + 10) { far += m; nf++; }
    if (OBJ && r < 0.5 * R) { jit += Math.hypot(flow[i] - flowPrev[i], flow[i + 1] - flowPrev[i + 1]) / fs_; nj++; } }
  console.log('FLOWQ ' + JSON.stringify({ rmsErrInside: +Math.sqrt(e2 / Math.max(ne, 1)).toFixed(3), haloMean: +(halo / Math.max(nh, 1)).toFixed(3), farMean: +(far / Math.max(nf, 1)).toFixed(3), jitterInside: +(jit / Math.max(nj, 1)).toFixed(3) })); }
// panels: source | output rgb | alpha | flow (hue=dir, val=|v|/4 px)
const out = Buffer.alloc(W * 4 * H * 3); let nan = 0, fm = 0, fn = 0; const cl = v => Math.max(0, Math.min(255, Math.round(v * 255)));
const hsv = (h, s, v) => { const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6]; };
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const i = (y * W + x) * 4; let [r, g, b, a] = data.slice(i, i + 4); if (![r, g, b, a].every(Number.isFinite)) { nan++; r = 1; g = 0; b = 1; a = 1; }
  const o = (y * W * 4 + x) * 3; out.set([cl(srcLast[i]), cl(srcLast[i + 1]), cl(srcLast[i + 2])], o); out.set([cl(r), cl(g), cl(b)], o + W * 3); out.set([cl(a), cl(a), cl(a)], o + W * 6);
  const fx = flow[i], fy = flow[i + 1]; const mag = Math.hypot(fx, fy); const hc = hsv((Math.atan2(fy, fx) / (2 * Math.PI) + 1) % 1, 1, Math.min(1, mag / 4)); out.set(hc.map(cl), o + W * 9);
  if (Number.isFinite(mag)) { fm += mag; fn++; }
}
fs.writeFileSync(outPng + '.rgb', out);
const { execFileSync } = await import('child_process');
execFileSync('python3', ['-c', `import sys;from PIL import Image;d=open(sys.argv[1],'rb').read();Image.frombytes('RGB',(${W * 4},${H}),d).save(sys.argv[2])`, outPng + '.rgb', outPng]); fs.unlinkSync(outPng + '.rgb');
if (process.env.RAW) fs.writeFileSync(process.env.RAW, Buffer.from(new Float32Array(data).buffer));
console.log(JSON.stringify({ nan, meanFlow: +(fm / Math.max(fn, 1)).toFixed(3), verr: result.verr }));
