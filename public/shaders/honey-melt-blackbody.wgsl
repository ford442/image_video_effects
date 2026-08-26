// Honey Melt Blackbody — Codex (e) high-viscosity thermal honey.
// A/C packing: velocity.xy, thickness, normalized temperature.
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

fn blackbody(kelvin: f32) -> vec3<f32> {
  let t = clamp(kelvin / 1000.0, 0.8, 12.0);
  var rgb = vec3<f32>(1.0);
  if (t <= 6.5) {
    rgb.r = 1.0;
    rgb.g = clamp(0.39 * log(max(t, 0.001)) - 0.63, 0.0, 1.0);
    rgb.b = clamp(0.54 * log(max(t - 1.0, 0.001)) - 1.0, 0.0, 1.0);
  } else {
    rgb.r = clamp(1.29 * pow(max(t - 0.6, 0.001), -0.133), 0.0, 1.0);
    rgb.g = clamp(1.29 * pow(max(t - 0.6, 0.001), -0.076), 0.0, 1.0);
    rgb.b = 1.0;
  }
  return rgb * (0.42 + 0.58 * pow(t / 6.5, 1.8));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn stateUV(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  return stateAt(vec2<i32>(floor(uv * vec2<f32>(dims))), dims);
}

fn hexMetric(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(p.x * 1.1547005, p.y + p.x * 0.5773503);
  let cell = floor(q);
  let local = fract(q) - 0.5;
  let edge = max(abs(local.x), max(abs(local.y), abs(local.x + local.y)));
  return vec2<f32>(edge, hash12(cell));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let cellScale = mix(8.0, 42.0, u.zoom_params.x);
  let meltRadius = mix(0.045, 0.42, u.zoom_params.y);
  let pullStrength = mix(0.08, 1.2, u.zoom_params.z);
  let softness = mix(0.015, 0.22, u.zoom_params.w);
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let hex = hexMetric(p * cellScale + vec2<f32>(0.0, time * 0.09));
  let cellCore = 1.0 - smoothstep(0.28, 0.48 + softness * 0.2, hex.x);

  let previous = stateAt(coord, dims);
  var velocity = previous.xy * mix(0.992, 0.955, pullStrength);
  let gravity = vec2<f32>(sin(p.x * 5.0 + time * 0.7) * 0.00025,
    0.0007 + audio.x * 0.0007);
  velocity += gravity * (0.4 + previous.z);
  velocity += vec2<f32>(sin(p.y * 13.0 + time), cos(p.x * 11.0 - time * 0.8)) *
    audio.z * 0.00045;

  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let melt = exp(-mouseDist * mouseDist /
    max(meltRadius * meltRadius, 0.0001)) * held;
  velocity -= vec2<f32>(mouseDelta.x / aspect, mouseDelta.y) / mouseDist *
    melt * 0.006 * pullStrength;
  velocity += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    melt * 0.0035 * pullStrength;

  var clickHeat = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.4) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let ring = sin((d - age * 0.22) * 54.0) *
        exp(-abs(d - age * 0.22) * 24.0 - age * 0.65);
      velocity += vec2<f32>(q.x / aspect, q.y) / d * ring * 0.006 * pullStrength;
      clickHeat += abs(ring);
    }
  }

  velocity = clamp(velocity, vec2<f32>(-0.032), vec2<f32>(0.032));
  let advectedUV = clamp(uv - velocity, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = stateUV(advectedUV, dims);
  let average = (stateAt(coord + vec2<i32>(-1, 0), dims) +
    stateAt(coord + vec2<i32>(1, 0), dims) +
    stateAt(coord + vec2<i32>(0, -1), dims) +
    stateAt(coord + vec2<i32>(0, 1), dims)) * 0.25;

  let seedThickness = 0.18 + cellCore * (0.52 + hex.y * 0.24);
  var thickness = mix(advected.z, average.z, 0.055);
  thickness = mix(thickness, seedThickness, 0.018);
  thickness += audio.x * 0.004 - melt * 0.025 + clickHeat * 0.008;
  thickness = clamp(thickness, 0.05, 1.15);
  var temperature = mix(advected.w, average.w, 0.035);
  temperature += thickness * 0.006 + melt * 0.075 + clickHeat * 0.026 + audio.y * 0.008;
  temperature *= 0.992;
  temperature = clamp(temperature, 0.04, 1.25);
  textureStore(dataTextureA, coord, vec4<f32>(velocity, thickness, temperature));

  let source = textureSampleLevel(readTexture, u_sampler, advectedUV, 0.0);
  let kelvin = mix(1050.0, 8800.0, clamp(temperature, 0.0, 1.0));
  let thermal = blackbody(kelvin);
  let beer = exp(-thickness * vec3<f32>(0.35, 1.0, 2.3));
  let amber = vec3<f32>(1.0, 0.38, 0.035) * (1.0 - beer);
  let rim = smoothstep(0.31, 0.49, hex.x) * (1.0 - melt * 0.65);
  var rgb = source.rgb * beer + amber * (0.48 + thickness * 0.42);
  rgb = mix(rgb, thermal * (0.7 + audio.y * 0.25),
    clamp(temperature * 0.58 + melt * 0.26, 0.0, 0.88));
  rgb += vec3<f32>(1.0, 0.78, 0.25) * rim * 0.16 + thermal * clickHeat * 0.12;
  let alpha = clamp(source.a * 0.48 + thickness * 0.42 +
    rim * 0.08 + melt * 0.06, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgb), alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    advectedUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - thickness * 0.018 - rim * 0.008, 0.0, 1.0), 0.0, 0.0, 0.0));
}
