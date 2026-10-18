import {
  formatAdapterIdentity,
  inferAdapterGpuType,
  readAdapterIdentity,
  UNKNOWN_ADAPTER_IDENTITY,
  type AdapterIdentity,
} from './adapterIdentity';
import { allowsFullWorkingSize, MIN_MAX_BUFFER_SIZE_FOR_FULL } from './vramBudget';

function adapterWithInfo(info: Record<string, unknown> | undefined, extra: Record<string, unknown> = {}): GPUAdapter {
  return { info, ...extra } as unknown as GPUAdapter;
}

function identity(overrides: Partial<AdapterIdentity>): AdapterIdentity {
  return { ...UNKNOWN_ADAPTER_IDENTITY, ...overrides };
}

describe('readAdapterIdentity', () => {
  it('reads vendor / architecture / device / description / isFallbackAdapter from adapter.info', () => {
    const id = readAdapterIdentity(
      adapterWithInfo({
        vendor: 'nvidia',
        architecture: 'ampere',
        device: '0x2484',
        description: 'NVIDIA GeForce RTX 3070',
        isFallbackAdapter: false,
      }),
    );
    expect(id).toEqual({
      vendor: 'nvidia',
      architecture: 'ampere',
      device: '0x2484',
      description: 'NVIDIA GeForce RTX 3070',
      isFallbackAdapter: false,
    });
  });

  it('falls back to adapter.isFallbackAdapter for browsers before it moved to info', () => {
    const id = readAdapterIdentity(adapterWithInfo({ vendor: 'google' }, { isFallbackAdapter: true }));
    expect(id.isFallbackAdapter).toBe(true);
  });

  it('returns empty strings when info is missing', () => {
    expect(readAdapterIdentity(adapterWithInfo(undefined))).toEqual(UNKNOWN_ADAPTER_IDENTITY);
    expect(readAdapterIdentity(null)).toEqual(UNKNOWN_ADAPTER_IDENTITY);
  });

  it('keeps an explicit adapter type when the implementation reports one', () => {
    expect(readAdapterIdentity(adapterWithInfo({ adapterType: 'DiscreteGPU' })).adapterType).toBe('DiscreteGPU');
    expect(readAdapterIdentity(adapterWithInfo({ type: 'integrated GPU' })).adapterType).toBe('integrated GPU');
  });
});

describe('inferAdapterGpuType', () => {
  it.each([
    [{ vendor: 'nvidia', architecture: 'ampere' }, 'discrete'],
    [{ vendor: 'nvidia', architecture: 'pascal' }, 'discrete'],
    [{ vendor: 'amd', architecture: 'rdna-3' }, 'discrete'],
    [{ vendor: 'amd', architecture: 'rdna-2', description: 'AMD Radeon(TM) Graphics' }, 'integrated'],
    [{ vendor: 'amd', architecture: 'rdna-3', description: 'AMD Radeon 780M' }, 'integrated'],
    [{ vendor: 'intel', architecture: 'gen-12lp' }, 'integrated'],
    [{ vendor: 'intel', architecture: 'xe-hpg' }, 'discrete'],
    [{ vendor: 'apple', architecture: 'metal-3' }, 'integrated'],
    [{ vendor: 'google', architecture: 'swiftshader' }, 'cpu'],
    [{ vendor: 'nvidia', isFallbackAdapter: true }, 'cpu'],
    [{ vendor: 'mystery' }, 'unknown'],
    [{}, 'unknown'],
    [{ vendor: 'intel', adapterType: 'discrete GPU' }, 'discrete'],
  ] as Array<[Partial<AdapterIdentity>, string]>)('%j → %s', (fields, expected) => {
    expect(inferAdapterGpuType(identity(fields))).toBe(expected);
  });
});

describe('2048 gate from a browser-shaped adapter (#1395)', () => {
  const gateFor = (info: Record<string, unknown>) => {
    const id = readAdapterIdentity(adapterWithInfo(info));
    return allowsFullWorkingSize({
      maxBufferSize: MIN_MAX_BUFFER_SIZE_FOR_FULL,
      adapterGpuType: inferAdapterGpuType(id),
      adapterSummary: `Adapter attempt=HighPerformance | adapter: ${formatAdapterIdentity(id)}`,
      adapterIdentity: id,
    });
  };

  beforeEach(() => sessionStorage.clear());

  it('opens on a fat non-Pascal NVIDIA adapter that reports no adapter type', () => {
    expect(gateFor({ vendor: 'nvidia', architecture: 'ampere' })).toBe(true);
  });

  it('blocks Pascal by architecture alone (description is often empty in browsers)', () => {
    expect(gateFor({ vendor: 'nvidia', architecture: 'pascal' })).toBe(false);
  });

  it('blocks a fallback adapter even when its vendor looks discrete', () => {
    expect(gateFor({ vendor: 'nvidia', architecture: 'ampere', isFallbackAdapter: true })).toBe(false);
  });

  it('stays closed on integrated adapters', () => {
    expect(gateFor({ vendor: 'intel', architecture: 'gen-12lp' })).toBe(false);
  });
});
