// Hyper-Space Jump — continuous relativistic streak integration and helical flight.
// A/C stores ACES display RGBA. B is unused. Depth remains cleared for the tunnel.

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

const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn dopplerPalette(shift: f32) -> vec3<f32> {
  let cold = vec3<f32>(0.12, 0.5, 1.65);
  let neutral = vec3<f32>(0.9, 0.95, 1.0);
  let hot = vec3<f32>(1.55, 0.22, 0.06);
  return mix(mix(hot, neutral, smoothstep(-1.0, 0.0, shift)), cold, smoothstep(0.0, 1.0, shift));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let jumpStrength = 0.2 + u.zoom_params.x * 2.8;
  let decay = 0.58 + u.zoom_params.y * 0.38;
  let chromaticSpread = 0.002 + u.zoom_params.z * 0.035;
  let vignetteSize = 0.18 + u.zoom_params.w * 0.95;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let vanishingPoint = clamp(u.zoom_config.yz, vec2<f32>(0.02), vec2<f32>(0.98));
  let held = u.zoom_config.w > 0.5;
  let heldAcceleration = select(1.0, 1.75 + audio.x * 0.35, held);

  let ray = (uv - vanishingPoint) * aspectVec;
  let radius = length(ray);
  let directionAspect = ray / max(radius, 0.0001);
  let directionUV = directionAspect / aspectVec;
  var shock = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.42 + audio.x * 0.09);
      shock += sin((rd - front) * 72.0) * exp(-abs(rd - front) * 31.0) * exp(-age * 1.15);
    }
  }

  let beta = clamp((0.25 + jumpStrength * 0.2 + audio.x * 0.12) * heldAcceleration + abs(shock) * 0.08, 0.0, 0.985);
  let gamma = inverseSqrt(max(1.0 - beta * beta, 0.03));
  let helixPhase = time * (1.1 + beta * 4.0 + audio.y) + radius * (9.0 + audio.z * 3.0);
  let tangent = vec2<f32>(-directionUV.y, directionUV.x);
  let helix = tangent * sin(helixPhase) * (0.0025 + beta * 0.008) * smoothstep(0.0, 0.55, radius);

  var accumulated = vec3<f32>(0.0);
  var alphaAccum = 0.0;
  var weightAccum = 0.0;
  let sampleCount = 14;
  for (var i = 0; i < sampleCount; i = i + 1) {
    let t = f32(i) / f32(sampleCount - 1);
    let relativisticDistance = (exp2(t * (1.0 + gamma * 0.45)) - 1.0) * 0.025 * jumpStrength * heldAcceleration;
    let spiral = helix * (0.25 + t * t * 2.5);
    let shockOffset = directionUV * shock * 0.006 * (1.0 - t);
    let sampleUV = clamp(uv - directionUV * relativisticDistance - spiral - shockOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let longitudinal = dot(directionAspect, normalize(ray + vec2<f32>(0.0001)));
    let doppler = clamp((beta * longitudinal + chromaticSpread * (t - 0.5) * 10.0), -1.0, 1.0);
    let palette = dopplerPalette(doppler);
    let bright = dot(sampleColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let weight = pow(decay, f32(i)) * (0.25 + bright * (1.0 + audio.z));
    accumulated += sampleColor.rgb * palette * weight * (0.65 + gamma * 0.12);
    alphaAccum += sampleColor.a * weight * (0.5 + bright);
    weightAccum += weight;
  }

  let integrated = accumulated / max(weightAccum, 0.0001);
  let starBands = pow(0.5 + 0.5 * sin(log2(1.0 + radius * 42.0) * 28.0 - time * (8.0 + audio.x * 5.0)), 12.0);
  let streakEmission = dopplerPalette(sin(helixPhase)) * starBands * smoothstep(0.02, 0.8, radius) * (0.35 + gamma * 0.16);
  let historyUV = uv - directionUV * (0.006 + beta * 0.018) - helix * 0.7;
  let history = historyAt(historyUV, resolution);
  var hdr = integrated + streakEmission * (0.45 + audio.z * 0.8);
  hdr += history.rgb * clamp(0.035 + beta * 0.09 + abs(shock) * 0.025, 0.0, 0.18);
  let vignette = 1.0 - smoothstep(vignetteSize * 0.55, vignetteSize * 1.55, radius);
  hdr *= 0.18 + vignette * 0.82;
  let alpha = clamp((alphaAccum / max(weightAccum, 0.0001)) * vignette + starBands * 0.25 + abs(shock) * 0.18, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0));
}
