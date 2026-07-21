// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous Nebula
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
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

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(41.7, 289.1))) * 45758.5453); }
fn noise21(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0)), w.x), w.y);
}
fn fbm(p0: vec2<f32>) -> f32 {
  var p = p0; var value = 0.0; var amp = 0.5;
  for (var i = 0; i < 4; i = i + 1) { value += noise21(p) * amp; p = mat2x2<f32>(1.6, 1.2, -1.2, 1.6) * p; amp *= 0.5; }
  return value;
}
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0); let time = u.config.x;
  let viscosity = mix(0.2, 0.92, u.zoom_params.x); let turbulence = u.zoom_params.y;
  let nebulaGlow = u.zoom_params.z; let spectralShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let warpA = fbm(p * mix(2.5, 7.0, turbulence) + vec2<f32>(time * 0.08, -time * 0.06));
  let warpB = fbm(p * 4.0 + vec2<f32>(warpA, -warpA) * 2.4 - time * 0.04);
  var displacement = vec2<f32>(warpA - 0.5, warpB - 0.5) * (0.004 + turbulence * 0.018) * mix(1.0, 0.35, depth);
  var vortexEnergy = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 6.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001);
      let dir = delta / dist; let tangent = vec2<f32>(-dir.y, dir.x);
      let life = exp(-age * mix(0.35, 0.12, viscosity)); let falloff = exp(-dist * mix(8.0, 3.0, viscosity));
      let pulse = sin(dist * 20.0 - age * (2.0 + audio.x * 3.0));
      let flow = (tangent * (0.8 + viscosity) + dir * pulse * 0.25) * life * falloff;
      displacement += vec2<f32>(flow.x / aspect, flow.y) * (0.006 + turbulence * 0.022) * (1.0 + audio.x * 0.5);
      vortexEnergy += life * falloff;
    }
  }

  let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let base = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv - displacement * 0.35, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let density = smoothstep(0.25, 0.85, warpA * 0.6 + warpB * 0.6 + vortexEnergy * 0.08);
  let paletteA = vec3<f32>(0.08, 0.22, 0.5); let paletteB = vec3<f32>(0.75, 0.16, 0.72);
  let nebula = mix(paletteA, paletteB, fract(warpB + spectralShift + time * 0.025 + audio.y * 0.2));
  let veins = pow(clamp(1.0 - abs(warpA - warpB) * 3.0, 0.0, 1.0), 4.0);
  var rgb = base.rgb + nebula * density * nebulaGlow * (0.35 + audio.x * 0.8) + veins * vec3<f32>(0.25, 0.55, 1.0) * (0.2 + audio.z);
  let trailMix = clamp((0.12 + viscosity * 0.3) * history.a, 0.0, 0.48);
  rgb = mix(rgb, history.rgb, trailMix);
  rgb = aces(rgb);
  let alpha = clamp(base.a * 0.75 + density * 0.22 + veins * 0.12 + history.a * trailMix * 0.15, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
