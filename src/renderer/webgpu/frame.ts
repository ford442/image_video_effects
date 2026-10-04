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
import { writeExtraBuffer, writePlasmaBuffer } from './audioDepth';
import type { WebGPUFrameState } from './frameState';
import { WebGPUPresenter } from './present';
import {
  buildFrameSlotDispatchPlan,
  dispatchFrameSlots,
} from './slotDispatch';
import {
  AUDIO_FFT_BINS,
  WG_SIZE_X,
  WG_SIZE_Y,
} from './webgpuConstants';
import { buildGPUTimings } from './WebGPUTiming';
import { FrameStats, FrameStatsTracker } from './deviceCounters';

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
  /** Staging copy of each enabled slot's zoom_params (16 bytes per slot). */
  private slotParamsBuf: GPUBuffer | null = null;
  private slotParamsDevice: GPUDevice | null = null;
  private slotParamsCapacity = 0;
  private readonly statsTracker = new FrameStatsTracker();

  startRenderLoop(state: WebGPUFrameState): void {
    const loop = () => {
      if (!state.initialized) return;
      state.currentTime = performance.now() / 1000 - state.startTime;
      this.renderFrame(state);
      state.animationId = scheduleFrame(loop);
    };
    loop();
  }

  stopRenderLoop(state: WebGPUFrameState): void {
    if (state.animationId !== null) {
      cancelFrame(state.animationId);
      state.animationId = null;
    }
  }

  getGPUTimings(state: WebGPUFrameState): GPUTimings {
    const rt = state.timestampRuntime;
    return buildGPUTimings(
      state.gpuTimings,
      rt.supportsTimestampQuery,
      rt.hasRealGpuTimings,
      rt.passTimings,
    );
  }

  /**
   * Upload per-slot zoom_params and return a hook that copies a slot's params
   * into uniformBuf (bytes 32-47) before its pass. Copies are ordered within
   * the encoder, so each slot sees its own sliders (mirrors C++ WriteSlotParams).
   */
  private prepareSlotParams(
    state: WebGPUFrameState,
    slots: WebGPUFrameState['slots'],
  ): ((encoder: GPUCommandEncoder, slot: WebGPUFrameState['slots'][number]) => void) | undefined {
    const device = state.device;
    if (!device || !state.uniformBuf) return undefined;
    const withParams = slots.filter((slot) => slot.params && slot.params.length >= 4);
    if (withParams.length === 0) return undefined;

    if (!this.slotParamsBuf || this.slotParamsDevice !== device || this.slotParamsCapacity < withParams.length) {
      this.slotParamsBuf?.destroy();
      this.slotParamsCapacity = Math.max(withParams.length, state.slots.length);
      this.slotParamsBuf = device.createBuffer({
        label: 'slotParamsBuf',
        size: this.slotParamsCapacity * 16,
        usage: GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
      });
      this.slotParamsDevice = device;
    }

    const data = new Float32Array(withParams.length * 4);
    const offsets = new Map<WebGPUFrameState['slots'][number], number>();
    withParams.forEach((slot, i) => {
      data.set(slot.params!.slice(0, 4), i * 4);
      offsets.set(slot, i * 16);
    });
    device.queue.writeBuffer(this.slotParamsBuf, 0, data);

    const src = this.slotParamsBuf;
    const dst = state.uniformBuf;
    return (encoder, slot) => {
      const offset = offsets.get(slot);
      if (offset === undefined) return;
      encoder.copyBufferToBuffer(src, offset, dst, 32, 16);
    };
  }

  /** Submits / bind groups per frame, read from the instrumented device. */
  getFrameStats(): FrameStats {
    return { ...this.statsTracker.stats };
  }

  /**
   * Encode and submit one frame. Every GPU command of a steady-state frame —
   * video ingest, input copy, chores, all slots / graph passes, feedback,
   * history, present, chore readback and timestamp resolve — goes into a
   * single encoder and a single queue.submit (#1314 WP-3).
   */
  renderFrame(state: WebGPUFrameState): void {
    if (!state.device || !state.context || !state.initialized) return;

    this.statsTracker.onFrameStart(state.device);
    state.beforeFrame?.();
    state.timestampRuntime.frame.reset();

    const encoder = state.device.createCommandEncoder({ label: 'frame' });
    this.encodeVideoIngest(state, encoder);

    const slotPlan = buildFrameSlotDispatchPlan(state);
    if (slotPlan.enabledCount === 0) {
      // No effects: still refresh readTex from the (possibly video) source.
      this.presenter.encodeInputCopy(state, encoder);
      state.blitReadTex = state.readTex;
      this.presenter.updateBlitBindGroup(state);
      this.presenter.encodePresent(state, encoder);
      this.presenter.submitFrame(state, encoder);
      state.afterFrameSubmit?.();
      this.updateFPS(state);
      return;
    }

    this.writeUniforms(state);

    this.presenter.encodeInputCopy(state, encoder);
    state.encodePreFxChores?.(encoder);
    const dispatch = dispatchFrameSlots(
      state,
      encoder,
      slotPlan,
      this.prepareSlotParams(state, [...slotPlan.parallel, ...slotPlan.chained].map((p) => p.slot)),
    );

    const historyLayers = state.historyLayers;
    const useHistoryRing = slotPlan.anyUsesHistory && historyLayers > 1;
    if (useHistoryRing) {
      encoder.copyTextureToTexture(
        { texture: state.blitReadTex },
        { texture: state.historyTex, origin: [0, 0, state.audioDepth.historyHead] },
        [state.scaledW, state.scaledH, 1],
      );
    }

    this.presenter.updateBlitBindGroup(state);
    this.presenter.encodePresent(state, encoder);
    state.encodePostFxChores?.(encoder);
    this.presenter.submitFrame(state, encoder);
    state.afterFrameSubmit?.();
    state.afterFrameSubmitChores?.();

    if (!state.timestampRuntime.hasRealGpuTimings) {
      state.timestampRuntime.gpuTimings.parallelTime = dispatch.wallParallel;
      state.timestampRuntime.gpuTimings.chainedTime = dispatch.wallChained;
      state.timestampRuntime.gpuTimings.totalTime = performance.now() - dispatch.wallStart;
    }

    if (useHistoryRing) {
      state.audioDepth.historyHead = (state.audioDepth.historyHead + 1) % historyLayers;
    }

    this.updateFPS(state);
  }

  /** The renderer decides (playing <video>, VideoFrame pump, or worker transfers). */
  private encodeVideoIngest(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    state.encodeVideoFrame(encoder);
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
    writePlasmaBuffer(state.device, state.plasmaBuf, state.audioDepth);
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

// Dedicated workers get requestAnimationFrame in Chromium (paced to the
// OffscreenCanvas' display); fall back to a 60 Hz timer where it is missing.
function scheduleFrame(cb: () => void): number {
  if (typeof requestAnimationFrame === 'function') return requestAnimationFrame(cb);
  return setTimeout(cb, 1000 / 60) as unknown as number;
}

function cancelFrame(handle: number): void {
  if (typeof cancelAnimationFrame === 'function') cancelAnimationFrame(handle);
  else clearTimeout(handle);
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
