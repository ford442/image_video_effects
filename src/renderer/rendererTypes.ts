import type { GpuChoresBreadcrumbs } from '../gpuChores';
import type { WebGpuProbeSerializable } from './webgpuBootProbe';
import type { WasmErrorRing } from '../wasm/wasm_bridge';
import type { RendererType } from './backendLifecycle';
import type { GraphRunReport } from './GraphRunner';
import type { FrameStats } from './webgpu/deviceCounters';
import type { PassTiming } from './passTimings';
import type { VideoIngestStats } from './media/videoFramePump';
import type { DeviceRecoveryStatus } from './deviceRecovery';

/**
 * Diagnostic information from the WASM renderer (type-only: the renderer itself is lazy-loaded).
 */
export interface WASMDiagnostics {
  initialized: boolean;
  initAttempts: number;
  errorCount: number;
  lastErrorTime: string | null;
  fps: number;
  hasModule: boolean;
  adapterInfo: string;
  /** WebGPURenderer::InitStage of the last Initialize() attempt (0=None, 8=Ready). */
  failedStage: number;
  /** Human-readable reason for the last Initialize() failure, or '' if none. */
  lastInitError: string;
  /** InitStage name from C++ (e.g. 'Device', 'Surface'). */
  failedStageName: string;
  /** Bridge-layer load/init failures (from wasm_bridge getDiagnostics). */
  loadErrorCount: number;
  lastLoadError: string | null;
  initTime: string;
  /** One-line "ready / partial / failed at <stage> · adapter: …" summary for the debug panel. */
  initSummary: string;
  /** C++ canvas COPY_SRC probe (canvas_configure.json optIn.copySrc); null = artifact predates it. */
  canvasCopySrc: boolean | null;
  /** MAX_SHADER_SLOTS in the loaded artifact; null = artifact predates the export. */
  maxShaderSlots: number | null;
  /** Emscripten glue that loaded: 'jspi' or 'asyncify'. null before init. */
  wasmArtifact: 'jspi' | 'asyncify' | null;
  /** Smoothed per-pass GPU ms from C++ timestamp queries (#1314 D); [] until they resolve. */
  passTimings: PassTiming[];
  /** C++ uncaptured WebGPU errors + device-lost messages (count survives clearErrorRing). */
  errors: WasmErrorRing;
}

export interface RendererMetrics {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
}

export interface RendererDiagnostics {
  rendererType: RendererType;
  /** TS WebGPU backend: rendering on the page or in the render worker (#1314). */
  renderThread?: 'main' | 'worker';
  /** Page ↔ render-worker input path: shared memory (isolated pages) or messages. */
  inputChannel?: 'sab' | 'postMessage';
  crossOriginIsolated?: boolean;
  metrics: RendererMetrics;
  timestamp: string;
  /** Last published boot-probe breadcrumb (also on window.webgpuProbe). */
  webgpuProbe?: WebGpuProbeSerializable;
  wasm?: WASMDiagnostics;
  /** TS WebGPU device-loss recovery (state, attempts, last loss / failure). */
  deviceRecovery?: DeviceRecoveryStatus;
  /** Renderer device registry generation: bumps on every device publish / clear (#1395). */
  deviceGeneration?: number;
  /** GPUDevices alive on the page plus in the current render worker; 1 while rendering. */
  liveGpuDevices?: number;
  webgpu?: {
    initialized: boolean;
    fps: number;
    adapterInfo: string;
    adapterAttemptLabel: string | null;
    graph?: GraphRunReport | null;
    gpuChores?: GpuChoresBreadcrumbs;
    /** Submits / bind groups per frame (#1314: steady state is one submit). */
    frameStats?: FrameStats;
    /** Smoothed per-pass GPU ms (#1314 WP-4); empty until timestamps resolve. */
    passTimings?: PassTiming[];
    timing?: { source: 'gpu-timestamp' | 'wall-clock'; periodNs: number; profiledPasses: number; overflow: number };
    /** Demoted opt-in graph nodes, `${slot}:${nodeId}` → scale. */
    nodeScales?: Record<string, number>;
    /** Video ingest path + counters (#1314 WP-2). */
    video?: VideoIngestStats;
    /** Applied canvas color state (requested vs. accepted color space / tone mapping). */
    canvas?: import('./webgpuBootProbe').CanvasColorState | null;
    /** Uncaptured GPU errors in the render worker (page hooks cannot see that device). */
    gpuErrors?: string[];
    /** Input currently held by the renderer (worker mode; proves the input channel). */
    input?: { mouse: [number, number]; mouseDown: boolean; audio: [number, number, number]; slot0: number[] } | null;
    /** Layer compositor (#1512): stack layers allocated, their bytes, composites last frame. */
    compositor?: { layers: number; bytes: number; compositesLastFrame: number };
    /** shader-f16 (#1512): supported, half path on, per-shader compiled precision. */
    shaderPrecision?: import('./WebGPURenderer').ShaderPrecisionInfo;
    /** Direct-to-swapchain present (bgra8unorm-storage, #1512): available / active / why not. */
    directPresent?: import('./WebGPURenderer').DirectPresentStatus;
  };
}
