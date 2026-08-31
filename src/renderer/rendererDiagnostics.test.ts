import { buildRendererDiagnostics } from './rendererDiagnostics';
import type { GraphRunReport } from './GraphRunner';

describe('buildRendererDiagnostics', () => {
  it('forwards GraphRunReport from the WebGPU renderer', () => {
    const graph: GraphRunReport = {
      shaderId: 'ripple-tank',
      requested: 7,
      executed: 4,
      truncated: 3,
      cap: 4,
      errors: [],
    };
    const renderer = {
      initialized: true,
      loadShader: async () => true,
      setSlotShader: () => {},
      updateSlotParams: () => {},
      getFPS: () => 60,
      getAdapterSummary: () => 'test-adapter',
      getAdapterAttemptLabel: () => 'base',
      getLastGraphReport: () => graph,
    };
    const diags = buildRendererDiagnostics(
      'webgpu',
      { fps: 60, frameTime: 16, agentCount: 0, isWASM: false },
      renderer as never,
      null,
    );
    expect(diags.webgpu?.graph).toEqual(graph);
  });

  it('forwards gpu-chores breadcrumbs from the WebGPU renderer', () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [{ brand: 'Chromium', version: '120' }],
      attempts: [],
    };
    const renderer = {
      initialized: true,
      loadShader: async () => true,
      setSlotShader: () => {},
      updateSlotParams: () => {},
      getFPS: () => 60,
      getAdapterSummary: () => 'test-adapter',
      getAdapterAttemptLabel: () => 'base',
      getLastGraphReport: () => null,
      getGpuChoresBreadcrumbs: () => ({
        gpuComputeAvailable: false,
        reason: 'kill switch ?no_gpu_compute',
        lastOp: 'auto_exposure' as const,
        backend: 'ts' as const,
        sourceGain: 'skipped-physics' as const,
        classifyPreview: null,
        autoUniforms: {
          lumaMin: 0.1,
          lumaMax: 0.9,
          lumaMean: 0.18,
          exposureGain: 1,
          exposureEv: 0,
        },
      }),
    };
    const diags = buildRendererDiagnostics(
      'webgpu',
      { fps: 60, frameTime: 16, agentCount: 0, isWASM: false },
      renderer as never,
      null,
    );
    expect(diags.webgpu?.gpuChores?.gpuComputeAvailable).toBe(false);
    expect(diags.webgpu?.gpuChores?.reason).toContain('no_gpu_compute');
    expect(diags.webgpu?.gpuChores?.backend).toBe('ts');
    expect(diags.webgpu?.gpuChores?.sourceGain).toBe('skipped-physics');
    expect(diags.webgpuProbe?.ok).toBe(true);
    delete window.webgpuProbe;
  });
});
