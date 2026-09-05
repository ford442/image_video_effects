// Ripple Tank — Codex (e) graph node 2: pointer, click, and audio sources.
// Reads exact bounded state from C and writes only A.

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

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1) * 43758.5453);
}

fn hash21(x: f32) -> vec2<f32> {
  return vec2<f32>(hash11(x), hash11(x + 73.156));
}

fn splash(distanceSquared: f32, radius: f32) -> f32 {
  let normalizedDistance = sqrt(distanceSquared) / max(radius, 0.0001);
  return smoothstep(1.0, 0.0, normalizedDistance) *
    cos(normalizedDistance * 1.5707963);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let sourceStrength = mix(0.15, 1.5, u.zoom_params.z) *
    (1.0 + audio.x * 0.65);

  let state = textureLoad(dataTextureC, pixel, 0);
  var height = state.r;
  var velocity = state.g;
  var foam = state.b;
  var phase = state.a;

  let mouseDelta = (uv - u.zoom_config.yz) * aspect;
  let mouseDistanceSquared = dot(mouseDelta, mouseDelta);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseRadius = 0.022 + audio.y * 0.006;
  if (held > 0.0 && mouseDistanceSquared < mouseRadius * mouseRadius) {
    phase = fract(phase + (0.055 + audio.z * 0.045));
    let drive = sin(phase * 6.283185) * sourceStrength * held;
    let shape = splash(mouseDistanceSquared, mouseRadius);
    height += drive * shape * 0.34;
    velocity += drive * shape * 0.08;
    foam += abs(drive) * shape * 0.06;
  }

  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 0.14) {
      let delta = (uv - event.xy) * aspect;
      let distanceSquared = dot(delta, delta);
      let radius = 0.026;
      if (distanceSquared < radius * radius) {
        let punch = (1.0 - age / 0.14) * sourceStrength * max(event.w, 0.35);
        let shape = splash(distanceSquared, radius);
        height -= punch * shape * 0.48;
        velocity -= punch * shape * 0.12;
        foam += punch * shape * 0.09;
      }
    }
  }

  let dripRate = 0.8 + audio.z * 1.55;
  for (var drop = 0; drop < 3; drop = drop + 1) {
    let clock = time * dripRate + f32(drop) * 0.37;
    let cell = floor(clock);
    let age = fract(clock) / dripRate;
    let position = hash21(cell * 7.31 + f32(drop) * 91.7) * 0.8 + vec2<f32>(0.1);
    if (age < 0.1) {
      let delta = (uv - position) * aspect;
      let distanceSquared = dot(delta, delta);
      let radius = 0.015 + audio.y * 0.004;
      if (distanceSquared < radius * radius) {
        let amplitude = sourceStrength * (0.1 + audio.y * 0.32 + audio.z * 0.14);
        let shape = splash(distanceSquared, radius) * (1.0 - age / 0.1);
        height -= amplitude * shape;
        foam += amplitude * shape * 0.16;
      }
    }
  }

  textureStore(dataTextureA, pixel, vec4<f32>(
    clamp(height, -1.5, 1.5),
    clamp(velocity, -0.8, 0.8),
    clamp(foam, 0.0, 1.5),
    phase));
}
