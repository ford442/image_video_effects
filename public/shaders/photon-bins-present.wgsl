// ═══ PHOTON BINS — PRESENT ════════════════════════════════════════════════
//  Reads the caustic accumulator (dataA → dataC barrier after the splat pass)
//  and composites it over a night-dimmed copy of the source image:
//    · spectral dispersion — wavelength bins arrive as separate rainbow ribbons
//    · thin-film fringes   — local photon count modulates hue in iridescent bands
//    · ridge glints        — the height field's steep edges catch the light (treble)
//  A/C packing: .rgb spectral energy, .a photon count

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let hi = ri - vec2<i32>(1);
  let p = vec2<i32>(gid.xy);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let acc = textureLoad(dataTextureC, p, 0);
  let src = textureLoad(readTexture, p, 0).rgb;

  // Edge strength of the source (the height field the rays bounce off).
  let gx = luma(textureLoad(readTexture, clamp(p + vec2<i32>(1, 0), vec2<i32>(0), hi), 0).rgb)
         - luma(textureLoad(readTexture, clamp(p - vec2<i32>(1, 0), vec2<i32>(0), hi), 0).rgb);
  let gy = luma(textureLoad(readTexture, clamp(p + vec2<i32>(0, 1), vec2<i32>(0), hi), 0).rgb)
         - luma(textureLoad(readTexture, clamp(p - vec2<i32>(0, 1), vec2<i32>(0), hi), 0).rgb);
  let edge = clamp(length(vec2<f32>(gx, gy)) * 3.0, 0.0, 1.0);

  let fringe = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(acc.a * 0.9) + vec3<f32>(0.0, 0.33, 0.67)));
  let caustic = acc.rgb * (vec3<f32>(0.8) + 0.7 * fringe);
  let glint = vec3<f32>(1.0, 0.95, 0.9) * edge * luma(acc.rgb) * (1.5 + treble * 3.0);

  let bg = src * 0.16 + vec3<f32>(0.012, 0.016, 0.035);
  textureStore(writeTexture, p, vec4<f32>(aces(bg + caustic + glint), 1.0));
}
