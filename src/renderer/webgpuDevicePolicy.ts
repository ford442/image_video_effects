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
 * device.cpp CheckLimit + requiredLimits. TypeScript validates and requests by
 * limits tier (#1512): BASE_LIMITS are the real requirements, and only what
 * exceeds the adapter feature level's spec default is requested.
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

/** WebGPU feature level an adapter was requested at (the compat rung is 'compatibility'). */
export type FeatureLevel = 'core' | 'compatibility';

/** Probed limits tiers, low to high (webgpu_limits.json limitsTiers). */
export type LimitsTier = 'base' | 'deep-workgroup' | 'big-buffer';

type ContractLimitName = keyof typeof webgpuLimitsContract.minimumComputeLimits;

/** Spec defaults per feature level for the contract's limits: requesting at or below these is a no-op. */
export const SPEC_DEFAULT_LIMITS: Record<FeatureLevel, Record<ContractLimitName, number>> =
  webgpuLimitsContract.specDefaults;

/**
 * The real requirements (`base` tier): the bind group's counts, the Uniforms size and the
 * 16×16 catalog workgroup. maxTextureDimension2D is the minimum viable 4096 (the canvas
 * and working pool are ≤ 2048), not the 8192 comfortable floor C++ keeps.
 */
export const BASE_LIMITS: Record<ContractLimitName, number> = {
  ...MINIMUM_COMPUTE_LIMITS,
  maxTextureDimension2D: webgpuLimitsContract.limitsTiers.base.maxTextureDimension2D,
};

/** Requested up to this when the feature level's default is lower (compat: 4096). */
export const COMFORTABLE_MAX_TEXTURE_DIMENSION_2D =
  webgpuLimitsContract.limitsTiers.base.comfortableMaxTextureDimension2D;

/** maxBufferSize of the `big-buffer` tier (the 2048 working-size gate, vramBudget.ts). */
export const BIG_BUFFER_MIN_BYTES = webgpuLimitsContract.limitsTiers['big-buffer'].maxBufferSize;

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
  /** Absent = core. The last rung asks for a compatibility adapter (#1512). */
  featureLevel?: FeatureLevel;
};

/** The compatibility rung: Android GL ES and older Chromebooks get an adapter here. */
export const COMPAT_ADAPTER_ATTEMPT: AdapterAttempt = {
  powerPreference: undefined,
  forceFallbackAdapter: false,
  featureLevel: 'compatibility',
  label: 'Compatibility',
};

/**
 * The four core rungs match C++ ADAPTER_ATTEMPT_LADDER in device.cpp; the TS ladder adds
 * the compatibility rung last (the WASM backend has no compat path: it stays frozen).
 */
export const ADAPTER_ATTEMPT_LADDER: readonly AdapterAttempt[] = [
  { powerPreference: 'high-performance', forceFallbackAdapter: false, label: 'HighPerformance' },
  { powerPreference: undefined, forceFallbackAdapter: false, label: 'Undefined' },
  { powerPreference: 'low-power', forceFallbackAdapter: false, label: 'LowPower' },
  { powerPreference: undefined, forceFallbackAdapter: true, label: 'Undefined+forceFallback' },
  COMPAT_ADAPTER_ATTEMPT,
] as const;

/**
 * `?feature_level=compatibility` starts at the compat rung (tests, and checking that the
 * catalog loads on a compat-only adapter on a machine that has a core one).
 */
export function resolveAdapterLadder(search = ''): readonly AdapterAttempt[] {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  return params.get('feature_level') === 'compatibility' ? [COMPAT_ADAPTER_ATTEMPT] : ADAPTER_ATTEMPT_LADDER;
}

/**
 * A device runs under compatibility validation when its rung asked for it and it was not
 * granted core-features-and-limits (Chromium hands a core-capable adapter to a compat
 * request, but the device stays compat unless that feature is requested).
 */
export function isCompatibilityDevice(device: GPUDevice, featureLevel: FeatureLevel | undefined): boolean {
  return featureLevel === 'compatibility' && !device.features.has('core-features-and-limits' as GPUFeatureName);
}

type LimitCheck = {
  name: ContractLimitName;
  required: number;
};

/** The `base` tier, validated against the adapter (real requirements, see BASE_LIMITS). */
const LIMIT_CHECKS: LimitCheck[] = (Object.keys(BASE_LIMITS) as ContractLimitName[]).map((name) => ({
  name,
  required: BASE_LIMITS[name],
}));

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
 * Build requiredLimits for requestDevice(). `maxCanvasDim` is accepted for call-site
 * compatibility but never drives maxTextureDimension2D.
 *
 * Only limits that change something are requested (#1512): a base limit when it exceeds
 * the spec default of `featureLevel` (a core device requests none; a compatibility
 * device requests 256 invocations and up to the comfortable 8192 texture size), the
 * deep-workgroup limits when the adapter offers them, and the adapter's buffer-size
 * limits. WebGPU never grants more than requested, so omitting `adapterLimits` caps
 * the device at 256 invocations and 256 MiB buffers even on an adapter with more.
 */
export function buildRequiredLimits(
  _maxCanvasDim?: number,
  adapterLimits?: Partial<WorkgroupLimits & BufferSizeLimits & Pick<GPUSupportedLimits, 'maxTextureDimension2D'>>,
  featureLevel: FeatureLevel = 'core',
): GPUDeviceDescriptor['requiredLimits'] {
  return {
    ...baseLimitRequest(featureLevel, adapterLimits?.maxTextureDimension2D),
    ...(meetsDeepWorkgroupLimits(adapterLimits) ? DEEP_WORKGROUP_LIMITS : {}),
    ...bufferSizeRequest(adapterLimits),
  };
}

/** Base-tier limits above the feature level's spec default (empty on core). */
export function baseLimitRequest(featureLevel: FeatureLevel, adapterMaxTexture2D?: number): Partial<Record<ContractLimitName, number>> {
  const defaults = SPEC_DEFAULT_LIMITS[featureLevel];
  const out: Partial<Record<ContractLimitName, number>> = {};
  for (const name of Object.keys(BASE_LIMITS) as ContractLimitName[]) {
    if (BASE_LIMITS[name] > defaults[name]) out[name] = BASE_LIMITS[name];
  }
  if (defaults.maxTextureDimension2D < COMFORTABLE_MAX_TEXTURE_DIMENSION_2D && adapterMaxTexture2D !== undefined) {
    const wanted = Math.min(adapterMaxTexture2D, COMFORTABLE_MAX_TEXTURE_DIMENSION_2D);
    if (wanted > defaults.maxTextureDimension2D) out.maxTextureDimension2D = wanted;
  }
  return out;
}

/** Every tier the granted device limits reach, low to high (window.webgpuProbe.limitsTiers). */
export function resolveLimitsTiers(limits: Partial<GPUSupportedLimits> | undefined): LimitsTier[] {
  if (!limits) return [];
  const tiers: LimitsTier[] = [];
  const meetsBase = (Object.keys(BASE_LIMITS) as ContractLimitName[]).every(
    (name) => ((limits[name] as number | undefined) ?? 0) >= BASE_LIMITS[name],
  );
  if (meetsBase) tiers.push('base');
  if (meetsDeepWorkgroupLimits(limits)) tiers.push('deep-workgroup');
  if ((limits.maxBufferSize ?? 0) >= BIG_BUFFER_MIN_BYTES) tiers.push('big-buffer');
  return tiers;
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
    const actual = limits[check.name];
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
  const has = (name: string) => (adapter.features.has(name as GPUFeatureName) ? 'yes' : 'no');
  console.log(
    `[WebGPU] Adapter features: Float32Filterable=${has('float32-filterable')} ` +
    `Float32Blendable=${has('float32-blendable')} BGRA8UnormStorage=${has('bgra8unorm-storage')} ` +
    `ShaderF16=${has('shader-f16')} DualSourceBlending=${has('dual-source-blending')}`,
  );
}
