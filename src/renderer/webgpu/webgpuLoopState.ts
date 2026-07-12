/**
 * webgpuLoopState.ts
 *
 * Builds a render-loop state object with getters bound to a WebGPURenderer host.
 */

import { WebGPURenderLoopState } from './WebGPURenderLoop';
import { WebGPUShaderManager } from './WebGPUShaderManager';
import { ShaderSlot } from './webgpuConstants';
import { Ripple } from '../UniformBuffer';

/** Minimal host surface the render loop reads/writes through getters. */
export interface WebGPURenderLoopHost {
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
  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;
  slots: ShaderSlot[];
  shaderManager: WebGPUShaderManager;
  ripples: Ripple[];
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  zoomParams: number[];
  audioBass: number;
  audioMid: number;
  audioTreble: number;
  audioFreqBins: Float32Array;
  historyHead: number;
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

export function createRenderLoopState(host: WebGPURenderLoopHost): WebGPURenderLoopState {
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
    get ripples() { return h.ripples; },
    get mouseX() { return h.mouseX; },
    get mouseYShader() { return h.mouseYShader; },
    get mouseDown() { return h.mouseDown; },
    get zoomParams() { return h.zoomParams; },
    get audioBass() { return h.audioBass; },
    get audioMid() { return h.audioMid; },
    get audioTreble() { return h.audioTreble; },
    get audioFreqBins() { return h.audioFreqBins; },
    get historyHead() { return h.historyHead; },
    set historyHead(v) { h.historyHead = v; },
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
