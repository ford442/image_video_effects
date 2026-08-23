/**
 * frame.ts
 *
 * Thin frame lifecycle facade: media refresh, uniforms, history ring, timing,
 * and delegation to slotDispatch.ts + present.ts. Mirrors wasm_renderer/frame.cpp.
 */

import { GPUTimings } from '../Renderer';
import {
  createUniformBufferView,
  UniformBufferView,
  MAX_RIPPLES,
} from '../UniformBuffer';
import { writeExtraBuffer } from './audioDepth';
import type { WebGPUFrameState } from './frameState';
import { WebGPUPresenter } from './present';
import {
  buildFrameSlotDispatchPlan,
  dispatchFrameSlots,
} from './slotDispatch';
import {
  AUDIO_FFT_BINS,
  HISTORY_DEPTH,
  WG_SIZE_X,
  WG_SIZE_Y,
} from './webgpuConstants';
import { buildGPUTimings } from './WebGPUTiming';

export {
  createFrameState,
  createRendererFrameHost,
} from './frameState';
export type {
  RendererFrameDeps,
  WebGPUFrameHost,
  WebGPUFrameState,
} from './frameState';

export class WebGPUFrameRenderer {
  private uniformView: UniformBufferView = createUniformBufferView();
  private presenter = new WebGPUPresenter();

  startRenderLoop(state: WebGPUFrameState): void {
    const loop = () => {
      if (!state.initialized) return;
      state.currentTime = performance.now() / 1000 - state.startTime;
      this.renderFrame(state);
      state.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  stopRenderLoop(state: WebGPUFrameState): void {
    if (state.animationId !== null) {
      cancelAnimationFrame(state.animationId);
      state.animationId = null;
    }
  }

  getGPUTimings(state: WebGPUFrameState): GPUTimings {
    const rt = state.timestampRuntime;
    return buildGPUTimings(
      state.gpuTimings,
      rt.supportsTimestampQuery,
      rt.hasRealGpuTimings,
    );
  }

  renderFrame(state: WebGPUFrameState): void {
    if (!state.device || !state.context || !state.initialized) return;

    this.refreshVideo(state);

    const slotPlan = buildFrameSlotDispatchPlan(state);
    if (slotPlan.enabledCount === 0) {
      state.blitReadTex = state.readTex;
      this.presenter.presentWithoutEffects(state);
      return;
    }

    this.writeUniforms(state);

    const encoder = state.device.createCommandEncoder({ label: 'frame' });
    this.presenter.encodeInputCopy(state, encoder);
    state.encodePreFxChores?.(encoder);
    const dispatch = dispatchFrameSlots(state, encoder, slotPlan);

    if (slotPlan.anyUsesHistory) {
      encoder.copyTextureToTexture(
        { texture: state.blitReadTex },
        { texture: state.historyTex, origin: [0, 0, state.audioDepth.historyHead] },
        [state.scaledW, state.scaledH, 1],
      );
    }

    this.presenter.updateBlitBindGroup(state);
    this.presenter.encodePresent(state, encoder);
    this.presenter.submitFrame(state, encoder);
    state.afterFrameSubmitChores?.();

    if (!state.timestampRuntime.hasRealGpuTimings) {
      state.timestampRuntime.gpuTimings.parallelTime = dispatch.wallParallel;
      state.timestampRuntime.gpuTimings.chainedTime = dispatch.wallChained;
      state.timestampRuntime.gpuTimings.totalTime = performance.now() - dispatch.wallStart;
    }

    if (slotPlan.anyUsesHistory) {
      state.audioDepth.historyHead = (state.audioDepth.historyHead + 1) % HISTORY_DEPTH;
    }

    this.updateFPS(state);
  }

  private refreshVideo(state: WebGPUFrameState): void {
    if (state.video && !state.video.paused && state.video.readyState >= 2) {
      state.updateVideoFrame();
      return;
    }
    if (
      state.video &&
      state.video.readyState >= 2 &&
      state.frameCount % 60 === 0 &&
      process.env.NODE_ENV === 'development'
    ) {
      console.log('[WebGPURenderer] Video state:', {
        paused: state.video.paused,
        readyState: state.video.readyState,
        videoWidth: state.video.videoWidth,
        videoHeight: state.video.videoHeight,
        src: state.video.src?.substring(0, 100),
        error: state.video.error?.code,
      });
    }
  }

  private writeUniforms(state: WebGPUFrameState): void {
    if (!state.device) return;

    const uniforms = this.uniformView;
    uniforms.setConfig(
      state.currentTime,
      state.ripples.length,
      state.scaledW,
      state.scaledH,
    );
    uniforms.setZoomConfig(
      state.currentTime,
      state.mouseX,
      state.mouseYShader,
      state.mouseDown ? 1 : 0,
    );
    uniforms.setZoomParams(
      state.zoomParams[0],
      state.zoomParams[1],
      state.zoomParams[2],
      state.zoomParams[3],
    );

    for (let i = 0; i < MAX_RIPPLES; i++) {
      if (i < state.ripples.length) {
        const ripple = state.ripples[i];
        uniforms.setRipple(i, ripple.x, ripple.y, ripple.startTime);
      } else {
        uniforms.clearRipple(i);
      }
    }

    state.device.queue.writeBuffer(state.uniformBuf, 0, uniforms.data);
    writeExtraBuffer(state.device, state.extraBuf, state.audioDepth);
  }

  private updateFPS(state: WebGPUFrameState): void {
    state.frameCount++;
    const now = performance.now() / 1000;
    if (now - state.lastFPSTime < 1.0) return;

    state.fps = state.frameCount / (now - state.lastFPSTime);
    state.frameCount = 0;
    state.lastFPSTime = now;
    state.adaptQualityIfNeeded();
  }
}

export function computeScaledDimensions(
  canvasW: number,
  canvasH: number,
  resolutionScale: number,
): { scaledW: number; scaledH: number } {
  const scaledW = Math.ceil((canvasW * resolutionScale) / WG_SIZE_X) * WG_SIZE_X;
  const scaledH = Math.ceil((canvasH * resolutionScale) / WG_SIZE_Y) * WG_SIZE_Y;
  return { scaledW, scaledH };
}

export function createDefaultAudioFreqBins(): Float32Array {
  return new Float32Array(AUDIO_FFT_BINS);
}
