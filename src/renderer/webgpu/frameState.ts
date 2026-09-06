/**
 * frameState.ts
 *
 * Shared mutable frame state and the adapter from WebGPURenderer-owned modules.
 * Keeping this plumbing separate leaves frame.ts focused on frame lifecycle.
 */

import { ShaderBindingUsage } from '../ShaderCompilation';
import { Ripple } from '../UniformBuffer';
import { AudioDepthState } from './audioDepth';
import { WebGPUPipelineModule, WebGPUShaderManager } from './pipeline';
import {
  WebGPUBufferSet,
  WebGPUResourcePool,
  WebGPUSamplerSet,
  WebGPUTextureSet,
} from './resources';
import { WebGPUTimestampQueries } from './WebGPUTiming';
import { ShaderSlot } from './webgpuConstants';

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
  historyLayers: number;
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
  /** Mutable GPU timestamp runtime (shared with WebGPURenderer). */
  timestampRuntime: WebGPUTimestampQueries;
  encodePreFxChores?: (encoder: GPUCommandEncoder) => void;
  afterFrameSubmitChores?: () => void;
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
  historyLayers: number;
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
  timestampRuntime: WebGPUTimestampQueries;
  encodePreFxChores?: (encoder: GPUCommandEncoder) => void;
  afterFrameSubmitChores?: () => void;
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
  timestampRuntime: WebGPUTimestampQueries;
  maxPassesPerFrame: number;
  encodePreFxChores?: (encoder: GPUCommandEncoder) => void;
  afterFrameSubmitChores?: () => void;
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
    get historyLayers() { return d.resources.historyLayers; },
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
    get timestampRuntime() { return d.timestampRuntime; },
    encodePreFxChores: (encoder) => d.encodePreFxChores?.(encoder),
    afterFrameSubmitChores: () => d.afterFrameSubmitChores?.(),
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
    get historyLayers() { return h.historyLayers; },
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
    get timestampRuntime() { return h.timestampRuntime; },
    encodePreFxChores: (encoder) => h.encodePreFxChores?.(encoder),
    afterFrameSubmitChores: () => h.afterFrameSubmitChores?.(),
  };
}
