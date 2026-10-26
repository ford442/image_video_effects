/**
 * presentHold.ts
 *
 * Live cue crossfade: one frozen picture and one linear mix, both in the present
 * pass. The history ring (at most eight frames, docs/BINDING_CONTRACT.md) cannot
 * hold the outgoing picture for a two-second fade, so a cue copies the last
 * presented color into a single canvas-sized `rgba8unorm` texture and the present
 * pass mixes it over the live frame: mix 1 shows the hold, mix 0 the new frame.
 * Recording grabs the presented frame, so it captures the mix.
 *
 * What this is not:
 * - Not a catalog shader and not part of the compute `Uniforms` struct. The mix
 *   factor lives in a 16-byte uniform on the blit pipeline only (`@group(1)`).
 * - Not a second live stack. One frozen image, no parallel render.
 * - Not per frame work. One copy per cue; a cue during a cue replaces the hold
 *   with the current present (the old hold under the live frame, at the weight it
 *   was last presented) and restarts the ramp. There is no queue of holds.
 *
 * Allocation: the texture exists only while a fade runs. If it cannot be created
 * the cue is dropped and the picture cuts, exactly like today: no retry, and no
 * drop of the working resolution (the out-of-memory error is taken by this
 * module's own error scope, so the renderer's OOM handler never sees it). WebGPU
 * reports that error asynchronously, so the capture of the first frame is encoded
 * optimistically; if the verdict is a failure the ramp is cancelled and the frame
 * loop keeps running (a frame whose command buffer already used the invalid
 * texture is dropped, once).
 */

import { crossfadeMix } from '../../utils/transitionMath';
import {
  BLIT_MIX_WGSL,
  BLIT_WGSL,
  GENERATIVE_BLIT_MIX_WGSL,
  GENERATIVE_BLIT_WGSL,
} from '../ShaderTemplates';
import type { WebGPUFrameState } from './frameState';
import { createBlitBindGroup } from './pipeline';
import {
  describeScopeFailure,
  scopeFailed,
  withOutOfMemoryScope,
  withValidationScope,
} from './validationScope';

export const HOLD_FORMAT: GPUTextureFormat = 'rgba8unorm';
/** One `vec4f`-sized block: `[mix, pad, pad, pad]`. */
const MIX_UNIFORM_BYTES = 16;
const DEFAULT_CANVAS_FORMAT: GPUTextureFormat = 'bgra8unorm';

interface HoldSlot {
  texture: GPUTexture;
  uniformBuf: GPUBuffer;
  /** `@group(1)` of the mix pipelines: the hold and its mix uniform. */
  bindGroup: GPUBindGroup;
  width: number;
  height: number;
  /** False once the allocation scope reported an error: never bound again. */
  valid: boolean;
  retired: boolean;
}

interface PendingCue {
  durationMs: number;
  slot: HoldSlot;
  /** The hold still on screen when this cue started, or null. */
  replaces: HoldSlot | null;
}

interface Ramp {
  slot: HoldSlot;
  startMs: number;
  durationMs: number;
}

/** What `encodePresent` needs to mix the hold into this frame. */
export interface PresentMixBinding {
  standard: GPURenderPipeline;
  generative: GPURenderPipeline;
  /** Set as bind group 1; group 0 stays the usual blit bind group. */
  bindGroup: GPUBindGroup;
  mix: number;
}

type PipelineKind = 'blit' | 'mix';

export class PresentHold {
  private device: GPUDevice | null = null;
  private holdLayout: GPUBindGroupLayout | null = null;
  private readonly pipelines = new Map<string, GPURenderPipeline>();
  private pending: PendingCue | null = null;
  private ramp: Ramp | null = null;
  /** Slots to destroy once the frame that may still reference them has been submitted. */
  private readonly retired: HoldSlot[] = [];
  private readonly mixScratch = new Float32Array(MIX_UNIFORM_BYTES / 4);

  constructor(private readonly clock: () => number = () => performance.now()) {}

  /** A cue was requested and its capture has not been encoded yet. */
  get hasPending(): boolean {
    return this.pending !== null;
  }

  /** A fade is running (or about to start). */
  get active(): boolean {
    return this.pending !== null || this.ramp !== null;
  }

  /**
   * Start a cue. `hasPresented` says whether a picture has been presented yet
   * (nothing to dissolve from otherwise). Returns false when the picture will
   * simply cut: duration 0, nothing presented, or no hold could be created.
   */
  start(state: WebGPUFrameState, durationMs: number, hasPresented: boolean): boolean {
    const device = state.device;
    if (!device) return false;
    this.adoptDevice(device);

    // A duration of 0 is today's hard cut — and it ends a fade that is still running.
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      this.cancel();
      return false;
    }
    if (!hasPresented) return false;

    const slot = this.allocate(device, state.canvasW, state.canvasH);
    if (!slot) return false;

    // Two cues before one frame: the first never captured anything, drop its texture.
    if (this.pending) this.retire(this.pending.slot);
    this.pending = { durationMs, slot, replaces: this.ramp?.slot ?? null };
    return true;
  }

  /**
   * First thing in the frame encoder of the cue's frame: copy what the last present
   * drew into the new hold. `state.blitReadTex` still is that texture here, because
   * this frame's compute has not run yet. `generative` is the orientation the last
   * present used, so the hold is exactly what was on the canvas.
   */
  encodeCapture(state: WebGPUFrameState, encoder: GPUCommandEncoder, generative: boolean): void {
    const cue = this.pending;
    if (!cue) return;
    this.pending = null;

    const device = state.device;
    const source = state.blitReadTex;
    if (
      !device
      || !source
      || !cue.slot.valid
      || cue.slot.width !== state.canvasW
      || cue.slot.height !== state.canvasH
    ) {
      this.retire(cue.slot);
      this.dropRamp();
      return;
    }

    try {
      const old = cue.replaces && cue.replaces.valid ? cue.replaces : null;
      const pipeline = this.pipeline(device, state.blitBindGroupLayout, old ? 'mix' : 'blit', generative, HOLD_FORMAT);
      const pass = encoder.beginRenderPass({
        label: 'crossfadeCapture',
        colorAttachments: [
          {
            view: cue.slot.texture.createView(),
            loadOp: 'clear',
            storeOp: 'store',
            clearValue: { r: 0, g: 0, b: 0, a: 1 },
          },
        ],
      });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, createBlitBindGroup(device, state.blitBindGroupLayout, source));
      // A cue during a cue: the old hold under the live frame, at the weight its
      // uniform still holds from the last present.
      if (old) pass.setBindGroup(1, old.bindGroup);
      pass.draw(3);
      pass.end();
    } catch (e) {
      console.warn('[WebGPU] crossfade capture failed — cutting:', e);
      this.retire(cue.slot);
      this.dropRamp();
      return;
    }

    if (cue.replaces) this.retire(cue.replaces);
    this.ramp = { slot: cue.slot, startMs: this.clock(), durationMs: cue.durationMs };
  }

  /**
   * The mix pipelines and hold bind group for this frame's present, or null when
   * the frame presents as usual (no fade, fade over, or the hold no longer fits).
   * Writes this frame's mix; the ramp is the orchestrator's eased progress.
   */
  presentBinding(state: WebGPUFrameState, target: GPUTexture): PresentMixBinding | null {
    const ramp = this.ramp;
    const device = state.device;
    if (!ramp || !device) return null;
    const slot = ramp.slot;

    // A hold that no longer matches the canvas cannot be mixed pixel for pixel: cut.
    if (!slot.valid || target.width !== slot.width || target.height !== slot.height) {
      this.dropRamp();
      return null;
    }
    const progress = (this.clock() - ramp.startMs) / ramp.durationMs;
    if (progress >= 1) {
      this.dropRamp();
      return null;
    }

    const mix = crossfadeMix(progress);
    try {
      const format = target.format ?? DEFAULT_CANVAS_FORMAT;
      this.mixScratch[0] = mix;
      device.queue.writeBuffer(slot.uniformBuf, 0, this.mixScratch);
      return {
        standard: this.pipeline(device, state.blitBindGroupLayout, 'mix', false, format),
        generative: this.pipeline(device, state.blitBindGroupLayout, 'mix', true, format),
        bindGroup: slot.bindGroup,
        mix,
      };
    } catch (e) {
      console.warn('[WebGPU] crossfade present failed — cutting:', e);
      this.dropRamp();
      return null;
    }
  }

  /** After `queue.submit`: nothing in flight can reference a retired hold any more. */
  afterSubmit(): void {
    for (const slot of this.retired.splice(0)) this.destroySlot(slot);
  }

  /** Drop every cue and resource (renderer teardown, new device). */
  release(): void {
    this.cancel();
    this.afterSubmit();
    this.pipelines.clear();
    this.holdLayout = null;
    this.device = null;
  }

  private cancel(): void {
    if (this.pending) this.retire(this.pending.slot);
    this.pending = null;
    this.dropRamp();
  }

  private dropRamp(): void {
    if (this.ramp) this.retire(this.ramp.slot);
    this.ramp = null;
  }

  private retire(slot: HoldSlot): void {
    if (slot.retired) return;
    slot.retired = true;
    this.retired.push(slot);
  }

  private destroySlot(slot: HoldSlot): void {
    try {
      slot.texture.destroy();
      slot.uniformBuf.destroy();
    } catch {
      /* the device is gone; nothing left to free */
    }
  }

  /** Pipelines, layouts and holds belong to one device; a new device starts clean. */
  private adoptDevice(device: GPUDevice): void {
    if (this.device === device) return;
    this.release();
    this.device = device;
  }

  private getHoldLayout(device: GPUDevice): GPUBindGroupLayout {
    if (!this.holdLayout) {
      this.holdLayout = device.createBindGroupLayout({
        label: 'crossfadeHoldBGL',
        entries: [
          { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float' } },
          { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        ],
      });
    }
    return this.holdLayout;
  }

  /**
   * One pipeline per (kind, orientation, target format), created on first use so a
   * session that never fades never builds them. `blit` is the ordinary blit drawn
   * into the hold; `mix` adds the hold as group 1.
   */
  private pipeline(
    device: GPUDevice,
    blitLayout: GPUBindGroupLayout,
    kind: PipelineKind,
    generative: boolean,
    format: GPUTextureFormat,
  ): GPURenderPipeline {
    const key = `${kind}|${generative ? 'y-up' : 'standard'}|${format}`;
    const cached = this.pipelines.get(key);
    if (cached) return cached;

    const code = kind === 'mix'
      ? (generative ? GENERATIVE_BLIT_MIX_WGSL : BLIT_MIX_WGSL)
      : (generative ? GENERATIVE_BLIT_WGSL : BLIT_WGSL);
    const module = device.createShaderModule({ label: `crossfade-${kind}-${generative ? 'y-up' : 'standard'}`, code });
    const pipeline = device.createRenderPipeline({
      label: `crossfade-${kind}-${generative ? 'y-up' : 'standard'}-${format}`,
      layout: device.createPipelineLayout({
        bindGroupLayouts: kind === 'mix' ? [blitLayout, this.getHoldLayout(device)] : [blitLayout],
      }),
      vertex: { module, entryPoint: 'vs' },
      fragment: { module, entryPoint: 'fs', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
    });
    this.pipelines.set(key, pipeline);
    return pipeline;
  }

  /**
   * The hold texture, its mix uniform and the group-1 bind group, created inside
   * out-of-memory and validation scopes. The slot is returned at once (the scopes'
   * verdict arrives later); null only when creation threw synchronously.
   */
  private allocate(device: GPUDevice, width: number, height: number): HoldSlot | null {
    if (width < 1 || height < 1) return null;
    const box: { slot: HoldSlot | null } = { slot: null };
    const layout = this.getHoldLayout(device);
    const verdict = withOutOfMemoryScope(device, () =>
      withValidationScope(device, () => {
        const texture = device.createTexture({
          label: 'crossfadeHold',
          size: [width, height, 1],
          format: HOLD_FORMAT,
          usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
        });
        const uniformBuf = device.createBuffer({
          label: 'crossfadeMix',
          size: MIX_UNIFORM_BYTES,
          usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        // The cue starts on the hold: the first present shows mix 1.
        this.mixScratch[0] = 1;
        device.queue.writeBuffer(uniformBuf, 0, this.mixScratch);
        const bindGroup = device.createBindGroup({
          label: 'crossfadeHoldBG',
          layout,
          entries: [
            { binding: 0, resource: texture.createView() },
            { binding: 1, resource: { buffer: uniformBuf } },
          ],
        });
        box.slot = { texture, uniformBuf, bindGroup, width, height, valid: true, retired: false };
        return box.slot;
      }),
    );

    const slot = box.slot;
    void verdict.then((outer) => {
      const inner = outer.value;
      if (!slot) return;
      if (scopeFailed(outer) || !inner || scopeFailed(inner)) {
        this.fail(slot, describeScopeFailure(outer) ?? (inner ? describeScopeFailure(inner) : null) ?? 'allocation failed');
      }
    });
    if (!slot) {
      console.warn('[WebGPU] crossfade hold could not be created — cutting');
    }
    return slot;
  }

  /** The allocation verdict was a failure: cut once, keep rendering. */
  private fail(slot: HoldSlot, reason: string): void {
    console.warn(`[WebGPU] crossfade hold allocation failed (${reason}) — cutting`);
    slot.valid = false;
    if (this.pending?.slot === slot) this.pending = null;
    if (this.ramp?.slot === slot) this.ramp = null;
    this.retire(slot);
  }
}
