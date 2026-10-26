import { BLIT_MIX_WGSL, BLIT_WGSL, GENERATIVE_BLIT_MIX_WGSL, GENERATIVE_BLIT_WGSL } from './ShaderTemplates';

const vertexStage = (wgsl: string) => wgsl.slice(wgsl.indexOf('@vertex'), wgsl.indexOf('@group(0)'));

describe('blit templates', () => {
  it('the ordinary blits have no hold bindings: cues cost nothing until one runs', () => {
    for (const wgsl of [BLIT_WGSL, GENERATIVE_BLIT_WGSL]) {
      expect(wgsl).not.toContain('@group(1)');
      expect(wgsl).not.toContain('holdTex');
      expect(wgsl).toContain('return vec4f(rgb, 1.0);');
    }
  });

  it('the mix variants add the hold and the mix factor as group 1, after the gamma encode', () => {
    for (const wgsl of [BLIT_MIX_WGSL, GENERATIVE_BLIT_MIX_WGSL]) {
      expect(wgsl).toContain('@group(0) @binding(0) var src: texture_2d<f32>;');
      expect(wgsl).toContain('@group(1) @binding(0) var holdTex: texture_2d<f32>;');
      expect(wgsl).toContain('@group(1) @binding(1) var<uniform> holdMix: HoldMix;');
      expect(wgsl.indexOf('pow(clamp(c.rgb')).toBeLessThan(wgsl.indexOf('mix(rgb, held'));
      // 0 = the new frame, 1 = the hold; the hold is read pixel for pixel, never flipped.
      expect(wgsl).toContain('mix(rgb, held, clamp(holdMix.amount, 0.0, 1.0))');
      expect(wgsl).toContain('textureLoad(holdTex, clamp(vec2i(in.pos.xy)');
    }
  });

  it('the mix never touches shader state: no compute Uniforms, config, zoom_params or extraBuffer', () => {
    for (const wgsl of [BLIT_MIX_WGSL, GENERATIVE_BLIT_MIX_WGSL]) {
      expect(wgsl).not.toMatch(/struct Uniforms|zoom_params|extraBuffer|\bconfig\b/);
    }
  });

  it('orientation stays what selectPresentPipeline picked: the mix variants share the vertex stage', () => {
    expect(vertexStage(BLIT_MIX_WGSL)).toBe(vertexStage(BLIT_WGSL));
    expect(vertexStage(GENERATIVE_BLIT_MIX_WGSL)).toBe(vertexStage(GENERATIVE_BLIT_WGSL));
    expect(vertexStage(BLIT_MIX_WGSL)).not.toBe(vertexStage(GENERATIVE_BLIT_MIX_WGSL));
  });
});
