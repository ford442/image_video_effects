// Fabric of Reality — Verlet integration + external forces
// Reads dataTextureC (.rg pos, .ba prev pos), writes dataTextureA

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
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * noise2D(pos * freq + vec2<f32>(time * 0.1, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let dt = 0.016;

  let gravity = mix(0.0, 0.02, u.zoom_params.z);
  let damping = mix(0.95, 0.999, u.zoom_params.w);

  let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var pos = prevState.xy;
  var prevPos = prevState.zw;

  if (length(pos) < 0.001 && length(prevPos) < 0.001) {
    pos = uv;
    prevPos = uv;
  }

  var vel = (pos - prevPos) * damping;
  vel.y = vel.y + gravity * dt;

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = pos - mouse;
  let mouseDist = length(toMouse);
  if (mouseDist < 0.15 && mouseDist > 0.001) {
    let force = (1.0 - mouseDist / 0.15) * 0.02;
    vel = vel + normalize(toMouse) * force;
  }

  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = pos - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.2 && dist > 0.001) {
          let force = (1.0 - dist / 0.2) * (1.0 - rippleAge / 2.0) * 0.03;
          vel = vel + normalize(toRipple) * force;
        }
      }
    }
  }

  let windX = fbm(pos * 4.0 + vec2<f32>(time * 0.5, 0.0), time) - 0.5;
  let windY = fbm(pos * 4.0 + vec2<f32>(0.0, time * 0.5), time) - 0.5;
  vel = vel + vec2<f32>(windX, windY) * 0.001;

  let newPrevPos = pos;
  pos = pos + vel;

  if (coord.y == 0u) {
    pos = uv;
    newPrevPos = uv;
  }

  pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(pos, newPrevPos));
}
