// Fluid Feedback Coupled — Codex (e) velocity/pressure/dye feedback solver.
// A/C packing: velocity.xy, pressure, density.
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

fn curlAt(pixel: vec2<i32>, dims: vec2<i32>) -> f32 {
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims).xy;
  let right = stateAt(pixel + vec2<i32>(1, 0), dims).xy;
  let top = stateAt(pixel + vec2<i32>(0, -1), dims).xy;
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims).xy;
  return 0.5 * ((right.y - left.y) - (bottom.x - top.x));
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.32, 0.66)));
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

  let viscosity = mix(0.015, 0.18, u.zoom_params.x);
  let turbulence = mix(0.04, 0.62, u.zoom_params.y);
  let fade = mix(0.998, 0.94, u.zoom_params.z);
  let glow = mix(0.12, 1.7, u.zoom_params.w);

  let center = stateAt(coord, dims);
  var velocity = clamp(center.xy, vec2<f32>(-0.07), vec2<f32>(0.07));
  let advected = stateUV(clamp(uv - velocity,
    vec2<f32>(0.0), vec2<f32>(1.0)), dims);
  velocity = advected.xy;
  var density = clamp(advected.w, 0.0, 1.6);

  let left = stateAt(coord + vec2<i32>(-1, 0), dims);
  let right = stateAt(coord + vec2<i32>(1, 0), dims);
  let top = stateAt(coord + vec2<i32>(0, -1), dims);
  let bottom = stateAt(coord + vec2<i32>(0, 1), dims);
  velocity += viscosity * (left.xy + right.xy + top.xy + bottom.xy - 4.0 * velocity);
  let divergence = 0.5 * ((right.x - left.x) + (bottom.y - top.y));
  let pressure = clamp((left.z + right.z + top.z + bottom.z - divergence) * 0.25,
    -0.45, 0.45);
  velocity -= vec2<f32>(right.z - left.z, bottom.z - top.z) * 0.22;

  let curl = curlAt(coord, dims);
  let curlGradient = vec2<f32>(
    abs(curlAt(coord + vec2<i32>(1, 0), dims)) -
      abs(curlAt(coord + vec2<i32>(-1, 0), dims)),
    abs(curlAt(coord + vec2<i32>(0, 1), dims)) -
      abs(curlAt(coord + vec2<i32>(0, -1), dims)));
  let curlNormal = curlGradient / max(length(curlGradient), 0.0001);
  velocity += vec2<f32>(curlNormal.y, -curlNormal.x) * curl *
    turbulence * (0.06 + audio.z * 0.08);

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let oscillation = vec2<f32>(
    sin(p.y * 15.0 + time * (2.0 + audio.x * 3.0)),
    cos(p.x * 13.0 - time * (1.7 + audio.y * 2.5)));
  velocity += oscillation * turbulence * 0.0012;

  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let stir = exp(-mouseDist * mouseDist * 50.0) * held;
  velocity += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    stir * (0.018 + turbulence * 0.026);
  density += stir * (0.045 + audio.x * 0.045);

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let front = sin((d - age * 0.40) * 70.0) *
        exp(-abs(d - age * 0.40) * 25.0 - age * 0.9);
      velocity += vec2<f32>(q.x / aspect, q.y) / d * front * 0.015;
      density += max(front, 0.0) * 0.065;
      clickFront += abs(front);
    }
  }

  velocity = clamp(velocity, vec2<f32>(-0.075), vec2<f32>(0.075));
  density = clamp(density * fade + 0.002 * (1.0 + audio.y), 0.0, 1.6);
  textureStore(dataTextureA, coord,
    vec4<f32>(velocity, pressure, density));

  let sourceUV = clamp(uv + velocity * (1.2 + turbulence),
    vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let phase = atan2(velocity.y, velocity.x) * 0.15915494 +
    density * 0.19 + time * 0.045;
  let tint = spectral(phase + audio.y * 0.12);
  let speed = length(velocity);
  var rgb = mix(source.rgb, tint * (0.25 + density),
    clamp(density * 0.42, 0.0, 0.82));
  rgb += tint * glow * (speed * 2.2 + abs(curl) * 0.35 + clickFront * 0.08);
  let alpha = clamp(source.a * 0.68 + density * 0.24 +
    speed * 1.1 + stir * 0.06, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgb), alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    sourceUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - density * 0.014 - speed * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
