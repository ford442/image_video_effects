// Complex Domain Warping (Julia Sets) - fragment shader skeleton
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

// Fragment path depends on pipeline; we provide a compute-style render that writes to writeTexture
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dim = textureDimensions(readTexture);
  let uv = (vec2<f32>(f32(gid.x), f32(gid.y)) + vec2<f32>(0.5)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  // Map mouse position to Julia constant c
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let c_base = vec2<f32>(-0.4, 0.6);
  let c = c_base + (mouse_pos - vec2<f32>(0.5)) * 0.5;
  
  // Ripple-based orbit trap highlights
  var ripple_highlight = 0.0;
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let to_ripple = uv - ripple.xy;
        let ripple_dist = length(to_ripple);
        ripple_highlight += exp(-ripple_dist * 10.0) * exp(-ripple_age * 0.5);
      }
    }
  }
  
  var z = (uv - vec2<f32>(0.5)) * vec2<f32>(1.5, -1.5);
  var orbit_trap = vec3<f32>(1000.0);
  let max_iter = 64u;
  for (var i: u32 = 0u; i < max_iter; i = i + 1u) {
    z = vec2<f32>(z.x*z.x - z.y*z.y, 2.0*z.x*z.y) + c;
    let dist = length(z);
    if (dist < orbit_trap.x) {
      orbit_trap = vec3<f32>(dist, f32(i), f32(i) / f32(max_iter));
    }
    if (dist > 2.0) { break; }
  }
  let warp_uv = (z + vec2<f32>(1.0)) * 0.5;
  let sampled = textureSampleLevel(readTexture, u_sampler, warp_uv, 0.0);
  let hue = orbit_trap.y * 0.01 + time * 0.1;
  let sat = 1.0 - orbit_trap.z;
  let val = 1.0 / (orbit_trap.x + 0.1);
  // simple HSV-to-RGB placeholder via multiples
  var color = sampled.rgb * vec3<f32>(sat * val);
  // Add ripple highlights
  color += vec3<f32>(ripple_highlight) * vec3<f32>(0.5, 0.8, 1.0);
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(color, 1.0));
}
