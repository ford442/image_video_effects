// Wave Tank — Pass 2: inject mouse, ripples, and audio-driven sources

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let sourceStrength = mix(0.1, 1.0, u.zoom_params.z) * (1.0 + bass * 0.35);

  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var height = state.r;
  var velocity = state.g;
  let prevHeight = state.b;
  var phase = state.a;

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDistSq = dot(uv - mouse, uv - mouse);
  let mouseRadius = 0.02;
  if (mouseDistSq < mouseRadius * mouseRadius) {
    let wave = sin(time * 10.0) * sourceStrength * 0.5;
    height = height + wave * (1.0 - sqrt(mouseDistSq) / mouseRadius);
    phase = phase + 0.02;
  }

  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 0.5) {
        let distSq = dot(uv - ripple.xy, uv - ripple.xy);
        let radius = 0.015;
        if (distSq < radius * radius) {
          let strength = (1.0 - rippleAge / 0.5) * sourceStrength;
          height = height + strength * (1.0 - sqrt(distSq) / radius);
        }
      }
    }
  }

  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(height, velocity, prevHeight, phase));
}
