// Lenia-style Continuous Cellular Automata (minimal skeleton)
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

const GRID_SIZE: u32 = 512u;
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  if (coord.x >= GRID_SIZE || coord.y >= GRID_SIZE) { return; }
  let idx = coord.y * GRID_SIZE + coord.x;
  let time = u.config.x;
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / f32(GRID_SIZE);
  
  var center = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rgb;
  
  // Inject seeds at mouse position
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.05) {
    center += vec3<f32>(0.3);
  }
  
  // Spawn seeds via ripples
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 1.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.04) {
          center += vec3<f32>(0.5) * (1.0 - ripple_age);
        }
      }
    }
  }
  
  var ring_sum: vec3<f32> = vec3<f32>(0.0);
  var ring_count: f32 = 0.0;
  for (var dx: i32 = -4; dx <= 4; dx = dx + 1) {
    for (var dy: i32 = -4; dy <= 4; dy = dy + 1) {
      let dist = length(vec2<f32>(f32(dx), f32(dy)));
      if (dist >= 2.0 && dist <= 4.0) {
        let sx = min(GRID_SIZE - 1u, max(0u, u32(i32(coord.x) + dx)));
        let sy = min(GRID_SIZE - 1u, max(0u, u32(i32(coord.y) + dy)));
        let s = textureLoad(dataTextureC, vec2<i32>(i32(sx), i32(sy)), 0).rgb;
        let weight = exp(-dist * 0.5);
        ring_sum = ring_sum + s * weight;
        ring_count = ring_count + weight;
      }
    }
  }
  let neighbor_avg = ring_sum / ring_count;
  let growth = (neighbor_avg - vec3<f32>(0.5)) * 2.0;
  let delta = growth * (vec3<f32>(1.0) - abs(growth)) * 0.1;
  let next = clamp(center + delta, vec3<f32>(0.0), vec3<f32>(1.0));
  textureStore(dataTextureB, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(next, 1.0));
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(next, 1.0));
}
