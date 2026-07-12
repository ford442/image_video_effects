/**
 * webgpuDevicePolicy.ts
 *
 * TypeScript mirror of wasm_renderer/renderer.cpp CreateDevice() defensive policy
 * (~lines 320–545): adapter fallback ladder, limit validation, and explicit
 * requiredLimits on requestDevice().
 *
 * Cross-reference: wasm_renderer/renderer.cpp
 *   - Adapter ladder: lines 320–337 (AdapterAttempt[])
 *   - CheckLimit validation: lines 458–470
 *   - requiredLimits seeding: lines 522–538
 *
 * Keep MINIMUM_COMPUTE_LIMITS in sync with the C++ CheckLimit table and
 * requiredLimits block above.
 */

import { UNIFORM_BUFFER_LAYOUT } from './types';

/** Minimum limits implied by the 13-binding compute shader contract (AGENTS.md). */
export const MINIMUM_COMPUTE_LIMITS = {
  maxBindingsPerBindGroup: 13,
  maxSampledTexturesPerShaderStage: 3,
  maxSamplersPerShaderStage: 3,
  maxStorageTexturesPerShaderStage: 4,
  maxStorageBuffersPerShaderStage: 2,
  maxUniformBuffersPerShaderStage: 1,
  maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE, // sizeof(Uniforms) in C++
  maxComputeWorkgroupSizeX: 16,
  maxComputeWorkgroupSizeY: 16,
  maxComputeInvocationsPerWorkgroup: 256,
} as const;

export type AdapterContractOptions = {
  maxCanvasDim: number;
};

export type AdapterContractResult = {
  ok: boolean;
  message: string;
  failures: string[];
};

export type AdapterAttempt = {
  powerPreference?: GPUPowerPreference;
  forceFallbackAdapter: boolean;
  label: string;
};

/** Four-step ladder matching C++ AdapterAttempt[] (renderer.cpp ~332–337). */
export const ADAPTER_ATTEMPT_LADDER: readonly AdapterAttempt[] = [
  { powerPreference: 'high-performance', forceFallbackAdapter: false, label: 'HighPerformance' },
  { powerPreference: undefined, forceFallbackAdapter: false, label: 'Undefined' },
  { powerPreference: 'low-power', forceFallbackAdapter: false, label: 'LowPower' },
  { powerPreference: undefined, forceFallbackAdapter: true, label: 'Undefined+forceFallback' },
] as const;

type LimitCheck = {
  name: keyof GPUSupportedLimits;
  required: number;
  canvasScaled?: boolean;
};

const LIMIT_CHECKS: LimitCheck[] = [
  { name: 'maxTextureDimension2D', required: 0, canvasScaled: true },
  { name: 'maxBindingsPerBindGroup', required: MINIMUM_COMPUTE_LIMITS.maxBindingsPerBindGroup },
  { name: 'maxSampledTexturesPerShaderStage', required: MINIMUM_COMPUTE_LIMITS.maxSampledTexturesPerShaderStage },
  { name: 'maxSamplersPerShaderStage', required: MINIMUM_COMPUTE_LIMITS.maxSamplersPerShaderStage },
  { name: 'maxStorageTexturesPerShaderStage', required: MINIMUM_COMPUTE_LIMITS.maxStorageTexturesPerShaderStage },
  { name: 'maxStorageBuffersPerShaderStage', required: MINIMUM_COMPUTE_LIMITS.maxStorageBuffersPerShaderStage },
  { name: 'maxUniformBuffersPerShaderStage', required: MINIMUM_COMPUTE_LIMITS.maxUniformBuffersPerShaderStage },
  { name: 'maxComputeWorkgroupSizeX', required: MINIMUM_COMPUTE_LIMITS.maxComputeWorkgroupSizeX },
  { name: 'maxComputeWorkgroupSizeY', required: MINIMUM_COMPUTE_LIMITS.maxComputeWorkgroupSizeY },
  { name: 'maxComputeInvocationsPerWorkgroup', required: MINIMUM_COMPUTE_LIMITS.maxComputeInvocationsPerWorkgroup },
];

/**
 * Build requiredLimits for requestDevice(), mirroring C++ requiredLimits seeding
 * (renderer.cpp ~527–538). Only requests the minimums we need; other fields stay
 * at adapter defaults.
 */
export function buildRequiredLimits(maxCanvasDim: number): GPUDeviceDescriptor['requiredLimits'] {
  return {
    maxTextureDimension2D: maxCanvasDim,
    ...MINIMUM_COMPUTE_LIMITS,
  };
}

function requiredForCheck(check: LimitCheck, maxCanvasDim: number): number {
  return check.canvasScaled ? maxCanvasDim : check.required;
}

/**
 * Validate adapter.limits against the 13-binding compute contract before device
 * creation (renderer.cpp CheckLimit table ~461–470).
 */
export function assertAdapterMeetsContract(
  adapter: GPUAdapter,
  opts: AdapterContractOptions,
): AdapterContractResult {
  const failures: string[] = [];
  const limits = adapter.limits;

  for (const check of LIMIT_CHECKS) {
    const required = requiredForCheck(check, opts.maxCanvasDim);
    const actual = limits[check.name] as number;
    if (actual < required) {
      failures.push(`${check.name}: need >= ${required}, adapter has ${actual}`);
    }
  }

  if (failures.length === 0) {
    return { ok: true, message: 'Adapter meets Pixelocity compute contract', failures: [] };
  }

  return {
    ok: false,
    message:
      'GPU adapter does not meet minimum WebGPU limits for Pixelocity\'s 13-binding ' +
      'compute shader contract. Try ?renderer=js or a different GPU/browser.',
    failures,
  };
}

/**
 * Request an adapter using the 4-step fallback ladder (renderer.cpp ~342–399).
 */
export async function requestAdapterWithFallback(
  gpu: GPU,
  attempts: readonly AdapterAttempt[] = ADAPTER_ATTEMPT_LADDER,
): Promise<{ adapter: GPUAdapter | null; attemptLabel: string | null }> {
  for (const attempt of attempts) {
    const options: GPURequestAdapterOptions = {
      forceFallbackAdapter: attempt.forceFallbackAdapter,
    };
    if (attempt.powerPreference !== undefined) {
      options.powerPreference = attempt.powerPreference;
    }

    console.log(
      `[WebGPU] Requesting adapter (powerPreference=${attempt.label}, ` +
      `forceFallbackAdapter=${attempt.forceFallbackAdapter})`,
    );

    const adapter = await gpu.requestAdapter(options);
    if (adapter) {
      console.log(`[WebGPU] Obtained adapter on attempt: ${attempt.label}`);
      return { adapter, attemptLabel: attempt.label };
    }
  }

  return { adapter: null, attemptLabel: null };
}

/** Human-readable summary of adapter limits for diagnostics. */
export function formatAdapterLimitsSummary(adapter: GPUAdapter): string {
  const l = adapter.limits;
  return (
    `maxTex2D=${l.maxTextureDimension2D} storageTex=${l.maxStorageTexturesPerShaderStage} ` +
    `sampledTex=${l.maxSampledTexturesPerShaderStage} computeInvocations=${l.maxComputeInvocationsPerWorkgroup}`
  );
}

/** Log adapter optional features (mirrors C++ feature printf ~487–490). */
export function logAdapterFeatures(adapter: GPUAdapter): void {
  const f32Filter = adapter.features.has('float32-filterable');
  const f32Blend = adapter.features.has('float32-blendable' as GPUFeatureName);
  const bgra8Storage = adapter.features.has('bgra8unorm-storage' as GPUFeatureName);
  console.log(
    `[WebGPU] Adapter features: Float32Filterable=${f32Filter ? 'yes' : 'no'} ` +
    `Float32Blendable=${f32Blend ? 'yes' : 'no'} BGRA8UnormStorage=${bgra8Storage ? 'yes' : 'no'}`,
  );
}
