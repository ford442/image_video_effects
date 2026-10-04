/**
 * fakeFrameState.ts
 *
 * Builds a WebGPUFrameState over a FakeGpu so frame.ts / slotDispatch.ts can be
 * driven end-to-end in Jest (slot plans, graph runs, video ingest, chores hooks).
 */

import { CONSERVATIVE_BINDING_USAGE, ShaderBindingUsage } from '../ShaderCompilation';
import { createAudioDepthState } from '../webgpu/audioDepth';
import type { WebGPUFrameState } from '../webgpu/frameState';
import { createDisabledTimestampQueries } from '../webgpu/WebGPUTiming';
import { PHYSICAL_SLOT_LIMIT } from '../slotOrchestrator';
import type { ShaderSlot, SlotMode } from '../webgpu/webgpuConstants';
import type { FakeGpu } from './fakeGpu';

export interface FakeFrameStateOptions {
  /** Shader ids with a compiled pipeline (graph entries included). */
  pipelines?: string[];
  /** Per-shader binding usage; defaults to "writes nothing, reads nothing". */
  usage?: Record<string, Partial<ShaderBindingUsage>>;
  size?: number;
  historyLayers?: number;
}

const NO_USAGE: ShaderBindingUsage = {
  ...CONSERVATIVE_BINDING_USAGE,
  writesDataA: false,
  writesDataB: false,
  readsDataC: false,
  usesHistory: false,
};

export function createFakeFrameState(
  fake: FakeGpu,
  options: FakeFrameStateOptions = {},
): WebGPUFrameState & { setSlots(slots: Array<{ id: string; mode?: SlotMode; params?: number[] }>): void } {
  const size = options.size ?? 64;
  const pipelines = new Set(options.pipelines ?? []);
  const t = (label: string, layers = 1) => fake.texture(label, size, size, layers);
  const slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({
    shaderId: null,
    enabled: false,
    mode: 'chained' as SlotMode,
    params: [0.5, 0.5, 0.5, 0.5],
  }));
  const readTex = t('readTex');
  const canvasTex = t('canvas');

  const state = {
    device: fake.device,
    context: { getCurrentTexture: () => canvasTex } as unknown as GPUCanvasContext,
    initialized: true,
    startTime: 0,
    currentTime: 1,
    animationId: null,

    sourceTex: t('sourceTex'),
    readTex,
    writeTex: t('writeTex'),
    dataTexA: t('dataTexA'),
    dataTexB: t('dataTexB'),
    dataTexC: t('dataTexC'),
    historyTex: t('historyTex', options.historyLayers ?? 8),
    historyLayers: options.historyLayers ?? 8,
    blitReadTex: readTex,

    uniformBuf: fake.buffer('uniformBuf', 848),
    extraBuf: fake.buffer('extraBuf', 1024),
    plasmaBuf: fake.buffer('plasmaBuf', 2400),
    computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
    blitBindGroup: { label: 'blitBG' } as unknown as GPUBindGroup,
    blitBindGroupLayout: { label: 'blitBGL' } as unknown as GPUBindGroupLayout,
    blitPipeline: { label: 'blitPipeline' } as unknown as GPURenderPipeline,
    generativeBlitPipeline: { label: 'generativeBlitPipeline' } as unknown as GPURenderPipeline,
    scaleCopyPipeline: { label: 'scaleCopyPipeline' } as unknown as GPURenderPipeline,
    pipelineLayout: { label: 'computePL' } as unknown as GPUPipelineLayout,
    bindGroupLayout: { label: 'computeBGL' } as unknown as GPUBindGroupLayout,

    canvasW: size,
    canvasH: size,
    scaledW: size,
    scaledH: size,
    resolutionScale: 1,

    slots,
    getPipeline: (id: string) =>
      (pipelines.has(id) ? ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline) : undefined),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    hasPipeline: (id: string) => pipelines.has(id),
    getBindingUsage: (id: string) => ({ ...NO_USAGE, ...(options.usage?.[id] ?? {}) }),
    usesSimRing: () => false,
    getSimRing: () => null,
    writeSimRingParams: () => {},
    createBindGroupForPass: () => fake.device.createBindGroup({ label: 'computeBG-pass' } as GPUBindGroupDescriptor),
    createBindGroupForRoles: () => fake.device.createBindGroup({ label: 'computeBG-graph' } as GPUBindGroupDescriptor),
    getTextureSet: () => ({
      sourceTex: state.sourceTex,
      readTex: state.readTex,
      writeTex: state.writeTex,
      dataTexA: state.dataTexA,
      dataTexB: state.dataTexB,
      dataTexC: state.dataTexC,
      historyTex: state.historyTex,
      historyLayers: state.historyLayers,
    }) as unknown as ReturnType<WebGPUFrameState['getTextureSet']>,
    maxPassesPerFrame: 12,

    ripples: [],
    mouseX: 0.5,
    mouseYShader: 0.5,
    mouseDown: false,
    zoomParams: [0.5, 0.5, 0.5, 0.5],
    audioDepth: createAudioDepthState(),

    inputSource: 'image' as WebGPUFrameState['inputSource'],
    video: null,
    updateVideoFrame: () => {},

    frameCount: 0,
    lastFPSTime: 0,
    fps: 0,
    adaptiveQuality: false,
    targetFPS: 60,
    adaptQualityIfNeeded: () => {},

    lastBlitReadTex: readTex,
    lastBlitScaledW: size,
    lastBlitScaledH: size,

    supportsTimestampQuery: false,
    gpuTimings: { parallelTime: 0, chainedTime: 0, totalTime: 0 },
    timestampRuntime: createDisabledTimestampQueries(),

    setSlots(next: Array<{ id: string; mode?: SlotMode; params?: number[] }>) {
      for (let i = 0; i < slots.length; i++) {
        const s = next[i];
        slots[i] = s
          ? { shaderId: s.id, enabled: true, mode: s.mode ?? 'chained', params: s.params ?? [0.5, 0.5, 0.5, 0.5] }
          : { shaderId: null, enabled: false, mode: 'chained', params: [0.5, 0.5, 0.5, 0.5] };
      }
    },
  };
  return state as unknown as WebGPUFrameState & {
    setSlots(slots: Array<{ id: string; mode?: SlotMode; params?: number[] }>): void;
  };
}
