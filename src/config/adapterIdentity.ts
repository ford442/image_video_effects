/**
 * Adapter identity read from `GPUAdapter.info` (#1395).
 *
 * Browsers expose vendor / architecture (and often an empty device / description)
 * but no adapter type, so `adapterGpuType` is inferred from the identity. A wrong
 * "discrete" guess is caught by the history OOM ladder (stay at 1024 this tab).
 * See docs/FORMAT_TIERS.md.
 */

import type { AdapterGpuType } from './formatPolicy';

export interface AdapterIdentity {
  vendor: string;
  architecture: string;
  device: string;
  description: string;
  isFallbackAdapter: boolean;
  /**
   * Explicit adapter type when the implementation reports one (Dawn native, tests);
   * browsers leave it undefined.
   */
  adapterType?: string;
}

export const UNKNOWN_ADAPTER_IDENTITY: AdapterIdentity = {
  vendor: '',
  architecture: '',
  device: '',
  description: '',
  isFallbackAdapter: false,
};

type AdapterInfoLike = Partial<GPUAdapterInfo> & {
  isFallbackAdapter?: boolean;
  adapterType?: string;
  type?: string;
};

/** Read `adapter.info`; `adapter.isFallbackAdapter` covers browsers from before it moved to info. */
export function readAdapterIdentity(adapter: GPUAdapter | null | undefined): AdapterIdentity {
  const legacy = adapter as unknown as { info?: AdapterInfoLike; isFallbackAdapter?: boolean } | null;
  const info = legacy?.info;
  const adapterType = info?.adapterType ?? info?.type;
  return {
    vendor: info?.vendor ?? '',
    architecture: info?.architecture ?? '',
    device: info?.device ?? '',
    description: info?.description ?? '',
    isFallbackAdapter: !!(info?.isFallbackAdapter ?? legacy?.isFallbackAdapter),
    ...(adapterType ? { adapterType } : {}),
  };
}

function parseExplicitType(adapterType: string | undefined): AdapterGpuType | null {
  switch (adapterType) {
    case 'discrete':
    case 'discrete GPU':
    case 'DiscreteGPU':
      return 'discrete';
    case 'integrated':
    case 'integrated GPU':
    case 'IntegratedGPU':
      return 'integrated';
    case 'cpu':
    case 'CPU':
      return 'cpu';
    default:
      return null;
  }
}

/** AMD APU graphics: "AMD Radeon(TM) Graphics", "Radeon Vega 8 Graphics", "Radeon 780M". */
const AMD_INTEGRATED = /radeon(\s*\(tm\))?\s+graphics|vega\s*\d+\s+graphics|\b[678][0-9]0m\b/i;
/** Intel discrete: Arc (Alchemist xe-hpg, Battlemage xe2-hpg). */
const INTEL_DISCRETE = /xe-?hpg|xe2-?hpg|\barc\b/i;

/**
 * Best-effort adapter type from identity. Only the vendors and architectures we can
 * place with confidence return discrete / integrated; everything else is unknown.
 */
export function inferAdapterGpuType(id: AdapterIdentity): AdapterGpuType {
  const explicit = parseExplicitType(id.adapterType);
  if (explicit) return explicit;
  if (id.isFallbackAdapter) return 'cpu';
  const vendor = id.vendor.toLowerCase();
  const detail = `${id.architecture} ${id.device} ${id.description}`;
  if (/swiftshader|llvmpipe|lavapipe|warp/i.test(`${vendor} ${detail}`)) return 'cpu';
  switch (vendor) {
    case 'nvidia':
      return 'discrete';
    case 'amd':
    case 'ati':
      return AMD_INTEGRATED.test(detail) ? 'integrated' : 'discrete';
    case 'intel':
      return INTEL_DISCRETE.test(detail) ? 'discrete' : 'integrated';
    case 'apple':
    case 'qualcomm':
    case 'arm':
    case 'imagination':
      return 'integrated';
    default:
      return 'unknown';
  }
}

/** `vendor=… arch=… device=… desc=… fallback=…` for adapterSummary and logs. */
export function formatAdapterIdentity(id: AdapterIdentity): string {
  return (
    `vendor=${id.vendor || '?'} arch=${id.architecture || '?'}`
    + ` device=${id.device || '?'} desc=${id.description || '?'}`
    + ` fallback=${id.isFallbackAdapter ? 'yes' : 'no'}`
  );
}
