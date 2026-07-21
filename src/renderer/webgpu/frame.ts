/**
 * frame.ts
 *
 * Frame rendering, compute dispatch, slot orchestration, and canvas blit.
 * Mirrors wasm_renderer/frame.cpp.
 */

import { GPUTimings } from '../Renderer';
import { resolveMultipassChain } from '../multipassRegistry';
import { resolveGraphForShader } from '../multipassGraph';
import { analyzeGraphBindingUsage, graphRunner } from '../GraphRunner';
import { ShaderBindingUsage } from '../ShaderCompilation';
import {
  createUniformBufferView,
  UniformBufferView,
  MAX_RIPPLES,
  Ripple,
} from '../UniformBuffer';
import { WebGPUShaderManager, WebGPUPipelineModule, createBlitBindGroup } from './pipeline';
import { writeExtraBuffer, AudioDepthState } from './audioDepth';
import { WebGPUTextureSet, WebGPUBufferSet, WebGPUSamplerSet, WebGPUResourcePool } from './resources';
import {
  AUDIO_FFT_BINS,
  HISTORY_DEPTH,
  ShaderSlot,
  WG_SIZE_X,
  WG_SIZE_Y,
} from './webgpuConstants';

export interface WebGPUFrameState {
  device: GPUDevice | null;
  context: GPUCanvasContext | null;
  initialized: boolean;
  startTime: number;
  currentTime: number;
  animationId: number | null;

  sourceTex: GPUTexture;
  readTex: GPUTexture;
  writeTex: GPUTexture;
  dataTexA: GPUTexture;
  dataTexB: GPUTexture;
  dataTexC: GPUTexture;
  historyTex: GPUTexture;
  blitReadTex: GPUTexture;

  uniformBuf: GPUBuffer;
  extraBuf: GPUBuffer;
  computeBindGroup: GPUBindGroup;
  blitBindGroup: GPUBindGroup;
  blitBindGroupLayout: GPUBindGroupLayout;
  blitPipeline: GPURenderPipeline;
  generativeBlitPipeline: GPURenderPipeline;
  scaleCopyPipeline: GPURenderPipeline;
  pipelineLayout: GPUPipelineLayout;
  bindGroupLayout: GPUBindGroupLayout;

  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;

  slots: ShaderSlot[];
  getPipeline: (id: string) => GPUComputePipeline | undefined;
  getWorkgroupSize: (id: string) => { x: number; y: number };
  hasPipeline: (id: string) => boolean;
  getBindingUsage: (id: string) => ShaderBindingUsage;
  createBindGroupForPass: (readTex: GPUTexture, writeTex: GPUTexture) => GPUBindGroup;
  createBindGroupForRoles: (roles: {
    read: GPUTexture;
    color: GPUTexture;
    dataA: GPUTexture;
    dataB: GPUTexture;
    dataC: GPUTexture;
  }) => GPUBindGroup;
  getTextureSet: () => WebGPUTextureSet;
  maxPassesPerFrame: number;

  ripples: Ripple[];
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  zoomParams: number[];
  audioDepth: AudioDepthState;

  inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live';
  video: HTMLVideoElement | null;
  updateVideoFrame: () => void;

  frameCount: number;
  lastFPSTime: number;
  fps: number;
  adaptiveQuality: boolean;
  targetFPS: number;
  adaptQualityIfNeeded: () => void;

  lastBlitReadTex: GPUTexture | null;
  lastBlitScaledW: number;
  lastBlitScaledH: number;

  supportsTimestampQuery: boolean;
  gpuTimings: { parallelTime: number; chainedTime: number; totalTime: number };
}

/** Minimal host surface the frame loop reads/writes through getters. */
export interface WebGPUFrameHost {
  device: GPUDevice | null;
  context: GPUCanvasContext | null;
  initialized: boolean;
  startTime: number;
  currentTime: number;
  animationId: number | null;
  sourceTex: GPUTexture;
  readTex: GPUTexture;
  writeTex: GPUTexture;
  dataTexA: GPUTexture;
  dataTexB: GPUTexture;
  dataTexC: GPUTexture;
  historyTex: GPUTexture;
  blitReadTex: GPUTexture;
  uniformBuf: GPUBuffer;
  extraBuf: GPUBuffer;
  computeBindGroup: GPUBindGroup;
  blitBindGroup: GPUBindGroup;
  blitBindGroupLayout: GPUBindGroupLayout;
  blitPipeline: GPURenderPipeline;
  generativeBlitPipeline: GPURenderPipeline;
  scaleCopyPipeline: GPURenderPipeline;
  pipelineLayout: GPUPipelineLayout;
  bindGroupLayout: GPUBindGroupLayout;
  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;
  slots: ShaderSlot[];
  shaderManager: WebGPUShaderManager;
  getTextureSet: () => WebGPUTextureSet;
  getBufferSet: () => WebGPUBufferSet;
  getSamplerSet: () => WebGPUSamplerSet;
  createBindGroupForPass: (readTex: GPUTexture, writeTex: GPUTexture) => GPUBindGroup;
  createBindGroupForRoles: (roles: {
    read: GPUTexture;
    color: GPUTexture;
    dataA: GPUTexture;
    dataB: GPUTexture;
    dataC: GPUTexture;
  }) => GPUBindGroup;
  maxPassesPerFrame: number;
  ripples: Ripple[];
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  zoomParams: number[];
  audioDepth: AudioDepthState;
  inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live';
  mediaVideo: HTMLVideoElement | null;
  updateVideoFrame: () => void;
  frameCount: number;
  lastFPSTime: number;
  fps: number;
  adaptiveQuality: boolean;
  targetFPS: number;
  adaptQualityIfNeeded: () => void;
  lastBlitReadTex: GPUTexture | null;
  lastBlitScaledW: number;
  lastBlitScaledH: number;
  supportsTimestampQuery: boolean;
  gpuTimings: { parallelTime: number; chainedTime: number; totalTime: number };
}

/** Dependencies passed from WebGPURenderer to build a frame host. */
export interface RendererFrameDeps {
  get device(): GPUDevice | null;
  set device(v: GPUDevice | null);
  get context(): GPUCanvasContext | null;
  set context(v: GPUCanvasContext | null);
  get initialized(): boolean;
  set initialized(v: boolean);
  get startTime(): number;
  set startTime(v: number);
  get currentTime(): number;
  set currentTime(v: number);
  get animationId(): number | null;
  set animationId(v: number | null);
  resources: WebGPUResourcePool;
  pipeline: WebGPUPipelineModule;
  get computeBindGroup(): GPUBindGroup;
  get blitReadTex(): GPUTexture;
  set blitReadTex(v: GPUTexture);
  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;
  slots: ShaderSlot[];
  ripples: Ripple[];
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  zoomParams: number[];
  audioDepth: AudioDepthState;
  inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live';
  mediaVideo: HTMLVideoElement | null;
  updateVideoFrame: () => void;
  frameCount: number;
  lastFPSTime: number;
  fps: number;
  adaptiveQuality: boolean;
  targetFPS: number;
  adaptQualityIfNeeded: () => void;
  lastBlitReadTex: GPUTexture | null;
  lastBlitScaledW: number;
  lastBlitScaledH: number;
  supportsTimestampQuery: boolean;
  gpuTimings: { parallelTime: number; chainedTime: number; totalTime: number };
  maxPassesPerFrame: number;
}

export function createRendererFrameHost(d: RendererFrameDeps): WebGPUFrameHost {
  return {
    get device() { return d.device; },
    set device(v) { d.device = v; },
    get context() { return d.context; },
    set context(v) { d.context = v; },
    get initialized() { return d.initialized; },
    set initialized(v) { d.initialized = v; },
    get startTime() { return d.startTime; },
    set startTime(v) { d.startTime = v; },
    get currentTime() { return d.currentTime; },
    set currentTime(v) { d.currentTime = v; },
    get animationId() { return d.animationId; },
    set animationId(v) { d.animationId = v; },
    get sourceTex() { return d.resources.sourceTex; },
    get readTex() { return d.resources.readTex; },
    get writeTex() { return d.resources.writeTex; },
    get dataTexA() { return d.resources.dataTexA; },
    get dataTexB() { return d.resources.dataTexB; },
    get dataTexC() { return d.resources.dataTexC; },
    get historyTex() { return d.resources.historyTex; },
    get blitReadTex() { return d.blitReadTex; },
    set blitReadTex(v) { d.blitReadTex = v; },
    get uniformBuf() { return d.resources.uniformBuf; },
    get extraBuf() { return d.resources.extraBuf; },
    get computeBindGroup() { return d.computeBindGroup; },
    get blitBindGroup() { return d.pipeline.blitBindGroup; },
    set blitBindGroup(v) { d.pipeline.blitBindGroup = v; },
    get blitBindGroupLayout() { return d.pipeline.blitBindGroupLayout; },
    get blitPipeline() { return d.pipeline.blitPipeline; },
    get generativeBlitPipeline() { return d.pipeline.generativeBlitPipeline; },
    get scaleCopyPipeline() { return d.pipeline.scaleCopyPipeline; },
    get pipelineLayout() { return d.pipeline.pipelineLayout; },
    get bindGroupLayout() { return d.pipeline.bindGroupLayout; },
    get canvasW() { return d.canvasW; },
    get canvasH() { return d.canvasH; },
    get scaledW() { return d.scaledW; },
    get scaledH() { return d.scaledH; },
    get resolutionScale() { return d.resolutionScale; },
    get slots() { return d.slots; },
    get shaderManager() { return d.pipeline.shaderManager; },
    getTextureSet: () => d.resources.getTextureSet(),
    getBufferSet: () => d.resources.getBufferSet(),
    getSamplerSet: () => d.resources.getSamplerSet(),
    createBindGroupForPass: (read, write) =>
      d.pipeline.createBindGroupForPass(
        d.device!, read, write,
        d.resources.getTextureSet(), d.resources.getBufferSet(), d.resources.getSamplerSet(),
      ),
    createBindGroupForRoles: (roles) =>
      d.pipeline.createBindGroupForRoles(
        d.device!, roles,
        d.resources.getTextureSet(), d.resources.getBufferSet(), d.resources.getSamplerSet(),
      ),
    get maxPassesPerFrame() { return d.maxPassesPerFrame; },
    set maxPassesPerFrame(v) { d.maxPassesPerFrame = v; },
    get ripples() { return d.ripples; },
    get mouseX() { return d.mouseX; },
    get mouseYShader() { return d.mouseYShader; },
    get mouseDown() { return d.mouseDown; },
    get zoomParams() { return d.zoomParams; },
    get audioDepth() { return d.audioDepth; },
    get inputSource() { return d.inputSource; },
    get mediaVideo() { return d.mediaVideo; },
    updateVideoFrame: () => d.updateVideoFrame(),
    get frameCount() { return d.frameCount; },
    set frameCount(v) { d.frameCount = v; },
    get lastFPSTime() { return d.lastFPSTime; },
    set lastFPSTime(v) { d.lastFPSTime = v; },
    get fps() { return d.fps; },
    set fps(v) { d.fps = v; },
    get adaptiveQuality() { return d.adaptiveQuality; },
    get targetFPS() { return d.targetFPS; },
    adaptQualityIfNeeded: () => d.adaptQualityIfNeeded(),
    get lastBlitReadTex() { return d.lastBlitReadTex; },
    set lastBlitReadTex(v) { d.lastBlitReadTex = v; },
    get lastBlitScaledW() { return d.lastBlitScaledW; },
    set lastBlitScaledW(v) { d.lastBlitScaledW = v; },
    get lastBlitScaledH() { return d.lastBlitScaledH; },
    set lastBlitScaledH(v) { d.lastBlitScaledH = v; },
    get supportsTimestampQuery() { return d.supportsTimestampQuery; },
    get gpuTimings() { return d.gpuTimings; },
  };
}

export function createFrameState(host: WebGPUFrameHost): WebGPUFrameState {
  const h = host;
  return {
    get device() { return h.device; },
    set device(v) { h.device = v; },
    get context() { return h.context; },
    set context(v) { h.context = v; },
    get initialized() { return h.initialized; },
    set initialized(v) { h.initialized = v; },
    get startTime() { return h.startTime; },
    set startTime(v) { h.startTime = v; },
    get currentTime() { return h.currentTime; },
    set currentTime(v) { h.currentTime = v; },
    get animationId() { return h.animationId; },
    set animationId(v) { h.animationId = v; },
    get sourceTex() { return h.sourceTex; },
    get readTex() { return h.readTex; },
    get writeTex() { return h.writeTex; },
    get dataTexA() { return h.dataTexA; },
    get dataTexB() { return h.dataTexB; },
    get dataTexC() { return h.dataTexC; },
    get historyTex() { return h.historyTex; },
    get blitReadTex() { return h.blitReadTex; },
    set blitReadTex(v) { h.blitReadTex = v; },
    get uniformBuf() { return h.uniformBuf; },
    get extraBuf() { return h.extraBuf; },
    get computeBindGroup() { return h.computeBindGroup; },
    get blitBindGroup() { return h.blitBindGroup; },
    set blitBindGroup(v) { h.blitBindGroup = v; },
    get blitBindGroupLayout() { return h.blitBindGroupLayout; },
    get blitPipeline() { return h.blitPipeline; },
    get generativeBlitPipeline() { return h.generativeBlitPipeline; },
    get scaleCopyPipeline() { return h.scaleCopyPipeline; },
    get pipelineLayout() { return h.pipelineLayout; },
    get bindGroupLayout() { return h.bindGroupLayout; },
    get canvasW() { return h.canvasW; },
    get canvasH() { return h.canvasH; },
    get scaledW() { return h.scaledW; },
    get scaledH() { return h.scaledH; },
    get resolutionScale() { return h.resolutionScale; },
    get slots() { return h.slots; },
    getPipeline: (id) => h.shaderManager.getPipeline(id),
    getWorkgroupSize: (id) => h.shaderManager.getWorkgroupSize(id),
    hasPipeline: (id) => h.shaderManager.hasPipeline(id),
    getBindingUsage: (id) => h.shaderManager.getBindingUsage(id),
    createBindGroupForPass: (read, write) => h.createBindGroupForPass(read, write),
    createBindGroupForRoles: (roles) => h.createBindGroupForRoles(roles),
    getTextureSet: () => h.getTextureSet(),
    get maxPassesPerFrame() { return h.maxPassesPerFrame; },
    set maxPassesPerFrame(v) { h.maxPassesPerFrame = v; },
    get ripples() { return h.ripples; },
    get mouseX() { return h.mouseX; },
    get mouseYShader() { return h.mouseYShader; },
    get mouseDown() { return h.mouseDown; },
    get zoomParams() { return h.zoomParams; },
    get audioDepth() { return h.audioDepth; },
    get inputSource() { return h.inputSource; },
    get video() { return h.mediaVideo; },
    updateVideoFrame: () => h.updateVideoFrame(),
    get frameCount() { return h.frameCount; },
    set frameCount(v) { h.frameCount = v; },
    get lastFPSTime() { return h.lastFPSTime; },
    set lastFPSTime(v) { h.lastFPSTime = v; },
    get fps() { return h.fps; },
    set fps(v) { h.fps = v; },
    get adaptiveQuality() { return h.adaptiveQuality; },
    get targetFPS() { return h.targetFPS; },
    adaptQualityIfNeeded: () => h.adaptQualityIfNeeded(),
    get lastBlitReadTex() { return h.lastBlitReadTex; },
    set lastBlitReadTex(v) { h.lastBlitReadTex = v; },
    get lastBlitScaledW() { return h.lastBlitScaledW; },
    set lastBlitScaledW(v) { h.lastBlitScaledW = v; },
    get lastBlitScaledH() { return h.lastBlitScaledH; },
    set lastBlitScaledH(v) { h.lastBlitScaledH = v; },
    get supportsTimestampQuery() { return h.supportsTimestampQuery; },
    get gpuTimings() { return h.gpuTimings; },
  };
}

export class WebGPUFrameRenderer {
  private uniformView: UniformBufferView = createUniformBufferView();
  private scaleBindGroup: GPUBindGroup | null = null;
  private scaleBindGroupTex: GPUTexture | null = null;

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
    return {
      ...state.gpuTimings,
      available: state.supportsTimestampQuery,
      timingSource: state.supportsTimestampQuery ? 'gpu-timestamp' : 'wall-clock',
    };
  }

  renderFrame(state: WebGPUFrameState): void {
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

    let anyReadsC = false;
    let anyUsesHistory = false;
    const slotPlans = enabled.map((slot) => {
      const graph = resolveGraphForShader(slot.shaderId!);
      let writesDataA = false;
      let writesDataB = false;

      if (graph) {
        const usage = analyzeGraphBindingUsage(graph);
        writesDataA = usage.writesDataA;
        writesDataB = usage.writesDataB;
        anyReadsC = anyReadsC || usage.readsDataC;
        for (const node of graph.nodes) {
          const entryUsage = state.getBindingUsage(node.entry);
          anyUsesHistory = anyUsesHistory || entryUsage.usesHistory;
        }
      } else {
        const chain = resolveMultipassChain(slot.shaderId!);
        for (const id of chain) {
          const usage = state.getBindingUsage(id);
          writesDataA = writesDataA || usage.writesDataA;
          writesDataB = writesDataB || usage.writesDataB;
          anyReadsC = anyReadsC || usage.readsDataC;
          anyUsesHistory = anyUsesHistory || usage.usesHistory;
        }
      }
      return { slot, writesDataA, writesDataB };
    });

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
      scalePass.setPipeline(state.scaleCopyPipeline);
      scalePass.setBindGroup(0, this.getScaleBindGroup(state));
      scalePass.draw(3);
      scalePass.end();
    } else {
      encoder.copyTextureToTexture(
        { texture: state.sourceTex },
        { texture: state.readTex },
        [state.canvasW, state.canvasH, 1],
      );
    }

    const parallelPlans = slotPlans.filter((p) => p.slot.mode === 'parallel');
    const chainedPlans = slotPlans.filter((p) => p.slot.mode === 'chained');
    const singleChained = enabled.length === 1 && enabled[0].mode === 'chained';
    state.blitReadTex = state.readTex;

    if (process.env.NODE_ENV === 'development' && state.frameCount % 60 === 0) {
      console.log(
        `[WebGPURenderer] Parallel slots: ${parallelPlans.length}, Chained slots: ${chainedPlans.length}`,
      );
      if (chainedPlans.length > 0) {
        console.log(
          `[WebGPURenderer] Chained slot order:`,
          chainedPlans.map((p) => p.slot.shaderId),
        );
      }
    }

    for (const plan of parallelPlans) {
      this.dispatchSlot(state, encoder, plan.slot, 'parallel');
    }

    if (parallelPlans.length > 0) {
      encoder.copyTextureToTexture(
        { texture: state.writeTex },
        { texture: state.readTex },
        [state.scaledW, state.scaledH, 1],
      );
    }

    for (const plan of chainedPlans) {
      this.dispatchSlot(state, encoder, plan.slot, 'chained');

      if (singleChained) {
        state.blitReadTex = state.writeTex;
      } else {
        encoder.copyTextureToTexture(
          { texture: state.writeTex },
          { texture: state.readTex },
          [state.scaledW, state.scaledH, 1],
        );
      }

      if (anyReadsC) {
        if (plan.writesDataA) {
          encoder.copyTextureToTexture(
            { texture: state.dataTexA },
            { texture: state.dataTexC },
            [state.scaledW, state.scaledH, 1],
          );
        }
        if (plan.writesDataB) {
          encoder.copyTextureToTexture(
            { texture: state.dataTexB },
            { texture: state.dataTexC },
            [state.scaledW, state.scaledH, 1],
          );
        }
      }
    }

    if (anyUsesHistory) {
      encoder.copyTextureToTexture(
        { texture: state.blitReadTex },
        { texture: state.historyTex, origin: [0, 0, state.audioDepth.historyHead] },
        [state.scaledW, state.scaledH, 1],
      );
    }

    this.updateBlitBindGroup(state);
    this.encodeBlit(state, encoder);

    state.device.queue.submit([encoder.finish()]);
    if (anyUsesHistory) {
      state.audioDepth.historyHead = (state.audioDepth.historyHead + 1) % HISTORY_DEPTH;
    }

    state.frameCount++;
    const now = performance.now() / 1000;
    if (now - state.lastFPSTime >= 1.0) {
      state.fps = state.frameCount / (now - state.lastFPSTime);
      state.frameCount = 0;
      state.lastFPSTime = now;
      state.adaptQualityIfNeeded();
    }
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

  private dispatchSlot(
    state: WebGPUFrameState,
    encoder: GPUCommandEncoder,
    slot: ShaderSlot,
    labelPrefix: string,
  ): void {
    if (!slot.shaderId || !state.device) return;

    const graph = resolveGraphForShader(slot.shaderId);
    if (graph) {
      const textures = state.getTextureSet();
      const roleTextures = {
        read: textures.readTex,
        color: textures.writeTex,
        dataA: textures.dataTexA,
        dataB: textures.dataTexB,
        dataC: textures.dataTexC,
      };
      graphRunner.runGraph(encoder, graph, {
        device: state.device,
        pipelineLayout: state.pipelineLayout,
        getPipeline: (shaderId) => state.getPipeline(shaderId),
        getWorkgroupSize: (shaderId) => state.getWorkgroupSize(shaderId),
        createBindGroupForRoles: (roles) => state.createBindGroupForRoles(roles),
        textures: roleTextures,
        scaledW: state.scaledW,
        scaledH: state.scaledH,
        maxPassesPerFrame: state.maxPassesPerFrame,
      });
      return;
    }

    for (const shaderId of resolveMultipassChain(slot.shaderId)) {
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

  private writeUniforms(state: WebGPUFrameState): void {
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
    writeExtraBuffer(state.device, state.extraBuf, state.audioDepth);
  }

  private encodeBlit(state: WebGPUFrameState, encoder: GPUCommandEncoder): void {
    if (!state.context) return;

    let currentTexture: GPUTexture;
    try {
      currentTexture = state.context.getCurrentTexture();
    } catch {
      return;
    }
    if (!currentTexture) return;

    const pipeline =
      state.inputSource === 'generative'
        ? state.generativeBlitPipeline
        : state.blitPipeline;
    const pass = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: currentTexture.createView(),
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
  }

  private blitToCanvas(state: WebGPUFrameState): void {
    if (!state.device || !state.context || !state.initialized) return;

    this.updateBlitBindGroup(state);

    const encoder = state.device.createCommandEncoder({ label: 'blit' });
    this.encodeBlit(state, encoder);
    state.device.queue.submit([encoder.finish()]);
  }

  private updateBlitBindGroup(state: WebGPUFrameState): void {
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
