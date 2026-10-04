/**
 * present.ts
 *
 * Input scaling, canvas acquisition, final blit, and frame submission.
 * Mirrors the presentation portion of wasm_renderer/frame.cpp.
 */

import { createBlitBindGroup } from './pipeline';
import type { WebGPUFrameState } from './frameState';
import {
  encodeResolveAndCopy,
  pickPresentTimestampWrites,
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

  /** Seed readTex from the source, scaling through a render pass when required. */
  encodeInputCopy(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (needsScaledInputCopy(state)) {
      const scalePass = encoder.beginRenderPass({
        label: 'scalePass',
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

    const timing = state.timestampRuntime;
    const timestampWrites =
      timing.supportsTimestampQuery && timing.querySet
        ? pickPresentTimestampWrites(timing.tracker, timing.querySet)
        : undefined;
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
      selectPresentPipeline(
        state.inputSource,
        state.blitPipeline,
        state.generativeBlitPipeline,
      ),
    );
    pass.setBindGroup(0, state.blitBindGroup);
    pass.draw(3);
    pass.end();
    return true;
  }

  /** Submit a fully encoded frame, including timestamp resolve/readback bookkeeping. */
  submitFrame(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (!state.device) return;
    const resolveSlot = encodeResolveAndCopy(encoder, state.timestampRuntime);
    state.device.queue.submit([encoder.finish()]);
    if (resolveSlot !== null) {
      scheduleTimestampReadback(state.timestampRuntime, resolveSlot);
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
