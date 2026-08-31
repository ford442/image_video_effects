/**
 * webgpuDevicePolicy.ts
 *
 * TypeScript mirror of wasm_renderer/device.cpp defensive policy: adapter fallback
 * ladder, limit validation, and explicit requiredLimits on requestDevice().
 *
 * Cross-reference: wasm_renderer/device.cpp
 *   - ADAPTER_ATTEMPT_LADDER / adapter request loop
 *   - CheckLimit table (adapter + device post-creation)
 *   - requiredLimits seeding on wgpuAdapterRequestDevice
 *
 * Keep MINIMUM_COMPUTE_LIMITS in sync with src/contracts/webgpu_limits.json and
 * device.cpp CheckLimit + requiredLimits.
 * See docs/BINDING_CONTRACT.md for the full bind-group + device policy contract.
 */

import webgpuLimitsContract from '../contracts/webgpu_limits.json';
import { UNIFORM_BUFFER_LAYOUT } from './types';

/**
 * Minimum limits implied by the 14-entry compute bind group (bindings 0–13).
 * Source of truth: src/contracts/webgpu_limits.json (sync-checked in CI).
 *
 * maxTextureDimension2D is the comfortable floor (8192), never derived from
 * canvas max(w,h), maxBufferSize, pixel count, or a mis-ordered init pointer.
 */
export const MINIMUM_COMPUTE_LIMITS = {
  ...webgpuLimitsContract.minimumComputeLimits,
  // Runtime guard: JSON value must match sizeof(Uniforms) in device.cpp
  maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE,
} as const;

export type AdapterContractOptions = {
  /** @deprecated Unused for maxTextureDimension2D (fixed 8192 floor). Kept for call-site compat. */
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

/** Four-step ladder matching C++ ADAPTER_ATTEMPT_LADDER in device.cpp. */
export const ADAPTER_ATTEMPT_LADDER: readonly AdapterAttempt[] = [
  { powerPreference: 'high-performance', forceFallbackAdapter: false, label: 'HighPerformance' },
  { powerPreference: undefined, forceFallbackAdapter: false, label: 'Undefined' },
  { powerPreference: 'low-power', forceFallbackAdapter: false, label: 'LowPower' },
  { powerPreference: undefined, forceFallbackAdapter: true, label: 'Undefined+forceFallback' },
] as const;

type LimitCheck = {
  name: keyof GPUSupportedLimits;
  required: number;
};

const LIMIT_CHECKS: LimitCheck[] = [
  { name: 'maxTextureDimension2D', required: MINIMUM_COMPUTE_LIMITS.maxTextureDimension2D },
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
 * Build requiredLimits for requestDevice() — mirrors device.cpp requiredLimits seeding.
 * `maxCanvasDim` is accepted for call-site compatibility but does not drive
 * maxTextureDimension2D (fixed comfortable floor from the contract).
 */
export function buildRequiredLimits(_maxCanvasDim?: number): GPUDeviceDescriptor['requiredLimits'] {
  return {
    ...MINIMUM_COMPUTE_LIMITS,
  };
}

/**
 * Validate adapter.limits against the compute bind contract before device creation
 * (device.cpp CheckLimit table).
 */
export function assertAdapterMeetsContract(
  adapter: GPUAdapter,
  _opts?: AdapterContractOptions,
): AdapterContractResult {
  const failures: string[] = [];
  const limits = adapter.limits;

  for (const check of LIMIT_CHECKS) {
    const actual = limits[check.name] as number;
    if (actual < check.required) {
      failures.push(`${check.name}: need >= ${check.required}, adapter has ${actual}`);
    }
  }

  if (failures.length === 0) {
    return { ok: true, message: 'Adapter meets Pixelocity compute contract', failures: [] };
  }

  return {
    ok: false,
    message:
      'GPU adapter does not meet minimum WebGPU limits for Pixelocity\'s 14-entry ' +
      'compute bind group contract (bindings 0–13). Try ?renderer=js or a different GPU/browser.',
    failures,
  };
}

export type AdapterAttemptLog = {
  label: string;
  powerPreference?: GPUPowerPreference;
  forceFallbackAdapter: boolean;
  adapterPresent: boolean;
  error?: string;
};

/**
 * Request an adapter using the 4-step fallback ladder (device.cpp requestAdapterWithFallback).
 */
export async function requestAdapterWithFallback(
  gpu: GPU,
  attempts: readonly AdapterAttempt[] = ADAPTER_ATTEMPT_LADDER,
): Promise<{
  adapter: GPUAdapter | null;
  attemptLabel: string | null;
  attemptLogs: AdapterAttemptLog[];
}> {
  const attemptLogs: AdapterAttemptLog[] = [];

  for (const attempt of attempts) {
    const options: GPURequestAdapterOptions = {
      forceFallbackAdapter: attempt.forceFallbackAdapter,
    };
    if (attempt.powerPreference !== undefined) {
      options.powerPreference = attempt.powerPreference;
    }

    const pref = attempt.powerPreference ?? 'default';
    console.log(
      `[WebGPU] Requesting adapter (attempt=${attempt.label}, powerPreference=${pref}, ` +
      `forceFallbackAdapter=${attempt.forceFallbackAdapter})`,
    );

    let adapter: GPUAdapter | null = null;
    let error: string | undefined;
    try {
      adapter = await gpu.requestAdapter(options);
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
      console.warn(`[WebGPU] requestAdapter failed on ${attempt.label}:`, error);
    }

    const log: AdapterAttemptLog = {
      label: attempt.label,
      powerPreference: attempt.powerPreference,
      forceFallbackAdapter: attempt.forceFallbackAdapter,
      adapterPresent: !!adapter,
      error: adapter ? undefined : error ?? 'requestAdapter returned null',
    };
    attemptLogs.push(log);

    if (adapter) {
      console.log(
        `[WebGPU] Obtained adapter on attempt: ${attempt.label} | ` +
        `${formatAdapterLimitsSummary(adapter)}`,
      );
      return { adapter, attemptLabel: attempt.label, attemptLogs };
    }
  }

  return { adapter: null, attemptLabel: null, attemptLogs };
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
