// Steamy Glass Volumetric — Codex (g) depth-layered condensation volume.
// A/C packing: steam density, optical depth, droplets, vertical flow.
// B and extraBuffer are intentionally unused; C reads are exact and bounded.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
    max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
    vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), s.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)),
      hash12(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn stateUV(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  return stateAt(vec2<i32>(floor(uv * vec2<f32>(dims))), dims);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let steamGain = mix(0.2, 1.4, u.zoom_params.x);
  let depthGain = mix(0.5, 3.2, u.zoom_params.y);
  let dropletGain = mix(0.08, 1.1, u.zoom_params.z);
  let turbulence = mix(0.03, 0.75, u.zoom_params.w);

  let state = stateAt(pixel, dims);
  let flow = vec2<f32>(
    (noise(uv * 7.0 + vec2<f32>(time * 0.12, 0.0)) - 0.5) * turbulence * 0.009,
    -(0.001 + turbulence * 0.004 + audio.y * 0.002));
  let advected = stateUV(clamp(uv - flow, vec2<f32>(0.0), vec2<f32>(1.0)), dims);
  let average = (stateAt(pixel + vec2<i32>(-1, 0), dims) +
    stateAt(pixel + vec2<i32>(1, 0), dims) +
    stateAt(pixel + vec2<i32>(0, -1), dims) +
    stateAt(pixel + vec2<i32>(0, 1), dims)) * 0.25;
  var steam = mix(advected.r, average.r, 0.06);
  steam += (0.22 + steamGain * 0.42 - steam) * 0.012;
  steam += audio.x * 0.004;
  var droplets = mix(advected.b, average.b, 0.035) +
    max(steam - 0.4, 0.0) * dropletGain * 0.006;
  var verticalFlow = mix(advected.a, flow.y, 0.08);

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDistance = length(p - mouseP);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let clearing = exp(-mouseDistance * mouseDistance * 55.0) * held;
  steam *= 1.0 - clearing * 0.68;
  droplets *= 1.0 - clearing * 0.5;

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.2) {
      let d = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
      let front = exp(-abs(d - age * 0.29) * 31.0 - age * 0.72);
      steam *= 1.0 - clamp(front * 0.24, 0.0, 0.58);
      droplets += front * 0.018;
      clickFront += front;
    }
  }

  steam = clamp(steam * 0.997, 0.0, 1.35);
  droplets = clamp(droplets * 0.994, 0.0, 1.0);
  let opticalDepth = clamp(steam * depthGain * (0.6 + droplets * 0.8), 0.0, 4.0);
  textureStore(dataTextureA, pixel,
    vec4<f32>(steam, opticalDepth, droplets, verticalFlow));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var integratedColor = vec3<f32>(0.0);
  var transmittance = 1.0;
  for (var layer = 0; layer < 6; layer = layer + 1) {
    let z = (f32(layer) + 0.5) / 6.0;
    let layerNoise = noise(uv * (4.0 + z * 5.0) +
      vec2<f32>(time * 0.08 * z, -time * 0.05));
    let layerDensity = steam * (0.45 + layerNoise * 0.8) *
      (1.0 - smoothstep(0.15, 1.0, z)) * (0.7 + depth * 0.3);
    let absorption = exp(-layerDensity * depthGain * 0.22);
    let layerColor = mix(vec3<f32>(0.44, 0.56, 0.7),
      vec3<f32>(0.82, 0.9, 1.0), z + audio.z * 0.12);
    integratedColor += layerColor * (1.0 - absorption) * transmittance;
    transmittance *= absorption;
  }

  let gradient = vec2<f32>(
    stateAt(pixel + vec2<i32>(1, 0), dims).b -
      stateAt(pixel + vec2<i32>(-1, 0), dims).b,
    stateAt(pixel + vec2<i32>(0, 1), dims).b -
      stateAt(pixel + vec2<i32>(0, -1), dims).b);
  let sourceUV = clamp(uv + gradient * (0.02 + droplets * 0.03),
    vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  var rgb = source.rgb * transmittance + integratedColor;
  rgb += vec3<f32>(0.55, 0.82, 1.0) *
    (droplets * 0.18 + clickFront * 0.08 + audio.z * 0.025);
  let alpha = clamp(source.a * transmittance + (1.0 - transmittance) * 0.9 +
    droplets * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(mix(depth, 0.86, (1.0 - transmittance) * 0.3), 0.0, 1.0), 0.0, 0.0, 0.0));
}
