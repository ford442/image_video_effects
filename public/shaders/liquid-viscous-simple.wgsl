// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous (Simple)
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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn flowField(p: vec2<f32>, time: f32) -> vec2<f32> {
  let a = sin(p.y * 6.0 + time) + cos(p.x * 3.7 - time * 0.7);
  let b = cos(p.x * 5.0 - time * 0.8) - sin(p.y * 4.3 + time * 0.6);
  return vec2<f32>(a, b) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let viscosity = mix(0.18, 0.92, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.002, 0.035, u.zoom_params.z);
  let spectralShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFlow = mix(1.0, 0.35, clamp(depth, 0.0, 1.0));
  let ambient = flowField(uv * mix(3.0, 9.0, turbulence), time * (0.15 + audio.y * 0.35));
  var displacement = ambient * turbulence * 0.0025 * depthFlow;
  var vortexEnergy = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);

  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age > 0.0 && age < 4.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let dist = max(length(delta), 0.0001);
      let dir = delta / dist;
      let tangent = vec2<f32>(-dir.y, dir.x);
      let life = 1.0 - smoothstep(0.0, 4.0, age);
      let envelope = exp(-dist * mix(5.0, 16.0, viscosity)) * life;
      let spiral = sin(dist * 24.0 - age * (2.0 + audio.x * 5.0));
      let local = (tangent * (0.7 + viscosity) + dir * spiral * 0.28) * envelope;
      displacement += vec2<f32>(local.x / aspect, local.y) * rippleStrength * (1.0 + audio.x * 0.6);
      vortexEnergy += envelope * abs(spiral);
    }
  }

  let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let left = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cohesion = ((right + left + up + down) * 0.25 - center).rg;
  displacement = displacement * mix(1.25, 0.45, viscosity) + cohesion * (0.004 + viscosity * 0.008);

  let chroma = (0.15 + spectralShift * 1.4 + audio.z * 0.35) * displacement;
  let uvR = clamp(uv + displacement + chroma, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + displacement - chroma, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  let sheen = clamp(vortexEnergy * 0.12 + length(displacement) * 18.0, 0.0, 1.0);
  let rgb = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) + vec3<f32>(0.04, 0.1, 0.13) * sheen * (0.4 + audio.y);
  let sourceAlpha = max(sampleR.a, max(sampleG.a, sampleB.a));
  let alpha = clamp(sourceAlpha * (0.88 + viscosity * 0.12) + sheen * 0.2, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
