// Steamy Glass — Codex (g) condensation, droplets, and interactive clearing.
// A/C packing: steam density, droplet mass, runoff, wipe memory.
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

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn sourceAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let texel = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let fogTarget = mix(0.08, 1.15, u.zoom_params.x);
  let returnRate = mix(0.002, 0.038, u.zoom_params.y);
  let wipeRadius = mix(0.035, 0.34, u.zoom_params.z);
  let blurRadius = mix(0.5, 5.5, u.zoom_params.w);

  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
  let right = stateAt(pixel + vec2<i32>(1, 0), dims);
  let top = stateAt(pixel + vec2<i32>(0, -1), dims);
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims);
  let average = (left + right + top + bottom) * 0.25;
  var steam = mix(state.r, average.r, 0.045);
  steam += (fogTarget - steam) * returnRate * (1.0 + audio.y * 0.35);
  var droplets = mix(state.g, average.g, 0.025);
  droplets += max(steam - 0.46, 0.0) * (0.004 + audio.z * 0.003);
  var runoff = mix(state.b, top.b, 0.08) + droplets * 0.0008;
  var wipeMemory = state.a * 0.982;

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDistance = length(p - mouseP);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let wipe = (1.0 - smoothstep(wipeRadius * 0.45, wipeRadius,
    mouseDistance)) * held;
  steam *= 1.0 - wipe * 0.82;
  droplets *= 1.0 - wipe * 0.7;
  wipeMemory = max(wipeMemory, wipe);

  var clickClear = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 2.8) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = length(q);
      let ring = exp(-abs(d - age * 0.31) * 34.0 - age * 0.85);
      clickClear += ring;
    }
  }
  steam *= 1.0 - clamp(clickClear * 0.28, 0.0, 0.72);
  droplets += clickClear * 0.014;
  runoff = clamp(runoff * 0.992 + audio.x * 0.0015, 0.0, 1.0);
  steam = clamp(steam, 0.0, 1.25);
  droplets = clamp(droplets * 0.995, 0.0, 1.0);
  textureStore(dataTextureA, pixel,
    vec4<f32>(steam, droplets, runoff, wipeMemory));

  let gradient = vec2<f32>(right.g - left.g, bottom.g - top.g);
  let refractedUV = clamp(uv + gradient * (0.018 + droplets * 0.024),
    vec2<f32>(0.0), vec2<f32>(1.0));
  var blurred = vec4<f32>(0.0);
  var weight = 0.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let delta = vec2<f32>(f32(x), f32(y));
      let w = select(0.65, 1.0, x == 0 && y == 0);
      blurred += sourceAt(refractedUV + delta * texel * blurRadius) * w;
      weight += w;
    }
  }
  blurred /= max(weight, 0.001);
  let clearSource = sourceAt(refractedUV);
  let opticalDepth = steam * (1.2 + droplets * 0.8);
  let transmittance = exp(-opticalDepth);
  let fogColor = vec3<f32>(0.72, 0.84, 0.92) *
    (0.78 + audio.y * 0.12) + vec3<f32>(0.12, 0.05, 0.18) * audio.x;
  var rgb = mix(blurred.rgb, fogColor, 1.0 - transmittance);
  rgb = mix(rgb, clearSource.rgb, clamp(wipeMemory * 0.82, 0.0, 0.9));
  let glint = pow(clamp(droplets, 0.0, 1.0), 1.6) *
    (0.35 + audio.z * 0.5);
  rgb += vec3<f32>(0.68, 0.9, 1.0) * glint * 0.25;
  let alpha = clamp(clearSource.a * transmittance +
    (1.0 - transmittance) * 0.82 + droplets * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    refractedUV, 0.0).r;
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(mix(depth, 0.9, (1.0 - transmittance) * 0.22), 0.0, 1.0), 0.0, 0.0, 0.0));
}
