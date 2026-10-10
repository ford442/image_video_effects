import {
  assembleComputeShader,
  extractMainImageGlsl,
  detectUnsupportedFeatures,
  generateShaderDefinitionDraft,
  buildFragmentShaderForNaga,
  convertShadertoyGlsl,
  rewriteNagaWgslToPixelocity,
} from './shadertoyToPixelocity';
import { formatNagaError, type NagaGlslConverter, type NagaValidator } from '../utils/nagaWasm';
import { loadRealNaga } from '../test-utils/nagaWasmNode';
import { checkWgslGatePreview } from '../utils/wgslGatePreview';
import {
  SAMPLE_PLASMA_GLSL,
  SAMPLE_TUNNEL_GLSL,
  SAMPLE_NOISE_GLSL,
  SAMPLE_PLASMA_WGSL_LOGIC,
  SAMPLE_TUNNEL_WGSL_LOGIC,
  SAMPLE_NOISE_WGSL_LOGIC,
  SAMPLE_MOUSE_CHANNEL_GLSL,
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

  it('wraps Shadertoy GLSL verbatim as a GLSL 450 fragment shader for naga', () => {
    const frag = buildFragmentShaderForNaga(SAMPLE_PLASMA_GLSL);
    expect(frag).toContain('#version 450');
    expect(frag).toContain('uniform ShadertoyUniforms');
    expect(frag).toContain(SAMPLE_PLASMA_GLSL.trim());
    expect(frag).toContain('mainImage(st_fragColor, gl_FragCoord.xy);');
  });

  it('generates shader definition draft with audio mappings', () => {
    const draft = generateShaderDefinitionDraft('st-plasma', 'Test Plasma');
    expect(draft.params).toHaveLength(4);
    expect(draft.params[0]!.audio).toBe('bass');
    expect(draft.params[0]!.mapping).toBe('zoom_params.x');
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

  describe('naga translation (real public/wasm/naga_wasm.wasm)', () => {
    let naga: NagaValidator & NagaGlslConverter;
    const convert = async (glsl: string, stage: 'fragment' | 'vertex' = 'fragment') => {
      const result = naga.glslToWgsl(glsl, stage);
      if (!result.ok || result.wgsl === undefined) throw new Error(formatNagaError(result));
      return result.wgsl;
    };
    const check = async (wgsl: string) => {
      const diag = naga.validate(wgsl);
      return diag.ok ? null : formatNagaError(diag);
    };

    beforeAll(async () => {
      naga = await loadRealNaga();
    });

    it.each([
      ['plasma (#define)', SAMPLE_PLASMA_GLSL],
      ['tunnel (atan)', SAMPLE_TUNNEL_GLSL],
      ['noise (helper fn)', SAMPLE_NOISE_GLSL],
      ['mouse + iChannel0 + loop', SAMPLE_MOUSE_CHANNEL_GLSL],
    ])('%s converts to a compute shader that naga and the gate accept', async (_name, glsl) => {
      const result = await convertShadertoyGlsl(glsl, convert, check);
      expect(result.errors).toEqual([]);
      expect(naga.validate(result.wgsl)).toEqual({ ok: true });

      const gate = checkWgslGatePreview(result.wgsl);
      expect(gate.errors).toEqual([]);
      expect(result.wgsl).toContain('@compute @workgroup_size(16, 16, 1)');
      expect(result.wgsl).toContain('mainImage(&outColor, fragCoord);');
      expect(result.wgsl).not.toMatch(/@fragment|FragmentOutput|st_iChannel0|var<uniform>\s+\w+\s*:\s*ShadertoyUniforms/);
    });

    it('binds iChannel0 to readTexture with an explicit LOD', async () => {
      const result = await convertShadertoyGlsl(SAMPLE_MOUSE_CHANNEL_GLSL, convert, check);
      expect(result.wgsl).toMatch(/textureSampleLevel\(readTexture, u_sampler,/);
      expect(result.wgsl).not.toMatch(/textureSample\(/);
    });

    it('reports a GLSL syntax error with its location', async () => {
      const broken = 'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0) }';
      const result = await convertShadertoyGlsl(broken, convert, check);
      expect(result.wgsl).toBe('');
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toMatch(/^GLSL conversion failed: L\d+:\d+/);
    });

    it('rejects naga output that has no Shadertoy uniform block', () => {
      expect(() => rewriteNagaWgslToPixelocity('fn mainImage() {}')).toThrow(/ShadertoyUniforms/);
    });
  });
});
