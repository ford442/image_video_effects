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
 * device.cpp CheckLimit + requiredLimits (the frozen C++ mirror). The TS policy
 * itself validates and requests the probed limits tier instead (#1512,
 * webgpu_limits.json limitsTiers): MINIMUM_COMPUTE_LIMITS only restates spec
 * defaults on a core adapter.
 * See docs/BINDING_CONTRACT.md for the full bind-group + device policy contract.
 */

import webgpuLimitsContract from '../contracts/webgpu_limits.json';
import { UNIFORM_BUFFER_LAYOUT } from './types';

/**
 * The C++ backend's minimum limits for the 14-entry compute bind group (bindings 0–13).
 * Source of truth: src/contracts/webgpu_limits.json (sync-checked in CI against
 * device.cpp). Every value is at or below the core spec default, so the TS boot
 * probe validates LIMITS_TIERS.base instead and never requests these (#1512).
 */
export const MINIMUM_COMPUTE_LIMITS = {
  ...webgpuLimitsContract.minimumComputeLimits,
  // Runtime guard: JSON value must match sizeof(Uniforms) in device.cpp
  maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE,
} as const;

export type AdapterContractOptions = {
  /** @deprecated Not used: maxTextureDimension2D is a fixed floor. Kept for call-site compat. */
  maxCanvasDim: number;
  /** The adapter came from the compatibility rung (diagnostics; the requirements are the same). */
  compat?: boolean;
};

export type AdapterContractResult = {
  ok: boolean;
  message: string;
  failures: string[];
};

export type AdapterAttempt = {
  powerPreference?: GPUPowerPreference;
  forceFallbackAdapter: boolean;
  /** 'compatibility' asks for a compat-mode adapter (GL ES / older GPUs; #1512). */
  featureLevel?: 'compatibility';
  label: string;
};

/**
 * The C++ ADAPTER_ATTEMPT_LADDER (device.cpp) plus a TS-only last rung (#1512):
 * `featureLevel: 'compatibility'`, so Android GL ES / older Chromebooks still get
 * an adapter. A browser that does not know featureLevel ignores it.
 */
export const ADAPTER_ATTEMPT_LADDER: readonly AdapterAttempt[] = [
  { powerPreference: 'high-performance', forceFallbackAdapter: false, label: 'HighPerformance' },
  { powerPreference: undefined, forceFallbackAdapter: false, label: 'Undefined' },
  { powerPreference: 'low-power', forceFallbackAdapter: false, label: 'LowPower' },
  { powerPreference: undefined, forceFallbackAdapter: true, label: 'Undefined+forceFallback' },
  { powerPreference: undefined, forceFallbackAdapter: false, featureLevel: 'compatibility', label: 'Compatibility' },
] as const;

// ── Limits tiers (#1512) ─────────────────────────────────────────────────────

export type LimitsTier = 'base' | 'deep-workgroup' | 'big-buffer';

type TierLimits = Partial<Record<keyof GPUSupportedLimits, number>>;

/** webgpu_limits.json limitsTiers: what the renderer really needs, per tier. */
export const LIMITS_TIERS: Record<LimitsTier, TierLimits> = {
  base: {
    ...webgpuLimitsContract.limitsTiers.base.limits,
    maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE,
  },
  'deep-workgroup': webgpuLimitsContract.limitsTiers['deep-workgroup'].limits,
  'big-buffer': webgpuLimitsContract.limitsTiers['big-buffer'].limits,
};

/** Spec defaults a device gets without asking, per feature level. */
export const SPEC_DEFAULT_LIMITS: Record<'core' | 'compatibility', TierLimits> = webgpuLimitsContract.specDefaults;

function meetsAll(limits: Partial<GPUSupportedLimits> | undefined, want: TierLimits): boolean {
  if (!limits) return false;
  return Object.entries(want).every(([name, value]) =>
    ((limits as Record<string, number | undefined>)[name] ?? 0) >= (value ?? 0));
}

/** Highest tier the limits reach: big-buffer needs deep-workgroup too. */
export function resolveLimitsTier(limits: Partial<GPUSupportedLimits> | undefined): LimitsTier {
  if (!meetsAll(limits, LIMITS_TIERS['deep-workgroup'])) return 'base';
  return meetsAll(limits, LIMITS_TIERS['big-buffer']) ? 'big-buffer' : 'deep-workgroup';
}

/**
 * The base tier. maxTextureDimension2D is a fixed floor (4096, the minimum viable
 * size), never scaled by a canvas size: a mis-ordered init once fed a heap pointer
 * (~79984) into the C++ check as a "canvas dimension".
 */
export function baseTierRequirements(): TierLimits {
  return { ...LIMITS_TIERS.base };
}

/** 32×32 / 1024-invocation limits requested when the adapter offers them (webgpu_limits.json). */
export const DEEP_WORKGROUP_LIMITS = webgpuLimitsContract.deepWorkgroupLimits;

type WorkgroupLimits = Pick<
  GPUSupportedLimits,
  'maxComputeWorkgroupSizeX' | 'maxComputeWorkgroupSizeY' | 'maxComputeInvocationsPerWorkgroup'
>;

/** True when `limits` reach every deepWorkgroupLimits value (device.cpp adapterDeepWorkgroup). */
export function meetsDeepWorkgroupLimits(limits: Partial<WorkgroupLimits> | undefined): boolean {
  if (!limits) return false;
  return (
    (limits.maxComputeWorkgroupSizeX ?? 0) >= DEEP_WORKGROUP_LIMITS.maxComputeWorkgroupSizeX
    && (limits.maxComputeWorkgroupSizeY ?? 0) >= DEEP_WORKGROUP_LIMITS.maxComputeWorkgroupSizeY
    && (limits.maxComputeInvocationsPerWorkgroup ?? 0) >= DEEP_WORKGROUP_LIMITS.maxComputeInvocationsPerWorkgroup
  );
}

/**
 * Build requiredLimits for requestDevice(): only what exceeds the spec default
 * for the adapter's feature level (#1512). A core device already has every base
 * limit, so a core request is just the deep-workgroup limits (when offered) and
 * the adapter's buffer sizes; a compatibility device additionally asks for the
 * base limits above the compat defaults (in practice 256 invocations per workgroup).
 *
 * WebGPU never grants more than requested, so omitting `adapterLimits` caps the
 * device at the defaults even on an adapter that offers more.
 */
export function buildRequiredLimits(
  _maxCanvasDim?: number,
  adapterLimits?: Partial<WorkgroupLimits & BufferSizeLimits>,
  options: { compat?: boolean } = {},
): GPUDeviceDescriptor['requiredLimits'] {
  const defaults = SPEC_DEFAULT_LIMITS[options.compat ? 'compatibility' : 'core'];
  const aboveDefault: Record<string, number> = {};
  for (const [name, value] of Object.entries(baseTierRequirements())) {
    if (value !== undefined && value > ((defaults as Record<string, number | undefined>)[name] ?? 0)) {
      aboveDefault[name] = value;
    }
  }
  return {
    ...aboveDefault,
    ...(meetsDeepWorkgroupLimits(adapterLimits) ? DEEP_WORKGROUP_LIMITS : {}),
    ...bufferSizeRequest(adapterLimits),
  };
}

/** Floors for the buffer-size limits (spec defaults, webgpu_limits.json bufferSizeLimits). */
export const BUFFER_SIZE_LIMIT_FLOORS = webgpuLimitsContract.bufferSizeLimits;

type BufferSizeLimits = Pick<GPUSupportedLimits, 'maxBufferSize' | 'maxStorageBufferBindingSize'>;

/**
 * Request the adapter's own buffer-size limits (never below the spec-default floor).
 * Without this the device keeps the 256 MiB default and the 2048 working-size gate
 * (`maxBufferSize >= 1 GiB`, src/config/vramBudget.ts) can never pass.
 */
function bufferSizeRequest(
  adapterLimits: Partial<BufferSizeLimits> | undefined,
): Partial<Record<keyof BufferSizeLimits, number>> {
  const out: Partial<Record<keyof BufferSizeLimits, number>> = {};
  for (const name of ['maxBufferSize', 'maxStorageBufferBindingSize'] as const) {
    const offered = adapterLimits?.[name];
    if (typeof offered === 'number' && offered > BUFFER_SIZE_LIMIT_FLOORS[name]) out[name] = offered;
  }
  return out;
}

/**
 * Validate adapter.limits against what the renderer actually needs (the base
 * limits tier) before device creation. Every base limit is within the core spec
 * defaults, so a conformant core adapter always passes; on the compatibility rung
 * this catches, e.g., a 128-invocation adapter that cannot run the 16×16 catalog.
 */
export function assertAdapterMeetsContract(
  adapter: GPUAdapter,
  opts?: AdapterContractOptions,
): AdapterContractResult {
  const failures: string[] = [];
  const limits = adapter.limits as unknown as Record<string, number>;

  void opts;
  for (const [name, required] of Object.entries(baseTierRequirements())) {
    const actual = limits[name];
    if (required !== undefined && typeof actual === 'number' && actual < required) {
      failures.push(`${name}: need >= ${required}, adapter has ${actual}`);
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
