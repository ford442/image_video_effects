import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { expandWgslIncludes } from '../src/wasm/bridge/wgslInclude';

const IDS = [
  'gen-fireworks-nocturne',
  'gen-ghost-flame',
  'gen-fireworks-crackle-palm',
  'gen-fireworks-audio-symphony',
  'gen-fireworks-wind-ripple',
  'gen-fireworks-smoke-bloom',
  'gen-fireworks-willow-cascade',
  'gen-ifs-fractal-flame',
  'gen-fireworks-chrysanthemum',
  'gen-fireworks-fan-shell',
];

for (const id of IDS) {
  test(`${id}: finite feedback, live controls and late playback`, async ({ page }, testInfo) => {
    test.setTimeout(180_000);
    const source = await readFile(`public/shaders/${id}.wgsl`, 'utf8');
    const code = await expandWgslIncludes(source, (name) => readFile(`public/shaders/${name}`, 'utf8'), `${id}.wgsl`);
    const definition: {
      params?: { default: number }[];
      'x-meta': { upgrade: { params: { default: number }[] } };
    } = JSON.parse(await readFile(`shader_definitions/generative/${id}.json`, 'utf8'));
    const defaults = (definition.params ?? definition['x-meta'].upgrade.params).map((p) => p.default);
    await page.route('http://localhost:3475/**', (route) => route.fulfill({
      contentType: 'text/html',
      body: '<!doctype html><title>Shader compute regression</title>',
    }));
    await page.goto('http://localhost:3475/');

    const result = await page.evaluate(async ({ id, code, defaults }) => {
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) throw new Error('Software WebGPU adapter required');
      const device = await adapter.requestDevice();
      const errors: string[] = [];
      device.addEventListener('uncapturederror', (event) => errors.push(event.error.message));
      device.pushErrorScope('validation');
      const module = device.createShaderModule({ code });
      const compilation = await module.getCompilationInfo();
      const compileErrors = compilation.messages.filter((m) => m.type === 'error');
      if (compileErrors.length) throw new Error(compileErrors.map((m) => m.message).join('\n'));

      const width = 65;
      const height = 49;
      const usage = GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.STORAGE_BINDING
        | GPUTextureUsage.COPY_SRC | GPUTextureUsage.COPY_DST;
      const texture = (format: GPUTextureFormat) => device.createTexture({ size: [width, height], format, usage });
      const input = texture('rgba8unorm');
      const output = texture('rgba32float');
      const state = texture('rgba32float');
      const unused = texture('rgba32float');
      const history = texture('rgba32float');
      const depthRead = texture('r32float');
      const depthWrite = texture('r32float');
      const buffer = (size: number, usage: GPUBufferUsageFlags) => device.createBuffer({ size, usage: usage | GPUBufferUsage.COPY_DST });
      const uniforms = buffer(848, GPUBufferUsage.UNIFORM);
      const extra = buffer(1024, GPUBufferUsage.STORAGE);
      const plasma = buffer(16, GPUBufferUsage.STORAGE);
      const V = GPUShaderStage.COMPUTE;
      const layout = device.createBindGroupLayout({ entries: [
        { binding: 0, visibility: V, sampler: { type: 'filtering' } },
        { binding: 1, visibility: V, texture: { sampleType: 'float' } },
        { binding: 2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding: 3, visibility: V, buffer: { type: 'uniform' } },
        { binding: 4, visibility: V, texture: { sampleType: 'unfilterable-float' } },
        { binding: 5, visibility: V, sampler: { type: 'non-filtering' } },
        { binding: 6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
        { binding: 7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding: 8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding: 9, visibility: V, texture: { sampleType: 'unfilterable-float' } },
        { binding: 10, visibility: V, buffer: { type: 'storage' } },
        { binding: 11, visibility: V, sampler: { type: 'comparison' } },
        { binding: 12, visibility: V, buffer: { type: 'read-only-storage' } },
      ] });
      const pipeline = await device.createComputePipelineAsync({
        layout: device.createPipelineLayout({ bindGroupLayouts: [layout] }),
        compute: { module, entryPoint: 'main' },
      });
      const group = device.createBindGroup({ layout, entries: [
        { binding: 0, resource: device.createSampler({ minFilter: 'linear', magFilter: 'linear' }) },
        { binding: 1, resource: input.createView() },
        { binding: 2, resource: output.createView() },
        { binding: 3, resource: { buffer: uniforms } },
        { binding: 4, resource: depthRead.createView() },
        { binding: 5, resource: device.createSampler() },
        { binding: 6, resource: depthWrite.createView() },
        { binding: 7, resource: state.createView() },
        { binding: 8, resource: unused.createView() },
        { binding: 9, resource: history.createView() },
        { binding: 10, resource: { buffer: extra } },
        { binding: 11, resource: device.createSampler({ compare: 'less' }) },
        { binding: 12, resource: { buffer: plasma } },
      ] });
      const image = new Uint8Array(width * height * 4);
      for (let i = 0; i < image.length; i += 4) {
        image[i] = (i / 4) % width * 3;
        image[i + 1] = Math.floor(i / 4 / width) * 4;
        image[i + 2] = 100;
        image[i + 3] = 200;
      }
      device.queue.writeTexture({ texture: input }, image, { bytesPerRow: width * 4 }, [width, height]);
      device.queue.writeTexture({ texture: depthRead }, new Float32Array(width * height).fill(0.5), { bytesPerRow: width * 4 }, [width, height]);

      const rgbaRow = Math.ceil(width * 16 / 256) * 256;
      const depthRow = Math.ceil(width * 4 / 256) * 256;
      const rgbaSize = rgbaRow * height;
      const readback = buffer(rgbaSize * 2 + depthRow * height, GPUBufferUsage.MAP_READ);
      const snapshots: { label: string; rgbRange: number; alphaRange: number; difference: number }[] = [];
      const references = new Map<number, number[]>();
      async function render(label: string, params: number[], time: number, audio: number[], held = false, click = false) {
        device.queue.writeTexture({ texture: history }, new Float32Array(width * height * 4), { bytesPerRow: width * 16 }, [width, height]);
        device.queue.writeBuffer(extra, 0, new Float32Array(256));
        device.queue.writeBuffer(plasma, 0, new Float32Array(audio));
        for (let frame = 0; frame < 12; frame++) {
          const u = new Float32Array(212);
          const now = time + frame / 60;
          u.set([now, click ? 1 : 0, width, height, now, 0.5, 0.65, held ? 1 : 0]);
          u.set(params, 8);
          // The renderer always writes zero padding in ripple.w.
          u.set([0.5, 0.5, time - 0.25, 0], 12);
          device.queue.writeBuffer(uniforms, 0, u);
          const encoder = device.createCommandEncoder();
          const pass = encoder.beginComputePass();
          pass.setPipeline(pipeline);
          pass.setBindGroup(0, group);
          pass.dispatchWorkgroups(Math.ceil(width / 16), Math.ceil(height / 16));
          pass.end();
          encoder.copyTextureToTexture({ texture: state }, { texture: history }, [width, height]);
          device.queue.submit([encoder.finish()]);
        }
        const encoder = device.createCommandEncoder();
        encoder.copyTextureToBuffer({ texture: output }, { buffer: readback, bytesPerRow: rgbaRow }, [width, height]);
        encoder.copyTextureToBuffer({ texture: state }, { buffer: readback, offset: rgbaSize, bytesPerRow: rgbaRow }, [width, height]);
        encoder.copyTextureToBuffer({ texture: depthWrite }, { buffer: readback, offset: rgbaSize * 2, bytesPerRow: depthRow }, [width, height]);
        device.queue.submit([encoder.finish()]);
        await readback.mapAsync(GPUMapMode.READ);
        const data = new Float32Array(readback.getMappedRange());
        const pixels: number[] = [];
        let minRGB = 1, maxRGB = 0, minAlpha = 1, maxAlpha = 0;
        for (let y = 0; y < height; y++) {
          for (let x = 0; x < width; x++) {
            const offset = y * rgbaRow / 4 + x * 4;
            for (let c = 0; c < 4; c++) {
              const value = data[offset + c];
              const stateValue = data[rgbaSize / 4 + offset + c];
              if (value === undefined || !Number.isFinite(value) || value < 0 || value > 1.00001
                || stateValue === undefined || !Number.isFinite(stateValue)) throw new Error(`${label}: invalid RGBA/state`);
              if (id !== 'gen-ghost-flame' && !(id === 'gen-fireworks-audio-symphony' && y === 0 && x <= 6)
                && Math.abs(stateValue - value) > 0.00001) throw new Error(`${label}: display history packing mismatch`);
              if (id === 'gen-ghost-flame') {
                const lo = c === 2 ? -1 : 0;
                const hi = c === 2 ? 1 : c === 3 ? 10 : 2;
                if (stateValue < lo || stateValue > hi) throw new Error(`${label}: flame state out of bounds`);
              }
              pixels.push(value);
              if (c < 3) { minRGB = Math.min(minRGB, value); maxRGB = Math.max(maxRGB, value); }
              else { minAlpha = Math.min(minAlpha, value); maxAlpha = Math.max(maxAlpha, value); }
            }
            const depth = data[rgbaSize / 2 + y * depthRow / 4 + x];
            if (depth === undefined || !Number.isFinite(depth) || depth < 0 || depth > 1) throw new Error(`${label}: invalid depth`);
          }
        }
        readback.unmap();
        const reference = references.get(time);
        const difference = reference
          ? pixels.reduce((sum, value, i) => sum + Math.abs(value - (reference[i] ?? 0)), 0) / pixels.length : 0;
        if (label.startsWith('default')) references.set(time, pixels);
        snapshots.push({ label, rgbRange: maxRGB - minRGB, alphaRange: maxAlpha - minAlpha, difference });
      }
      await render('default', defaults, 2.3, [0.2, 0.3, 0.25, 0.2]);
      await render('minimum', [0, 0, 0, 0], 0, [0, 0, 0, 0]);
      await render('maximum', [1, 1, 1, 1], 4.5, [2, 2, 2, 2], true, true);
      await render('late', defaults, 3600, [0, 0, 0, 0]);
      await render('pointer', defaults, 2.3, [0.2, 0.3, 0.25, 0.2], true);
      if (id === 'gen-fireworks-wind-ripple') {
        await render('click-zero-padding', defaults, 2.3, [0.2, 0.3, 0.25, 0.2], false, true);
      }
      await render('default-early', defaults, 0.4, [0.2, 0.3, 0.25, 0.2]);
      await render('pointer-early', defaults, 0.4, [0.2, 0.3, 0.25, 0.2], true);
      // Gated controls need a live shell/click, not just an arbitrary idle instant.
      for (const time of [0.4, 2.3]) {
        const click = id === 'gen-fireworks-wind-ripple';
        await render(`default-controls-${time}`, defaults, time, [0.2, 0.3, 0.25, 0.2], false, click);
        for (let index = 0; index < 4; index++) {
          const params = [...defaults];
          params[index] = defaults[index] === 1 ? 0 : 1;
          await render(`slider-${index}-${time}`, params, time, [0.2, 0.3, 0.25, 0.2], false, click);
        }
      }
      const validation = await device.popErrorScope();
      if (validation) errors.push(validation.message);
      device.destroy();
      return { errors, snapshots };
    }, { id, code, defaults });
    await testInfo.attach('compute-results', { body: JSON.stringify(result, null, 2), contentType: 'application/json' });
    expect(result.errors).toEqual([]);
    for (const snapshot of result.snapshots) {
      expect(snapshot.rgbRange, `${id} ${snapshot.label}: flat RGB`).toBeGreaterThan(0.01);
      expect(snapshot.alphaRange, `${id} ${snapshot.label}: flat alpha`).toBeGreaterThan(0.001);
      if (snapshot.label === 'click-zero-padding') {
        expect(snapshot.difference, `${id} ${snapshot.label}: no visible response`).toBeGreaterThan(0.000001);
      }
    }
    for (const control of ['pointer', 'slider-0', 'slider-1', 'slider-2', 'slider-3']) {
      const differences = result.snapshots.filter((s) => s.label.startsWith(control)).map((s) => s.difference);
      expect(Math.max(...differences), `${id} ${control}: no visible response`).toBeGreaterThan(0.000001);
    }
  });
}
