/**
 * slotCompositor.ts
 *
 * The GPU side of the layer compositor (#1512 Part B): layer array, r8unorm masks,
 * the mask / feather render pipelines and the composite compute pipeline. Planning,
 * uniform packing and the `FrameCompositor` interface are in compositor.ts.
 *
 * Loaded lazily (chunk `compositor`, scripts/check-bundle-size.mjs) by WebGPURenderer
 * the first time a parallel group composites; until then that group falls back to
 * last-one-wins, exactly as when an allocation fails.
 */

import type { InternalColorFormat } from '../../config/formatPolicy';
import { rewriteWgslStorageFormats } from '../wgslFormatRewrite';
import {
  COMPOSITE_PARAMS_BYTES,
  MASK_FORMAT,
  MAX_COMPOSITE_LAYERS,
  PARAM_SLICE_BYTES,
  compositorTextureBytes,
  featherRadiusPx,
  packCompositeParams,
  packFeatherParams,
  packMaskParams,
  type CompositeGroupPlan,
  type CompositorAttachment,
  type CompositorStats,
  type FrameCompositor,
  type MaskDraw,
} from './compositor';
import { COMPOSITE_WGSL, FEATHER_WGSL, MASK_WGSL } from './compositorShaders.generated';
import type { PassProfiler } from './nodeScale';
import { scopeFailed, withOutOfMemoryScope } from './validationScope';

const COMPOSITE_WORKGROUP = 8;

interface MaskTarget {
  texture: GPUTexture;
  view: GPUTextureView;
  paramsOffset: number;
  bindGroup: GPUBindGroup | null;
  featherH: GPUBindGroup | null;
  featherV: GPUBindGroup | null;
}

/** Everything one composite needs, resolved (and null-checked) once per group. */
interface CompositorGpu {
  device: GPUDevice;
  depth: GPUTexture;
  layers: GPUTexture;
  /** Built for one internal colour format; rebuilt when it changes. */
  pipelines: CompositorPipelines;
  compositeParams: GPUBuffer;
  /** Mask params at k×256, feather H at (6+k)×256, feather V at (12+k)×256. */
  sliceParams: GPUBuffer;
}

interface CompositorPipelines {
  format: InternalColorFormat;
  composite: GPUComputePipeline;
  compositeLayout: GPUBindGroupLayout;
  mask: GPURenderPipeline;
  maskLayout: GPUBindGroupLayout;
  feather: GPURenderPipeline;
  featherLayout: GPUBindGroupLayout;
  sampler: GPUSampler;
}

export class SlotCompositor implements FrameCompositor {
  private device: GPUDevice | null = null;
  private colorFormat: InternalColorFormat = 'rgba32float';
  private width = 0;
  private height = 0;
  private depthTex: GPUTexture | null = null;

  private pipelines: CompositorPipelines | null = null;
  private layerTex: GPUTexture | null = null;
  private layerCount = 0;
  private readonly masks: Array<MaskTarget | null> = Array.from({ length: MAX_COMPOSITE_LAYERS }, () => null);
  private scratch: GPUTexture | null = null;
  private whiteMask: GPUTexture | null = null;
  private compositeParams: GPUBuffer | null = null;
  private sliceParams: GPUBuffer | null = null;

  private compositeBindGroup: GPUBindGroup | null = null;
  private compositeBindKey = '';
  private textureIds = new WeakMap<GPUTexture, number>();
  private nextTextureId = 1;

  private composites = 0;
  private error: string | null = null;
  private warnings: string[] = [];

  /** Bind to this frame's device, tier format, working size and depth map. Cheap when unchanged. */
  attach(a: CompositorAttachment): void {
    if (a.device !== this.device) {
      this.destroy();
      this.device = a.device;
    }
    if (a.colorFormat !== this.colorFormat) {
      this.colorFormat = a.colorFormat;
      this.releaseLayers();
    }
    if (a.scaledW !== this.width || a.scaledH !== this.height) {
      this.width = a.scaledW;
      this.height = a.scaledH;
      this.releaseLayers();
      this.releaseMasks();
      this.error = null;
    }
    if (a.depthTex !== this.depthTex) {
      this.depthTex = a.depthTex;
      this.dropBindGroups();
    }
  }

  /** Free layer / mask memory (no parallel group composited this frame). Pipelines stay. */
  releaseTextures(): void {
    this.releaseLayers();
    this.releaseMasks();
  }

  destroy(): void {
    this.releaseTextures();
    this.compositeParams?.destroy();
    this.sliceParams?.destroy();
    this.whiteMask?.destroy();
    this.compositeParams = null;
    this.sliceParams = null;
    this.whiteMask = null;
    this.pipelines = null;
    this.compositeBindGroup = null;
    this.device = null;
    this.depthTex = null;
    this.composites = 0;
    this.error = null;
    this.warnings = [];
  }

  stats(): CompositorStats {
    const maskCount = this.masks.filter(Boolean).length;
    const layers = this.layerTex ? this.layerCount : 0;
    const bytes = compositorTextureBytes(this.width, this.height, this.colorFormat, layers, maskCount, !!this.scratch);
    return {
      layers,
      masks: maskCount,
      textureMiB: Math.round((bytes / (1024 * 1024)) * 10) / 10,
      composites: this.composites,
      error: this.error,
      warnings: [...this.warnings],
    };
  }

  /** False after an allocation failure at this size / device. */
  get available(): boolean {
    return !!this.device && this.error === null && this.width > 0 && this.height > 0;
  }

  encodeLayerCopy(encoder: GPUCommandEncoder, source: GPUTexture, layer: number, layerCount: number): boolean {
    if (!this.available || layer >= layerCount) return false;
    const layers = this.ensureLayers(layerCount);
    if (!layers) return false;
    encoder.copyTextureToTexture(
      { texture: source },
      { texture: layers, origin: [0, 0, layer] },
      [this.width, this.height, 1],
    );
    return true;
  }

  encodeComposite(
    encoder: GPUCommandEncoder,
    plan: CompositeGroupPlan,
    base: GPUTexture,
    out: GPUTexture,
    profile?: PassProfiler,
  ): boolean {
    const gpu = this.resolveGpu(plan.layerCount);
    if (!gpu) return false;
    this.warnings = plan.warnings;

    for (const layer of plan.layers) {
      if (!layer.mask) continue;
      const target = this.ensureMask(gpu.device, layer.layer);
      if (!target) return false;
      this.encodeMask(gpu, encoder, target, layer.layer, layer.mask, profile);
    }

    gpu.device.queue.writeBuffer(gpu.compositeParams, 0, packCompositeParams(plan));
    const bindGroup = this.getCompositeBindGroup(gpu, base, out);
    const stamps = profile?.('composite');
    const pass = encoder.beginComputePass(stamps ? { label: 'composite', timestampWrites: stamps } : { label: 'composite' });
    pass.setPipeline(gpu.pipelines.composite);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(
      Math.ceil(this.width / COMPOSITE_WORKGROUP),
      Math.ceil(this.height / COMPOSITE_WORKGROUP),
      1,
    );
    pass.end();
    this.composites++;
    return true;
  }

  private resolveGpu(layerCount: number): CompositorGpu | null {
    const device = this.device;
    const depth = this.depthTex;
    if (!device || !depth || !this.available) return null;
    const layers = this.ensureLayers(layerCount);
    const pipelines = this.ensurePipelines(device);
    if (!layers || !pipelines) return null;
    this.compositeParams ??= device.createBuffer({
      label: 'compositor-params',
      size: COMPOSITE_PARAMS_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.sliceParams ??= device.createBuffer({
      label: 'compositor-slice-params',
      size: 3 * MAX_COMPOSITE_LAYERS * PARAM_SLICE_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    return { device, depth, layers, pipelines, compositeParams: this.compositeParams, sliceParams: this.sliceParams };
  }

  private encodeMask(
    gpu: CompositorGpu,
    encoder: GPUCommandEncoder,
    target: MaskTarget,
    layer: number,
    mask: MaskDraw,
    profile?: PassProfiler,
  ): void {
    const { device, pipelines, sliceParams } = gpu;
    device.queue.writeBuffer(sliceParams, target.paramsOffset, packMaskParams(mask));
    target.bindGroup ??= device.createBindGroup({
      label: `compositor-mask-${layer}`,
      layout: pipelines.maskLayout,
      entries: [
        { binding: 0, resource: gpu.layers.createView({ dimension: '2d-array' }) },
        { binding: 1, resource: gpu.depth.createView() },
        { binding: 2, resource: { buffer: sliceParams, offset: target.paramsOffset, size: 16 } },
      ],
    });
    this.drawFullScreen(encoder, pipelines.mask, target.bindGroup, target.view, `mask-${layer}`, profile);

    const radius = featherRadiusPx(mask.feather);
    if (radius <= 0) return;
    const scratch = this.ensureScratch(device);
    if (!scratch) return;
    const hOffset = (MAX_COMPOSITE_LAYERS + layer) * PARAM_SLICE_BYTES;
    const vOffset = (2 * MAX_COMPOSITE_LAYERS + layer) * PARAM_SLICE_BYTES;
    device.queue.writeBuffer(sliceParams, hOffset, packFeatherParams(true, radius, this.width, this.height));
    device.queue.writeBuffer(sliceParams, vOffset, packFeatherParams(false, radius, this.width, this.height));
    const featherGroup = (src: GPUTexture, offset: number, label: string) => device.createBindGroup({
      label,
      layout: pipelines.featherLayout,
      entries: [
        { binding: 0, resource: src.createView() },
        { binding: 1, resource: pipelines.sampler },
        { binding: 2, resource: { buffer: sliceParams, offset, size: 16 } },
      ],
    });
    target.featherH ??= featherGroup(target.texture, hOffset, `compositor-feather-h-${layer}`);
    target.featherV ??= featherGroup(scratch, vOffset, `compositor-feather-v-${layer}`);
    this.drawFullScreen(encoder, pipelines.feather, target.featherH, scratch.createView(), `feather-h-${layer}`, profile);
    this.drawFullScreen(encoder, pipelines.feather, target.featherV, target.view, `feather-v-${layer}`, profile);
  }

  private drawFullScreen(
    encoder: GPUCommandEncoder,
    pipeline: GPURenderPipeline,
    bindGroup: GPUBindGroup,
    view: GPUTextureView,
    label: string,
    profile?: PassProfiler,
  ): void {
    const stamps = profile?.(label);
    const pass = encoder.beginRenderPass({
      label,
      colorAttachments: [{ view, loadOp: 'clear', storeOp: 'store', clearValue: { r: 1, g: 0, b: 0, a: 1 } }],
      ...(stamps ? { timestampWrites: stamps } : {}),
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.draw(3);
    pass.end();
  }

  private textureId(tex: GPUTexture): number {
    let id = this.textureIds.get(tex);
    if (id === undefined) {
      id = this.nextTextureId++;
      this.textureIds.set(tex, id);
    }
    return id;
  }

  private getCompositeBindGroup(gpu: CompositorGpu, base: GPUTexture, out: GPUTexture): GPUBindGroup {
    const white = this.ensureWhiteMask(gpu.device);
    const maskTex = this.masks.map((m) => m?.texture ?? white);
    const key = [base, out, gpu.layers, gpu.depth, ...maskTex].map((t) => this.textureId(t)).join(',');
    if (this.compositeBindGroup && key === this.compositeBindKey) return this.compositeBindGroup;
    this.compositeBindGroup = gpu.device.createBindGroup({
      label: 'compositor-composite',
      layout: gpu.pipelines.compositeLayout,
      entries: [
        { binding: 0, resource: base.createView() },
        { binding: 1, resource: gpu.layers.createView({ dimension: '2d-array' }) },
        ...maskTex.map((t, i) => ({ binding: 2 + i, resource: t.createView() })),
        { binding: 8, resource: gpu.depth.createView() },
        { binding: 9, resource: out.createView() },
        { binding: 10, resource: { buffer: gpu.compositeParams, offset: 0, size: COMPOSITE_PARAMS_BYTES } },
      ],
    });
    this.compositeBindKey = key;
    return this.compositeBindGroup;
  }

  private ensurePipelines(device: GPUDevice): CompositorPipelines | null {
    if (this.pipelines?.format === this.colorFormat) return this.pipelines;
    this.dropBindGroups();
    try {
      this.pipelines = createCompositorPipelines(device, this.colorFormat);
      return this.pipelines;
    } catch (e) {
      this.error = `compositor pipelines: ${e instanceof Error ? e.message : String(e)}`;
      this.pipelines = null;
      return null;
    }
  }

  /**
   * Layers are created on first use (and re-created when the count grows or shrinks).
   * The out-of-memory verdict is asynchronous; a failure turns the compositor off at
   * this size so the group falls back to last-one-wins instead of retrying every frame.
   */
  private ensureLayers(count: number): GPUTexture | null {
    const device = this.device;
    if (!device || count <= 0) return null;
    if (this.layerTex && this.layerCount === count) return this.layerTex;
    this.releaseLayers();
    const texture = this.allocate(device, () => device.createTexture({
      label: `compositor-layers×${count}`,
      size: { width: this.width, height: this.height, depthOrArrayLayers: count },
      format: this.colorFormat,
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      // Compatibility mode binds a texture only with the view dimension it was created for.
      textureBindingViewDimension: '2d-array',
    }));
    if (!texture) return null;
    this.layerTex = texture;
    this.layerCount = count;
    return texture;
  }

  private ensureMask(device: GPUDevice, layer: number): MaskTarget | null {
    const existing = this.masks[layer];
    if (existing) return existing;
    const texture = this.allocate(device, () => device.createTexture({
      label: `compositor-mask-${layer}`,
      size: [this.width, this.height],
      format: MASK_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    }));
    if (!texture) return null;
    const target: MaskTarget = {
      texture,
      view: texture.createView(),
      paramsOffset: layer * PARAM_SLICE_BYTES,
      bindGroup: null,
      featherH: null,
      featherV: null,
    };
    this.masks[layer] = target;
    this.compositeBindGroup = null;
    return target;
  }

  private ensureScratch(device: GPUDevice): GPUTexture | null {
    this.scratch ??= this.allocate(device, () => device.createTexture({
      label: 'compositor-mask-scratch',
      size: [this.width, this.height],
      format: MASK_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    }));
    return this.scratch;
  }

  private ensureWhiteMask(device: GPUDevice): GPUTexture {
    if (this.whiteMask) return this.whiteMask;
    const texture = device.createTexture({
      label: 'compositor-mask-none',
      size: [1, 1],
      format: MASK_FORMAT,
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    });
    device.queue.writeTexture({ texture }, new Uint8Array([255]), { bytesPerRow: 1 }, [1, 1]);
    this.whiteMask = texture;
    return texture;
  }

  private allocate(device: GPUDevice, create: () => GPUTexture): GPUTexture | null {
    let texture: GPUTexture | null = null;
    try {
      void withOutOfMemoryScope(device, () => {
        texture = create();
        return texture;
      }).then((result) => {
        if (!scopeFailed(result)) return;
        this.error = `compositor allocation failed at ${this.width}×${this.height}`;
        console.warn(`[WebGPU] ${this.error}; parallel groups fall back to last-one-wins`);
        this.releaseTextures();
      });
    } catch (e) {
      this.error = `compositor allocation failed: ${e instanceof Error ? e.message : String(e)}`;
      return null;
    }
    return texture;
  }

  /** Every cached bind group references textures; any of them changing invalidates them. */
  private dropBindGroups(): void {
    this.compositeBindGroup = null;
    for (const m of this.masks) {
      if (!m) continue;
      m.bindGroup = null;
      m.featherH = null;
      m.featherV = null;
    }
  }

  private releaseLayers(): void {
    this.layerTex?.destroy();
    this.layerTex = null;
    this.layerCount = 0;
    this.dropBindGroups();
  }

  private releaseMasks(): void {
    for (let i = 0; i < this.masks.length; i++) {
      this.masks[i]?.texture.destroy();
      this.masks[i] = null;
    }
    this.scratch?.destroy();
    this.scratch = null;
    this.compositeBindGroup = null;
  }
}

/** The three compositor pipelines for one internal colour format (throws on a device error). */
function createCompositorPipelines(device: GPUDevice, format: InternalColorFormat): CompositorPipelines {
  const sampled = (
    binding: number,
    visibility: GPUShaderStageFlags,
    viewDimension: GPUTextureViewDimension = '2d',
    sampleType: GPUTextureSampleType = 'unfilterable-float',
  ): GPUBindGroupLayoutEntry => ({ binding, visibility, texture: { sampleType, viewDimension } });
  const uniform = (binding: number, visibility: GPUShaderStageFlags): GPUBindGroupLayoutEntry => ({
    binding, visibility, buffer: { type: 'uniform' },
  });
  const C = GPUShaderStage.COMPUTE;
  const F = GPUShaderStage.FRAGMENT;

  const compositeLayout = device.createBindGroupLayout({
    label: 'compositor-composite-BGL',
    entries: [
      sampled(0, C),
      sampled(1, C, '2d-array'),
      ...Array.from({ length: MAX_COMPOSITE_LAYERS }, (_, i) => sampled(2 + i, C)),
      sampled(8, C),
      { binding: 9, visibility: C, storageTexture: { access: 'write-only', format } },
      uniform(10, C),
    ],
  });
  const composite = device.createComputePipeline({
    label: `compositor-composite-${format}`,
    layout: device.createPipelineLayout({ bindGroupLayouts: [compositeLayout] }),
    compute: {
      module: device.createShaderModule({
        label: 'compositor-composite',
        code: rewriteWgslStorageFormats(COMPOSITE_WGSL, format),
      }),
      entryPoint: 'main',
    },
  });

  const fullScreen = (label: string, code: string, layout: GPUBindGroupLayout) => {
    const module = device.createShaderModule({ label, code });
    return device.createRenderPipeline({
      label,
      layout: device.createPipelineLayout({ bindGroupLayouts: [layout] }),
      vertex: { module, entryPoint: 'vs' },
      fragment: { module, entryPoint: 'fs', targets: [{ format: MASK_FORMAT }] },
      primitive: { topology: 'triangle-list' },
    });
  };
  const maskLayout = device.createBindGroupLayout({
    label: 'compositor-mask-BGL',
    entries: [sampled(0, F, '2d-array'), sampled(1, F), uniform(2, F)],
  });
  const featherLayout = device.createBindGroupLayout({
    label: 'compositor-feather-BGL',
    entries: [
      sampled(0, F, '2d', 'float'),
      { binding: 1, visibility: F, sampler: { type: 'filtering' } },
      uniform(2, F),
    ],
  });
  return {
    format,
    composite,
    compositeLayout,
    mask: fullScreen('compositor-mask', MASK_WGSL, maskLayout),
    maskLayout,
    feather: fullScreen('compositor-feather', FEATHER_WGSL, featherLayout),
    featherLayout,
    sampler: device.createSampler({
      label: 'compositor-feather-sampler',
      magFilter: 'linear',
      minFilter: 'linear',
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    }),
  };
}
