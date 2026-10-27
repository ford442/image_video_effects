/**
 * compositor.ts
 *
 * GPU half of the layer compositor (#1512 Part B). The frame plan
 * (compositorPlan.ts) captures slot outputs into a 2d-array layer stack and
 * emits one composite op per parallel group (or per chained slot with a
 * non-replace layer). For each composite this encodes:
 *
 *   1. mask draws: one render pass per masked layer into its r8unorm
 *      maskTex layer (luma / depth / another slot's matte), plus an optional
 *      two-pass separable feather through a scratch layer
 *   2. one compute dispatch that blends every layer over the base (readTex)
 *      into writeTex, in the internal colour format (rgba16float/32float),
 *      so HDR values survive to the canvas
 *
 * Everything is allocated lazily on the first frame that composites and is
 * grow-only until the working size or colour format changes. Bind groups are
 * cached against the textures they hold (no per-frame bind-group churn); the
 * per-op parameters are uniform blocks addressed with dynamic offsets.
 *
 * Shaders: public/shaders/_compositor/*.wgsl (bundled; never in the catalog).
 */

import type { InternalColorFormat } from '../../config/formatPolicy';
import { rewriteWgslStorageFormats } from '../wgslFormatRewrite';
import compositeWgsl from '../../../public/shaders/_compositor/composite.wgsl?raw';
import maskWgsl from '../../../public/shaders/_compositor/mask.wgsl?raw';
import featherWgsl from '../../../public/shaders/_compositor/feather.wgsl?raw';
import { FEATHER_MAX_RADIUS_PX } from '../layerState';
import {
  KEY_SOFTNESS,
  MAX_STACK_LAYERS,
  type CaptureLayerOp,
  type CompositeLayer,
  type CompositeOp,
} from './compositorPlan';
import type { FrameCompositor } from './framePlan';
import type { PassProfiler } from './nodeScale';
import { arrayBindingDescriptor } from './compat';

export { compositeWgsl as COMPOSITE_WGSL, maskWgsl as MASK_WGSL, featherWgsl as FEATHER_WGSL };

/** The layer stack may not exceed this; a frame that needs more renders as replace. */
export const COMPOSITOR_STACK_BUDGET_BYTES = 384 * 1024 * 1024;

/** Uniform blocks per frame (the plan never needs more: 1 + 6 composites, 6 masks, 12 feathers). */
const COMPOSITE_BLOCKS = 8;
const MASK_BLOCKS = 8;
const FEATHER_BLOCKS = 16;

/** composite.wgsl Params: info vec4<u32> + 6 × Layer (2 × vec4). */
export const COMPOSITE_PARAMS_BYTES = 16 + MAX_STACK_LAYERS * 32;
const MASK_PARAMS_BYTES = 32;
const FEATHER_PARAMS_BYTES = 16;

const OUT_CODE = { replace: 0, blend: 1, mask: 2 } as const;
const MASK_SOURCE_CODE = { luma: 1, depth: 2, slot: 3 } as const;

/** The renderer's current resources, re-attached every frame (cheap when nothing changed). */
export interface CompositorEnvironment {
  device: GPUDevice;
  colorFormat: InternalColorFormat;
  readTex: GPUTexture;
  writeTex: GPUTexture;
  /** DPT depth map (catalog binding 4), r32float, canvas-sized. */
  depthTex: GPUTexture;
  scaledW: number;
  scaledH: number;
}

/** Pack one composite op's uniform block (exported for tests). */
export function packCompositeParams(layers: readonly CompositeLayer[]): ArrayBuffer {
  const buf = new ArrayBuffer(COMPOSITE_PARAMS_BYTES);
  const u32 = new Uint32Array(buf);
  const f32 = new Float32Array(buf);
  const count = Math.min(layers.length, MAX_STACK_LAYERS);
  u32[0] = count;
  for (const [i, layer] of layers.slice(0, count).entries()) {
    const base = 4 + i * 8;
    u32[base] = OUT_CODE[layer.output];
    u32[base + 1] = layer.blendIndex;
    u32[base + 2] = layer.mask ? 1 : 0;
    u32[base + 3] = layer.stackLayer;
    f32[base + 4] = layer.opacity;
    f32[base + 5] = layer.key;
    f32[base + 6] = KEY_SOFTNESS;
    f32[base + 7] = 0;
  }
  return buf;
}

/** Pack one mask draw's uniform block (exported for tests). */
export function packMaskParams(layer: CompositeLayer): ArrayBuffer {
  const buf = new ArrayBuffer(MASK_PARAMS_BYTES);
  const u32 = new Uint32Array(buf);
  const mask = layer.mask;
  if (!mask) return buf;
  u32[0] = MASK_SOURCE_CODE[mask.source];
  u32[1] = mask.srcStackLayer;
  u32[2] = mask.invert ? 1 : 0;
  u32[3] = mask.srcIsMatte ? 1 : 0;
  u32[4] = layer.stackLayer;
  return buf;
}

/** Feather radius in pixels at the working height (1.0 → FEATHER_MAX_RADIUS_PX at 1024 px). */
export function featherRadiusPx(feather: number, workingH: number): number {
  return Math.max(0, Math.min(1, feather)) * FEATHER_MAX_RADIUS_PX * (workingH / 1024);
}

function bytesPerTexel(format: InternalColorFormat): number {
  return format === 'rgba32float' ? 16 : 8;
}

export function stackBytes(layers: number, w: number, h: number, format: InternalColorFormat): number {
  // colour layer + r8unorm mask layer per stack layer
  return layers * w * h * (bytesPerTexel(format) + 1);
}

interface StackTextures {
  layers: number;
  layerTex: GPUTexture;
  maskTex: GPUTexture;
  /** Single-layer render views of maskTex, one per stack layer. */
  maskViews: GPUTextureView[];
}

export class LayerCompositor implements FrameCompositor {
  private env: CompositorEnvironment | null = null;
  private stack: StackTextures | null = null;
  private scratch: GPUTexture | null = null;
  private scratchView: GPUTextureView | null = null;
  private refusedLayers = Number.POSITIVE_INFINITY;

  private compositePipeline: GPUComputePipeline | null = null;
  private compositeLayout: GPUBindGroupLayout | null = null;
  private pipelineFormat: InternalColorFormat | null = null;
  private pipelineDevice: GPUDevice | null = null;
  private maskPipeline: GPURenderPipeline | null = null;
  private maskLayout: GPUBindGroupLayout | null = null;
  private featherPipeline: GPURenderPipeline | null = null;
  private featherLayout: GPUBindGroupLayout | null = null;
  private featherSampler: GPUSampler | null = null;

  private compositeParams: GPUBuffer | null = null;
  private maskParams: GPUBuffer | null = null;
  private featherParams: GPUBuffer | null = null;
  private blockAlign = 256;

  private compositeGroup: GPUBindGroup | null = null;
  private compositeGroupKey: unknown[] = [];
  private maskGroup: GPUBindGroup | null = null;
  private maskGroupKey: unknown[] = [];
  private featherFromMask: GPUBindGroup | null = null;
  private featherFromScratch: GPUBindGroup | null = null;

  private compositeBlock = 0;
  private maskBlock = 0;
  private featherBlock = 0;
  private warned = new Set<string>();

  /** Composites encoded since the last `prepare` (diagnostics). */
  lastFrameComposites = 0;

  /** Bind to the renderer's current resources; drops the stack when size / format / device changed. */
  attach(env: CompositorEnvironment): void {
    const prev = this.env;
    this.env = env;
    if (
      prev
      && prev.device === env.device
      && prev.colorFormat === env.colorFormat
      && prev.scaledW === env.scaledW
      && prev.scaledH === env.scaledH
    ) {
      return;
    }
    this.releaseTextures();
    if (prev && prev.device !== env.device) this.releasePipelines();
    this.refusedLayers = Number.POSITIVE_INFINITY;
  }

  /** Stack layers currently allocated (0 when idle). */
  allocatedLayers(): number {
    return this.stack?.layers ?? 0;
  }

  allocatedBytes(): number {
    const env = this.env;
    if (!env || !this.stack) return 0;
    return stackBytes(this.stack.layers, env.scaledW, env.scaledH, env.colorFormat)
      + (this.scratch ? env.scaledW * env.scaledH : 0);
  }

  /** Free the stack (no composite this frame and none expected). */
  releaseTextures(): void {
    this.stack?.layerTex.destroy();
    this.stack?.maskTex.destroy();
    this.stack = null;
    this.scratch?.destroy();
    this.scratch = null;
    this.scratchView = null;
    this.compositeGroup = null;
    this.compositeGroupKey = [];
    this.maskGroup = null;
    this.maskGroupKey = [];
    this.featherFromMask = null;
    this.featherFromScratch = null;
  }

  private releasePipelines(): void {
    this.compositePipeline = null;
    this.compositeLayout = null;
    this.pipelineFormat = null;
    this.pipelineDevice = null;
    this.maskPipeline = null;
    this.maskLayout = null;
    this.featherPipeline = null;
    this.featherLayout = null;
    this.featherSampler = null;
    this.compositeParams?.destroy();
    this.maskParams?.destroy();
    this.featherParams?.destroy();
    this.compositeParams = null;
    this.maskParams = null;
    this.featherParams = null;
  }

  destroy(): void {
    this.releaseTextures();
    this.releasePipelines();
    this.env = null;
  }

  private warnOnce(key: string, message: string): void {
    if (this.warned.has(key)) return;
    this.warned.add(key);
    console.warn(message);
  }

  prepare(stackLayers: number): boolean {
    const env = this.env;
    this.compositeBlock = 0;
    this.maskBlock = 0;
    this.featherBlock = 0;
    this.lastFrameComposites = 0;
    if (!env || stackLayers <= 0) return false;
    if (!this.ensurePipelines(env)) return false;
    return this.ensureStack(env, Math.min(MAX_STACK_LAYERS, stackLayers));
  }

  private ensurePipelines(env: CompositorEnvironment): boolean {
    if (this.compositePipeline && this.pipelineFormat === env.colorFormat && this.pipelineDevice === env.device) {
      return true;
    }
    const { device } = env;
    try {
      if (this.pipelineDevice !== device || !this.maskPipeline) {
        this.blockAlign = Math.max(256, device.limits?.minUniformBufferOffsetAlignment ?? 256);
        const uniformBlock = (size: number) => ({ type: 'uniform' as const, hasDynamicOffset: true, minBindingSize: size });
        this.maskLayout = device.createBindGroupLayout({
          label: 'compositorMaskBGL',
          entries: [
            { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float', viewDimension: '2d-array' } },
            { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float' } },
            { binding: 2, visibility: GPUShaderStage.FRAGMENT, buffer: uniformBlock(MASK_PARAMS_BYTES) },
          ],
        });
        const maskModule = device.createShaderModule({ label: 'compositorMask', code: maskWgsl });
        this.maskPipeline = device.createRenderPipeline({
          label: 'compositorMask',
          layout: device.createPipelineLayout({ bindGroupLayouts: [this.maskLayout] }),
          vertex: { module: maskModule, entryPoint: 'vs' },
          fragment: { module: maskModule, entryPoint: 'fs', targets: [{ format: 'r8unorm' }] },
          primitive: { topology: 'triangle-list' },
        });
        this.featherLayout = device.createBindGroupLayout({
          label: 'compositorFeatherBGL',
          entries: [
            { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float', viewDimension: '2d-array' } },
            { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
            { binding: 2, visibility: GPUShaderStage.FRAGMENT, buffer: uniformBlock(FEATHER_PARAMS_BYTES) },
          ],
        });
        const featherModule = device.createShaderModule({ label: 'compositorFeather', code: featherWgsl });
        this.featherPipeline = device.createRenderPipeline({
          label: 'compositorFeather',
          layout: device.createPipelineLayout({ bindGroupLayouts: [this.featherLayout] }),
          vertex: { module: featherModule, entryPoint: 'vs' },
          fragment: { module: featherModule, entryPoint: 'fs', targets: [{ format: 'r8unorm' }] },
          primitive: { topology: 'triangle-list' },
        });
        this.featherSampler = device.createSampler({
          label: 'compositorFeatherSampler',
          magFilter: 'linear',
          minFilter: 'linear',
          addressModeU: 'clamp-to-edge',
          addressModeV: 'clamp-to-edge',
        });
        const usage = GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST;
        this.compositeParams = device.createBuffer({ label: 'compositeParams', size: COMPOSITE_BLOCKS * this.blockAlign, usage });
        this.maskParams = device.createBuffer({ label: 'compositorMaskParams', size: MASK_BLOCKS * this.blockAlign, usage });
        this.featherParams = device.createBuffer({ label: 'compositorFeatherParams', size: FEATHER_BLOCKS * this.blockAlign, usage });
      }
      this.compositeLayout = device.createBindGroupLayout({
        label: 'compositeBGL',
        entries: [
          { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
          { binding: 1, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float', viewDimension: '2d-array' } },
          { binding: 2, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float', viewDimension: '2d-array' } },
          { binding: 3, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
          { binding: 4, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: env.colorFormat } },
          {
            binding: 5,
            visibility: GPUShaderStage.COMPUTE,
            buffer: { type: 'uniform', hasDynamicOffset: true, minBindingSize: COMPOSITE_PARAMS_BYTES },
          },
        ],
      });
      const module = device.createShaderModule({
        label: 'compositor',
        code: rewriteWgslStorageFormats(compositeWgsl, env.colorFormat),
      });
      this.compositePipeline = device.createComputePipeline({
        label: 'compositor',
        layout: device.createPipelineLayout({ bindGroupLayouts: [this.compositeLayout] }),
        compute: { module, entryPoint: 'main' },
      });
      this.pipelineFormat = env.colorFormat;
      this.pipelineDevice = device;
      this.compositeGroup = null;
      this.compositeGroupKey = [];
      return true;
    } catch (e) {
      this.warnOnce('pipeline', `[WebGPU] compositor pipelines failed — layers render as replace: ${String(e)}`);
      this.releasePipelines();
      return false;
    }
  }

  private ensureStack(env: CompositorEnvironment, layers: number): boolean {
    if (this.stack && this.stack.layers >= layers) return true;
    if (layers >= this.refusedLayers) return false;
    const bytes = stackBytes(layers, env.scaledW, env.scaledH, env.colorFormat);
    if (bytes > COMPOSITOR_STACK_BUDGET_BYTES) {
      this.refusedLayers = layers;
      this.warnOnce(
        `budget:${layers}`,
        `[WebGPU] compositor: ${layers} layers need ${(bytes / 2 ** 20).toFixed(0)} MiB (over budget) — rendering as replace`,
      );
      return false;
    }
    const { device } = env;
    // Compat devices fix the binding view dimension at creation (a one-layer stack is still an array).
    const arrayDim = arrayBindingDescriptor(device);
    this.stack?.layerTex.destroy();
    this.stack?.maskTex.destroy();
    const layerTex = device.createTexture({
      label: 'compositorLayers',
      size: { width: env.scaledW, height: env.scaledH, depthOrArrayLayers: layers },
      format: env.colorFormat,
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      ...arrayDim,
    });
    const maskTex = device.createTexture({
      label: 'compositorMasks',
      size: { width: env.scaledW, height: env.scaledH, depthOrArrayLayers: layers },
      format: 'r8unorm',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT,
      ...arrayDim,
    });
    const maskViews = Array.from({ length: layers }, (_, i) =>
      maskTex.createView({ label: `compositorMask-${i}`, dimension: '2d', baseArrayLayer: i, arrayLayerCount: 1 }),
    );
    this.stack = { layers, layerTex, maskTex, maskViews };
    this.compositeGroup = null;
    this.maskGroup = null;
    this.featherFromMask = null;
    return true;
  }

  private ensureScratch(env: CompositorEnvironment): GPUTextureView | null {
    if (this.scratchView) return this.scratchView;
    this.scratch = env.device.createTexture({
      label: 'compositorFeatherScratch',
      size: { width: env.scaledW, height: env.scaledH, depthOrArrayLayers: 1 },
      format: 'r8unorm',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT,
      ...arrayBindingDescriptor(env.device),
    });
    this.scratchView = this.scratch.createView({ dimension: '2d', baseArrayLayer: 0, arrayLayerCount: 1 });
    this.featherFromScratch = null;
    return this.scratchView;
  }

  encodeCapture(encoder: GPUCommandEncoder, op: CaptureLayerOp): void {
    const env = this.env;
    const stack = this.stack;
    if (!env || !stack || op.stackLayer >= stack.layers) return;
    encoder.copyTextureToTexture(
      { texture: env.writeTex },
      { texture: stack.layerTex, origin: [0, 0, op.stackLayer] },
      [env.scaledW, env.scaledH, 1],
    );
  }

  encodeComposite(encoder: GPUCommandEncoder, op: CompositeOp, profile?: PassProfiler): void {
    const env = this.env;
    const stack = this.stack;
    if (!env || !stack || !this.compositePipeline || !this.compositeParams) return;
    if (op.unresolvedMasks.length > 0) {
      this.warnOnce(
        `unresolved:${op.unresolvedMasks.join(',')}`,
        `[WebGPU] compositor: slot(s) ${op.unresolvedMasks.map((s) => s + 1).join(', ')} mask another slot that has not rendered yet this frame — drawn unmasked`,
      );
    }
    if (this.compositeBlock >= COMPOSITE_BLOCKS) {
      this.warnOnce('blocks', '[WebGPU] compositor: too many composites this frame — extra ones skipped');
      return;
    }
    const layers = op.layers.filter((l) => l.stackLayer < stack.layers);
    for (const layer of layers) {
      if (layer.mask) this.encodeMask(encoder, env, stack, layer, profile);
    }

    const group = this.getCompositeGroup(env, stack);
    if (!group) return;
    const offset = this.compositeBlock++ * this.blockAlign;
    env.device.queue.writeBuffer(this.compositeParams, offset, packCompositeParams(layers));
    const label = op.label;
    const timestampWrites = profile?.(label);
    const pass = encoder.beginComputePass(timestampWrites ? { label, timestampWrites } : { label });
    pass.setPipeline(this.compositePipeline);
    pass.setBindGroup(0, group, [offset]);
    pass.dispatchWorkgroups(Math.ceil(env.scaledW / 16), Math.ceil(env.scaledH / 16), 1);
    pass.end();
    this.lastFrameComposites++;
  }

  private encodeMask(
    encoder: GPUCommandEncoder,
    env: CompositorEnvironment,
    stack: StackTextures,
    layer: CompositeLayer,
    profile?: PassProfiler,
  ): void {
    const mask = layer.mask;
    if (!mask || !this.maskPipeline || !this.maskParams || this.maskBlock >= MASK_BLOCKS) return;
    if (mask.srcStackLayer >= stack.layers) return;
    const target = stack.maskViews[layer.stackLayer];
    const maskGroup = this.getMaskGroup(env, stack);
    if (!target || !maskGroup) return;
    const offset = this.maskBlock++ * this.blockAlign;
    env.device.queue.writeBuffer(this.maskParams, offset, packMaskParams(layer));
    const label = `composite-mask-${layer.slotIndex}`;
    this.renderPass(encoder, label, target, this.maskPipeline, maskGroup, offset, profile);

    const radius = featherRadiusPx(mask.feather, env.scaledH);
    if (radius < 0.5 || !this.featherPipeline || !this.featherParams || this.featherBlock + 2 > FEATHER_BLOCKS) return;
    const scratch = this.ensureScratch(env);
    if (!scratch || !this.scratch) return;
    this.featherFromMask ??= this.featherGroup(env, stack.maskTex, 'compositorFeatherFromMask');
    this.featherFromScratch ??= this.featherGroup(env, this.scratch, 'compositorFeatherFromScratch');
    const fromMask = this.featherFromMask;
    const fromScratch = this.featherFromScratch;
    if (!fromMask || !fromScratch) return;
    const h = this.featherBlock++ * this.blockAlign;
    const v = this.featherBlock++ * this.blockAlign;
    env.device.queue.writeBuffer(this.featherParams, h, new Float32Array([1, 0, radius, layer.stackLayer]));
    env.device.queue.writeBuffer(this.featherParams, v, new Float32Array([0, 1, radius, 0]));
    this.renderPass(encoder, `${label}-feather-x`, scratch, this.featherPipeline, fromMask, h, profile);
    this.renderPass(encoder, `${label}-feather-y`, target, this.featherPipeline, fromScratch, v, profile);
  }

  private renderPass(
    encoder: GPUCommandEncoder,
    label: string,
    target: GPUTextureView,
    pipeline: GPURenderPipeline,
    group: GPUBindGroup,
    offset: number,
    profile?: PassProfiler,
  ): void {
    const timestampWrites = profile?.(label);
    const pass = encoder.beginRenderPass({
      label,
      colorAttachments: [{ view: target, loadOp: 'clear', storeOp: 'store', clearValue: { r: 1, g: 0, b: 0, a: 1 } }],
      ...(timestampWrites ? { timestampWrites } : {}),
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, group, [offset]);
    pass.draw(3);
    pass.end();
  }

  private getCompositeGroup(env: CompositorEnvironment, stack: StackTextures): GPUBindGroup | null {
    const layout = this.compositeLayout;
    const params = this.compositeParams;
    if (!layout || !params) return null;
    const key = [env.readTex, env.writeTex, env.depthTex, stack.layerTex, stack.maskTex, layout];
    if (this.compositeGroup && sameKey(key, this.compositeGroupKey)) return this.compositeGroup;
    this.compositeGroup = env.device.createBindGroup({
      label: 'compositeBG',
      layout,
      entries: [
        { binding: 0, resource: env.readTex.createView() },
        { binding: 1, resource: stack.layerTex.createView({ dimension: '2d-array' }) },
        { binding: 2, resource: stack.maskTex.createView({ dimension: '2d-array' }) },
        { binding: 3, resource: env.depthTex.createView() },
        { binding: 4, resource: env.writeTex.createView() },
        { binding: 5, resource: { buffer: params, offset: 0, size: COMPOSITE_PARAMS_BYTES } },
      ],
    });
    this.compositeGroupKey = key;
    return this.compositeGroup;
  }

  private getMaskGroup(env: CompositorEnvironment, stack: StackTextures): GPUBindGroup | null {
    const layout = this.maskLayout;
    const params = this.maskParams;
    if (!layout || !params) return null;
    const key = [env.depthTex, stack.layerTex, layout];
    if (this.maskGroup && sameKey(key, this.maskGroupKey)) return this.maskGroup;
    this.maskGroup = env.device.createBindGroup({
      label: 'compositorMaskBG',
      layout,
      entries: [
        { binding: 0, resource: stack.layerTex.createView({ dimension: '2d-array' }) },
        { binding: 1, resource: env.depthTex.createView() },
        { binding: 2, resource: { buffer: params, offset: 0, size: MASK_PARAMS_BYTES } },
      ],
    });
    this.maskGroupKey = key;
    return this.maskGroup;
  }

  private featherGroup(env: CompositorEnvironment, src: GPUTexture, label: string): GPUBindGroup | null {
    const layout = this.featherLayout;
    const sampler = this.featherSampler;
    const params = this.featherParams;
    if (!layout || !sampler || !params) return null;
    return env.device.createBindGroup({
      label,
      layout,
      entries: [
        { binding: 0, resource: src.createView({ dimension: '2d-array' }) },
        { binding: 1, resource: sampler },
        { binding: 2, resource: { buffer: params, offset: 0, size: FEATHER_PARAMS_BYTES } },
      ],
    });
  }
}

function sameKey(a: readonly unknown[], b: readonly unknown[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}
