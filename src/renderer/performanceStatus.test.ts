import {
  applyQualityPolicy,
  buildPerformanceStatus,
  createPerformancePolicyState,
  registerFp32Requirement,
  releaseFp32Requirement,
} from './performanceStatus';

describe('performanceStatus', () => {
  it('pins rgba32float when an FP32-required shader is registered', () => {
    const state = createPerformancePolicyState();
    applyQualityPolicy(state, 'balanced', { supportsDeepWorkgroup: true });
    expect(state.performancePolicy.colorFormat).not.toBe('rgba32float');

    registerFp32Requirement(state, 'wave-equation');
    applyQualityPolicy(state, 'balanced', { supportsDeepWorkgroup: true });

    expect(state.fp32Pin.pinned).toBe(true);
    expect(state.fp32Pin.pinnedBy).toContain('wave-equation');
    expect(state.performancePolicy.colorFormat).toBe('rgba32float');
  });

  it('releases FP32 pin when shader requirement is removed', () => {
    const state = createPerformancePolicyState();
    registerFp32Requirement(state, 'ripple-tank');
    applyQualityPolicy(state, 'balanced', { supportsDeepWorkgroup: true });
    expect(state.fp32Pin.pinned).toBe(true);

    releaseFp32Requirement(state, 'ripple-tank');
    applyQualityPolicy(state, 'balanced', { supportsDeepWorkgroup: true });
    expect(state.fp32Pin.pinned).toBe(false);
  });

  it('surfaces pass budget and format tier in performance status', () => {
    const state = createPerformancePolicyState();
    applyQualityPolicy(state, 'ultra', { supportsDeepWorkgroup: true });
    const status = buildPerformanceStatus(
      state,
      'webgpu',
      () => 60,
      { scale: 1, scaled: { w: 2048, h: 2048 } },
    );
    expect(status.backend).toBe('webgpu');
    expect(status.maxPassesPerFrame).toBeGreaterThan(0);
    expect(status.requestedColorFormat).toBeDefined();
    expect(status.colorFormat).toBeDefined();
  });
});
