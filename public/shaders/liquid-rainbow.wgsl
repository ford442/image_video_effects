// ═══════════════════════════════════════════════════════════════════
//  Liquid Rainbow
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-07-21
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn fresnel(cosTheta: f32, f0: f32) -> f32 { return f0 + (1.0 - f0) * pow(1.0 - clamp(cosTheta, 0.0, 1.0), 5.0); }
fn spectralPalette(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(6.283185 * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let time = u.config.x;
  let viscosity = mix(0.2, 0.95, u.zoom_params.x); let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.002, 0.03, u.zoom_params.z); let dispersion = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let ambient = vec2<f32>(sin(uv.y * mix(8.0, 24.0, turbulence) + time * 0.4), cos(uv.x * mix(9.0, 27.0, turbulence) - time * 0.35));
  var displacement = ambient * turbulence * 0.002 * mix(1.2, 0.5, viscosity);
  var crest = 0.0; let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 3.4) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001);
      let dir = delta / dist; let life = 1.0 - smoothstep(0.0, 3.4, age);
      let wave = sin(dist * (24.0 + turbulence * 18.0) - age * (3.0 + audio.x * 5.0));
      let envelope = exp(-dist * mix(11.0, 5.0, viscosity)) * life;
      displacement += vec2<f32>(dir.x / aspect, dir.y) * wave * envelope * rippleStrength * (1.0 + audio.x * 0.65);
      crest += pow(max(wave, 0.0), 4.0) * envelope;
    }
  }
  let magnitude = length(displacement); let normal = normalize(vec3<f32>(-displacement * 32.0, 1.0));
  let rim = fresnel(normal.z, 0.035); let angle = time * (0.15 + audio.y * 0.25);
  let direction = vec2<f32>(cos(angle), sin(angle));
  let split = direction * (0.001 + dispersion * 0.018 + magnitude * 0.45) * (1.0 + audio.z * 0.4);
  let baseUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let cR = textureSampleLevel(readTexture, u_sampler, clamp(baseUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let spectral = spectralPalette(fract(crest * 0.2 + dispersion + time * 0.025));
  let spectralMask = clamp(crest * 0.22 + rim * dispersion, 0.0, 1.0);
  let separated = vec3<f32>(cR.r, cG.g, cB.b);
  let rgb = mix(separated, separated * (0.75 + spectral * 0.75), spectralMask) + spectral * rim * (0.08 + audio.z * 0.22);
  let sourceAlpha = max(cR.a, max(cG.a, cB.a));
  let alpha = clamp(sourceAlpha * (0.82 + viscosity * 0.16) + spectralMask * 0.18, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
