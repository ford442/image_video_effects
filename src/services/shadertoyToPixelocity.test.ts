import {
  assembleComputeShader,
  extractMainImageGlsl,
  detectUnsupportedFeatures,
  generateShaderDefinitionDraft,
  buildFragmentShaderForTint,
} from './shadertoyToPixelocity';
import { checkWgslGatePreview } from '../utils/wgslGatePreview';
import {
  SAMPLE_PLASMA_GLSL,
  SAMPLE_TUNNEL_GLSL,
  SAMPLE_NOISE_GLSL,
  SAMPLE_PLASMA_WGSL_LOGIC,
  SAMPLE_TUNNEL_WGSL_LOGIC,
  SAMPLE_NOISE_WGSL_LOGIC,
} from './__fixtures__/shadertoy-samples';

describe('shadertoyToPixelocity', () => {
  it('extracts mainImage body from Shadertoy GLSL', () => {
    const parsed = extractMainImageGlsl(SAMPLE_PLASMA_GLSL);
    expect(parsed).not.toBeNull();
    expect(parsed!.body).toContain('fragColor = vec4');
    expect(parsed!.body).toContain('iResolution');
  });

  it('detects unsupported multi-buffer features', () => {
    const unsupported = detectUnsupportedFeatures('texture(iChannel1, uv)');
    expect(unsupported).toContain('multi-buffer (iChannel1-3)');
  });

  it('builds fragment shader wrapper for Tint', () => {
    const parsed = extractMainImageGlsl(SAMPLE_PLASMA_GLSL)!;
    const frag = buildFragmentShaderForTint(parsed.helpers, parsed.body);
    expect(frag).toContain('#version 450');
    expect(frag).toContain('void mainImage');
    expect(frag).toContain('void main()');
  });

  it('generates shader definition draft with audio mappings', () => {
    const draft = generateShaderDefinitionDraft('st-plasma', 'Test Plasma');
    expect(draft.params).toHaveLength(4);
    expect(draft.params[0].audio).toBe('bass');
    expect(draft.params[0].mapping).toBe('zoom_params.x');
  });

  describe('assembleComputeShader gate-clean samples', () => {
    const samples = [
      ['plasma', SAMPLE_PLASMA_WGSL_LOGIC],
      ['tunnel', SAMPLE_TUNNEL_WGSL_LOGIC],
      ['noise', SAMPLE_NOISE_WGSL_LOGIC],
    ] as const;

    it.each(samples)('%s passes bindgroup + workgroup gate preview', (_name, logic) => {
      const wgsl = assembleComputeShader(logic);
      const gate = checkWgslGatePreview(wgsl);
      expect(gate.errors).toEqual([]);
      expect(gate.ok).toBe(true);
      expect(wgsl).toContain('@binding(12)');
      expect(wgsl).toContain('@workgroup_size(16, 16, 1)');
    });
  });

  it('parses all three GLSL fixtures', () => {
    for (const src of [SAMPLE_PLASMA_GLSL, SAMPLE_TUNNEL_GLSL, SAMPLE_NOISE_GLSL]) {
      expect(extractMainImageGlsl(src)).not.toBeNull();
      expect(detectUnsupportedFeatures(src)).toHaveLength(0);
    }
  });
});
