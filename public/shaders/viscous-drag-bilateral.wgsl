// Viscous Drag Bilateral — Codex (e) edge-aware displacement gel.
// A/C packing: displacement.xy, edge confidence, coating thickness.
// B and extraBuffer are intentionally unused; C loads are exact and bounded.

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

fn stateUV(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  return stateAt(vec2<i32>(floor(uv * vec2<f32>(dims))), dims);
}

fn sampleSource(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let texel = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let viscosity = mix(0.04, 0.42, u.zoom_params.x);
  let rangeSigma = mix(0.035, 0.55, u.zoom_params.y);
  let hueAmount = u.zoom_params.z;
  let dragStrength = mix(0.25, 2.2, u.zoom_params.w);

  let previous = stateAt(coord, dims);
  let average = (stateAt(coord + vec2<i32>(-1, 0), dims) +
    stateAt(coord + vec2<i32>(1, 0), dims) +
    stateAt(coord + vec2<i32>(0, -1), dims) +
    stateAt(coord + vec2<i32>(0, 1), dims)) * 0.25;
  var displacement = mix(previous.xy, average.xy, viscosity) *
    mix(0.965, 0.995, u.zoom_params.x);

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let brush = exp(-mouseDist * mouseDist * 38.0) * held;
  displacement += vec2<f32>(mouseDelta.x / aspect, mouseDelta.y) / mouseDist *
    brush * 0.018 * dragStrength;
  displacement += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    brush * 0.006 * dragStrength;

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let front = sin((d - age * 0.36) * 62.0) *
        exp(-abs(d - age * 0.36) * 24.0 - age * 0.85);
      displacement += vec2<f32>(q.x / aspect, q.y) / d *
        front * 0.012 * dragStrength;
      clickFront += abs(front);
    }
  }

  displacement += vec2<f32>(sin(uv.y * 21.0 - time * 2.3),
    cos(uv.x * 19.0 + time * 1.9)) * audio.xz * 0.0012;
  displacement = clamp(displacement, vec2<f32>(-0.12), vec2<f32>(0.12));
  let sampleUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let center = sampleSource(sampleUV);

  var accumulation = vec3<f32>(0.0);
  var alphaAccumulation = 0.0;
  var weightSum = 0.0;
  for (var y = -2; y <= 2; y = y + 1) {
    for (var x = -2; x <= 2; x = x + 1) {
      let delta = vec2<f32>(f32(x), f32(y));
      let neighbor = sampleSource(sampleUV + delta * texel);
      let spatialWeight = exp(-dot(delta, delta) / (2.2 + viscosity * 12.0));
      let colorDelta = neighbor.rgb - center.rgb;
      let rangeWeight = exp(-dot(colorDelta, colorDelta) /
        max(2.0 * rangeSigma * rangeSigma, 0.0001));
      let weight = spatialWeight * rangeWeight;
      accumulation += neighbor.rgb * weight;
      alphaAccumulation += neighbor.a * weight;
      weightSum += weight;
    }
  }

  let filtered = accumulation / max(weightSum, 0.001);
  let filteredAlpha = alphaAccumulation / max(weightSum, 0.001);
  let edgeConfidence = clamp(1.0 - length(filtered - center.rgb) * 2.8, 0.0, 1.0);
  let coating = clamp(mix(previous.w, 0.24 + brush * 0.58 + clickFront * 0.1,
    0.065) + audio.y * 0.004, 0.0, 1.0);
  textureStore(dataTextureA, coord,
    vec4<f32>(displacement, edgeConfidence, coating));

  let phase = atan2(displacement.y, displacement.x) * 0.15915494 +
    time * 0.035 + audio.y * 0.14;
  let tint = spectral(phase);
  let normal = normalize(vec3<f32>(displacement * 11.0, 0.22));
  let specular = pow(max(dot(normal,
    normalize(vec3<f32>(0.45, 0.55, 1.0))), 0.0), 22.0);
  var rgb = mix(filtered, filtered * tint * 1.45,
    clamp(hueAmount * (0.25 + coating * 0.55), 0.0, 0.82));
  rgb += tint * (specular * coating * 0.36 + clickFront * 0.11 + audio.z * 0.035);
  let alpha = clamp(mix(center.a, filteredAlpha, 0.72) * (0.72 + coating * 0.26) +
    brush * 0.05, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgb), alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    sampleUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - coating * 0.014 - specular * 0.006, 0.0, 1.0), 0.0, 0.0, 0.0));
}
