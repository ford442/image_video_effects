/**
 * present.ts
 *
 * Input scaling, canvas acquisition, final blit, and frame submission.
 * Mirrors the presentation portion of wasm_renderer/frame.cpp.
 */

import { createBlitBindGroup } from './pipeline';
import type { WebGPUFrameState } from './frameState';
import { PresentHold } from './presentHold';
import {
  encodeResolveAndCopy,
  profilePass,
  scheduleTimestampReadback,
} from './WebGPUTiming';

export interface BlitBindGroupSnapshot {
  hasBindGroup: boolean;
  readTextureMatches: boolean;
  scaledWidthMatches: boolean;
  scaledHeightMatches: boolean;
}

/** Pure cache gate used before rebuilding the sampled-texture bind group. */
export function needsBlitBindGroupRefresh(snapshot: BlitBindGroupSnapshot): boolean {
  return !(
    snapshot.hasBindGroup &&
    snapshot.readTextureMatches &&
    snapshot.scaledWidthMatches &&
    snapshot.scaledHeightMatches
  );
}

/** Pure present-pipeline selector; generative output keeps its Y-up orientation. */
export function selectPresentPipeline<T>(
  inputSource: WebGPUFrameState['inputSource'],
  standardPipeline: T,
  generativePipeline: T,
): T {
  return inputSource === 'generative' ? generativePipeline : standardPipeline;
}

/**
 * readTex is smaller than the canvas-sized sourceTex whenever the resolution
 * scale is below 1 *or* the working size is capped (1024 on every non-discrete
 * adapter while the canvas is 2048). A plain copy would then overrun readTex,
 * invalidating the whole frame command buffer, so resample instead.
 */
export function needsScaledInputCopy(
  state: Pick<WebGPUFrameState, 'resolutionScale' | 'scaledW' | 'scaledH' | 'canvasW' | 'canvasH'>,
): boolean {
  return state.resolutionScale < 1.0 || state.scaledW < state.canvasW || state.scaledH < state.canvasH;
}

export class WebGPUPresenter {
  private scaleBindGroup: GPUBindGroup | null = null;
  private scaleBindGroupTex: GPUTexture | null = null;
  /** Live cue crossfade: the frozen previous picture mixed in by the present pass. */
  private readonly hold = new PresentHold();
  /** What the last present drew (a cue's hold is a copy of exactly that); null before the first. */
  private presented: { device: GPUDevice; generative: boolean } | null = null;

  /** Seed readTex from the source, scaling through a render pass when required. */
  encodeInputCopy(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (needsScaledInputCopy(state)) {
      const scaleWrites = profilePass(state.timestampRuntime, { kind: 'input', label: 'scalePass' });
      const scalePass = encoder.beginRenderPass({
        label: 'scalePass',
        ...(scaleWrites ? { timestampWrites: scaleWrites } : {}),
        colorAttachments: [
          {
            view: state.readTex.createView(),
            loadOp: 'clear',
            storeOp: 'store',
            clearValue: { r: 0, g: 0, b: 0, a: 1 },
          },
        ],
      });
      scalePass.setPipeline(state.scaleCopyPipeline);
      scalePass.setBindGroup(0, this.getScaleBindGroup(state));
      scalePass.draw(3);
      scalePass.end();
      return;
    }

    encoder.copyTextureToTexture(
      { texture: state.sourceTex },
      { texture: state.readTex },
      [state.canvasW, state.canvasH, 1],
    );
  }

  /** Acquire the current canvas texture and encode the final full-screen blit. */
  encodePresent(state: WebGPUFrameState, encoder: GPUCommandEncoder): boolean {
    if (!state.context) return false;

    let currentTexture: GPUTexture;
    try {
      currentTexture = state.context.getCurrentTexture();
    } catch {
      return false;
    }
    if (!currentTexture) return false;

    // The mix is applied after the pipeline choice below: a cue changes what is blended in,
    // never which orientation the live frame uses.
    const mix = this.hold.presentBinding(state, currentTexture);
    const timestampWrites = profilePass(state.timestampRuntime, { kind: 'present', label: 'present' });
    const pass = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: currentTexture.createView(),
          loadOp: 'clear',
          storeOp: 'store',
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
        },
      ],
      ...(timestampWrites ? { timestampWrites } : {}),
    });
    pass.setPipeline(
      mix
        ? selectPresentPipeline(state.inputSource, mix.standard, mix.generative)
        : selectPresentPipeline(
            state.inputSource,
            state.blitPipeline,
            state.generativeBlitPipeline,
          ),
    );
    pass.setBindGroup(0, state.blitBindGroup);
    if (mix) pass.setBindGroup(1, mix.bindGroup);
    pass.draw(3);
    pass.end();
    if (state.device) {
      this.presented = { device: state.device, generative: state.inputSource === 'generative' };
    }
    return true;
  }

  /**
   * Start a cue crossfade: dissolve from the last presented picture into whatever the
   * frames after this call render. False when the picture simply cuts (duration 0,
   * nothing presented yet, or no hold could be created).
   */
  startCrossfade(state: WebGPUFrameState, durationMs: number): boolean {
    const hasPresented = !!state.device && this.presented?.device === state.device;
    return this.hold.start(state, durationMs, hasPresented);
  }

  /** First command of a frame: copy the last presented picture into a pending cue's hold. */
  encodeHoldCapture(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (!this.hold.hasPending) return;
    this.hold.encodeCapture(state, encoder, this.presented?.generative ?? false);
  }

  /** Free the hold and forget what was presented (renderer teardown). */
  releaseHold(): void {
    this.hold.release();
    this.presented = null;
  }

  /** Submit a fully encoded frame, including timestamp resolve/readback bookkeeping. */
  submitFrame(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (!state.device) return;
    const readback = encodeResolveAndCopy(encoder, state.timestampRuntime);
    state.device.queue.submit([encoder.finish()]);
    this.hold.afterSubmit();
    if (readback !== null) {
      scheduleTimestampReadback(state.timestampRuntime, readback);
    }
  }

  updateBlitBindGroup(state: WebGPUFrameState): void {
    if (!state.device) return;
    if (!needsBlitBindGroupRefresh({
      hasBindGroup: !!state.blitBindGroup,
      readTextureMatches: state.blitReadTex === state.lastBlitReadTex,
      scaledWidthMatches: state.scaledW === state.lastBlitScaledW,
      scaledHeightMatches: state.scaledH === state.lastBlitScaledH,
    })) {
      return;
    }

    state.blitBindGroup = createBlitBindGroup(
      state.device,
      state.blitBindGroupLayout,
      state.blitReadTex,
    );
    state.lastBlitReadTex = state.blitReadTex;
    state.lastBlitScaledW = state.scaledW;
    state.lastBlitScaledH = state.scaledH;
  }

  private getScaleBindGroup(state: WebGPUFrameState): GPUBindGroup {
    if (!this.scaleBindGroup || this.scaleBindGroupTex !== state.sourceTex) {
      this.scaleBindGroup = createBlitBindGroup(
        state.device!,
        state.blitBindGroupLayout,
        state.sourceTex,
      );
      this.scaleBindGroupTex = state.sourceTex;
    }
    return this.scaleBindGroup;
  }
}
