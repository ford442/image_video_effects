import { checkWgslGatePreview } from './wgslGatePreview';
import { assembleComputeShader } from '../services/shadertoyToPixelocity';

describe('wgslGatePreview', () => {
  it('passes canonical compute shader', () => {
    const wgsl = assembleComputeShader('outColor = vec4<f32>(uv, 1.0);');
    const result = checkWgslGatePreview(wgsl);
    expect(result.ok).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('fails when bindings are missing', () => {
    const result = checkWgslGatePreview('@compute @workgroup_size(16, 16, 1)\nfn main() {}');
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes('Missing binding'))).toBe(true);
  });

  it('warns on 2-arg workgroup size when bindings present', () => {
    const wgsl = assembleComputeShader('outColor = vec4<f32>(1.0);').replace(
      '@workgroup_size(16, 16, 1)',
      '@workgroup_size(16, 16)'
    );
    const result = checkWgslGatePreview(wgsl);
    expect(result.warnings.some((w) => w.includes('workgroup_size'))).toBe(true);
    expect(result.ok).toBe(true);
  });
});
