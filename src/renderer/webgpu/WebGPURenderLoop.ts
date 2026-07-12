/**
 * WebGPURenderLoop.ts
 *
 * Frame rendering, compute dispatch, and canvas blit for the WebGPU renderer.
 */

import { GPUTimings } from '../Renderer';
import { resolveMultipassChain } from '../multipassRegistry';
import {
  createUniformBufferView,
  UniformBufferView,
  MAX_RIPPLES,
} from '../UniformBuffer';
import { createBlitBindGroup } from './WebGPUResourceManager';
import {
  AUDIO_FFT_BINS,
  EXTRA_BIN_OFFSET,
  EXTRA_FLOATS,
  HISTORY_DEPTH,
  ShaderSlot,
  SlotMode,
  WG_SIZE_X,
  WG_SIZE_Y,
} from './webgpuConstants';

export interface WebGPURenderLoopState {
  device: GPUDevice | null;
  context: GPUCanvasContext | null;
  initialized: boolean;
  startTime: number;
  currentTime: number;
  animationId: number | null;

  // Textures
  sourceTex: GPUTexture;
  readTex: GPUTexture;
  writeTex: GPUTexture;
  dataTexA: GPUTexture;
  dataTexB: GPUTexture;
  dataTexC: GPUTexture;
  historyTex: GPUTexture;
  blitReadTex: GPUTexture;

  // Buffers & bind groups
  uniformBuf: GPUBuffer;
  extraBuf: GPUBuffer;
  computeBindGroup: GPUBindGroup;
  blitBindGroup: GPUBindGroup;
  blitBindGroupLayout: GPUBindGroupLayout;
  blitPipeline: GPURenderPipeline;
  generativeBlitPipeline: GPURenderPipeline;

  // Samplers & video copy
  filterSampler: GPUSampler;
  videoCopyPipeline: GPURenderPipeline | null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null;

  // Dimensions
  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;

  // Slots & shaders
  slots: ShaderSlot[];
  getPipeline: (id: string) => GPUComputePipeline | undefined;
  getWorkgroupSize: (id: string) => { x: number; y: number };
  hasPipeline: (id: string) => boolean;

  // Uniform / audio state
  ripples: { x: number; y: number; startTime: number }[];
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  zoomParams: number[];
  audioBass: number;
  audioMid: number;
  audioTreble: number;
  audioFreqBins: Float32Array;
  historyHead: number;

  // Input
  inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live';
  video: HTMLVideoElement | null;
  updateVideoFrame: () => void;

  // FPS / adaptive quality
  frameCount: number;
  lastFPSTime: number;
  fps: number;
  adaptiveQuality: boolean;
  targetFPS: number;
  adaptQualityIfNeeded: () => void;

  // Blit cache
  lastBlitReadTex: GPUTexture | null;
  lastBlitScaledW: number;
  lastBlitScaledH: number;

  // Timestamp queries
  supportsTimestampQuery: boolean;
  gpuTimings: { parallelTime: number; chainedTime: number; totalTime: number };
}

export class WebGPURenderLoop {
  private uniformView: UniformBufferView = createUniformBufferView();

  startRenderLoop(state: WebGPURenderLoopState): void {
    const loop = () => {
      if (!state.initialized) return;
      state.currentTime = performance.now() / 1000 - state.startTime;
      this.renderFrame(state);
      state.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  stopRenderLoop(state: WebGPURenderLoopState): void {
    if (state.animationId !== null) {
      cancelAnimationFrame(state.animationId);
      state.animationId = null;
    }
  }

  getGPUTimings(state: WebGPURenderLoopState): GPUTimings {
    return {
      ...state.gpuTimings,
      available: state.supportsTimestampQuery,
      timingSource: state.supportsTimestampQuery ? 'gpu-timestamp' : 'wall-clock',
    };
  }

  renderFrame(state: WebGPURenderLoopState): void {
    if (!state.device || !state.context || !state.initialized) return;

    if (state.video && !state.video.paused && state.video.readyState >= 2) {
      state.updateVideoFrame();
    } else if (state.video && state.video.readyState >= 2 && state.frameCount % 60 === 0) {
      if (process.env.NODE_ENV === 'development') {
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

    const enabled = state.slots.filter(
      (s) => s.enabled && s.shaderId && state.hasPipeline(s.shaderId),
    );

    if (enabled.length === 0) {
      state.blitReadTex = state.readTex;
      this.blitToCanvas(state);
      return;
    }

    this.writeUniforms(state);

    const encoder = state.device.createCommandEncoder({ label: 'frame' });

    if (state.resolutionScale < 1.0) {
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
      scalePass.setPipeline(state.videoCopyPipeline!);
      scalePass.setBindGroup(
        0,
        state.device.createBindGroup({
          layout: state.videoCopyBindGroupLayout!,
          entries: [
            { binding: 0, resource: state.sourceTex.createView() },
            { binding: 1, resource: state.filterSampler },
          ],
        }),
      );
      scalePass.draw(3);
      scalePass.end();
    } else {
      encoder.copyTextureToTexture(
        { texture: state.sourceTex },
        { texture: state.readTex },
        [state.canvasW, state.canvasH, 1],
      );
    }

    const parallelSlots = enabled.filter((s) => s.mode === 'parallel');
    const chainedSlots = enabled.filter((s) => s.mode === 'chained');
    const singleChained = enabled.length === 1 && enabled[0].mode === 'chained';
    state.blitReadTex = state.readTex;

    if (state.frameCount % 60 === 0) {
      console.log(
        `[WebGPURenderer] Parallel slots: ${parallelSlots.length}, Chained slots: ${chainedSlots.length}`,
      );
      if (chainedSlots.length > 0) {
        console.log(
          `[WebGPURenderer] Chained slot order:`,
          chainedSlots.map((s) => s.shaderId),
        );
      }
    }

    for (const slot of parallelSlots) {
      this.dispatchSlot(state, encoder, slot, 'parallel');
    }

    if (parallelSlots.length > 0) {
      encoder.copyTextureToTexture(
        { texture: state.writeTex },
        { texture: state.readTex },
        [state.scaledW, state.scaledH, 1],
      );
    }

    for (let i = 0; i < chainedSlots.length; i++) {
      const slot = chainedSlots[i];
      if (state.frameCount % 60 === 0) {
        console.log(`[WebGPURenderer] Processing chained slot ${i}: ${slot.shaderId}`);
      }
      this.dispatchSlot(state, encoder, slot, 'chained');

      if (singleChained) {
        state.blitReadTex = state.writeTex;
      } else {
        encoder.copyTextureToTexture(
          { texture: state.writeTex },
          { texture: state.readTex },
          [state.scaledW, state.scaledH, 1],
        );
      }

      encoder.copyTextureToTexture(
        { texture: state.dataTexA },
        { texture: state.dataTexC },
        [state.scaledW, state.scaledH, 1],
      );

      encoder.copyTextureToTexture(
        { texture: state.dataTexB },
        { texture: state.dataTexC },
        [state.scaledW, state.scaledH, 1],
      );
    }

    encoder.copyTextureToTexture(
      { texture: state.blitReadTex },
      { texture: state.historyTex, origin: [0, 0, state.historyHead] },
      [state.scaledW, state.scaledH, 1],
    );

    state.device.queue.submit([encoder.finish()]);
    state.historyHead = (state.historyHead + 1) % HISTORY_DEPTH;

    this.blitToCanvas(state);

    state.frameCount++;
    const now = performance.now() / 1000;
    if (now - state.lastFPSTime >= 1.0) {
      state.fps = state.frameCount / (now - state.lastFPSTime);
      state.frameCount = 0;
      state.lastFPSTime = now;
      state.adaptQualityIfNeeded();
    }
  }

  private dispatchSlot(
    state: WebGPURenderLoopState,
    encoder: GPUCommandEncoder,
    slot: { shaderId: string | null; enabled: boolean; mode: SlotMode },
    labelPrefix: string,
  ): void {
    if (!slot.shaderId) return;
    const chain = resolveMultipassChain(slot.shaderId);
    for (const shaderId of chain) {
      const pipeline = state.getPipeline(shaderId);
      if (!pipeline) {
        console.warn(`[WebGPURenderer] Pipeline missing for multipass step "${shaderId}"`);
        continue;
      }
      const wg = state.getWorkgroupSize(shaderId);
      const pass = encoder.beginComputePass({ label: `${labelPrefix}-${shaderId}` });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, state.computeBindGroup);
      pass.dispatchWorkgroups(
        Math.ceil(state.scaledW / wg.x),
        Math.ceil(state.scaledH / wg.y),
        1,
      );
      pass.end();
    }
  }

  private writeUniforms(state: WebGPURenderLoopState): void {
    if (!state.device) return;

    const u = this.uniformView;
    u.setConfig(state.currentTime, state.ripples.length, state.scaledW, state.scaledH);
    u.setZoomConfig(
      state.currentTime,
      state.mouseX,
      state.mouseYShader,
      state.mouseDown ? 1 : 0,
    );
    u.setZoomParams(
      state.zoomParams[0],
      state.zoomParams[1],
      state.zoomParams[2],
      state.zoomParams[3],
    );

    for (let i = 0; i < MAX_RIPPLES; i++) {
      if (i < state.ripples.length) {
        const r = state.ripples[i];
        u.setRipple(i, r.x, r.y, r.startTime);
      } else {
        u.clearRipple(i);
      }
    }

    state.device.queue.writeBuffer(state.uniformBuf, 0, u.data);

    const extraData = new Float32Array(EXTRA_FLOATS);
    extraData[0] = state.audioBass;
    extraData[1] = state.audioMid;
    extraData[2] = state.audioTreble;
    extraData[3] = 0;
    extraData[4] = state.historyHead;
    extraData.set(state.audioFreqBins, EXTRA_BIN_OFFSET);
    state.device.queue.writeBuffer(state.extraBuf, 0, extraData);
  }

  private blitToCanvas(state: WebGPURenderLoopState): void {
    if (!state.device || !state.context || !state.initialized) return;

    try {
      const currentTexture = state.context.getCurrentTexture();
      if (!currentTexture) return;
    } catch {
      return;
    }

    this.updateBlitBindGroup(state);

    const encoder = state.device.createCommandEncoder({ label: 'blit' });
    const pipeline =
      state.inputSource === 'generative'
        ? state.generativeBlitPipeline
        : state.blitPipeline;
    const pass = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: state.context.getCurrentTexture().createView(),
          loadOp: 'clear',
          storeOp: 'store',
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
        },
      ],
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, state.blitBindGroup);
    pass.draw(3);
    pass.end();
    state.device.queue.submit([encoder.finish()]);
  }

  private updateBlitBindGroup(state: WebGPURenderLoopState): void {
    if (!state.device) return;
    if (
      state.blitBindGroup &&
      state.blitReadTex === state.lastBlitReadTex &&
      state.scaledW === state.lastBlitScaledW &&
      state.scaledH === state.lastBlitScaledH
    ) {
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
}

export function computeScaledDimensions(
  canvasW: number,
  canvasH: number,
  resolutionScale: number,
): { scaledW: number; scaledH: number } {
  const scaledW =
    Math.ceil((canvasW * resolutionScale) / WG_SIZE_X) * WG_SIZE_X;
  const scaledH =
    Math.ceil((canvasH * resolutionScale) / WG_SIZE_Y) * WG_SIZE_Y;
  return { scaledW, scaledH };
}

export function createDefaultAudioFreqBins(): Float32Array {
  return new Float32Array(AUDIO_FFT_BINS);
}
