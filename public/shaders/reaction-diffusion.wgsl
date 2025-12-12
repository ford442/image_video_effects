// Reaction-Diffusion Color Bleed - minimal skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // chemicals as RGB
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // temp buffer
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
const FEED_RATE: f32 = 0.055;
const KILL_RATE: f32 = 0.062;

fn laplacian(coord: vec2<u32>, channel: u32) -> f32 {
  var sum: f32 = 0.0;
  let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
  var k: u32 = 0u;
  for (var i: i32 = -1; i <= 1; i = i + 1) {
    for (var j: i32 = -1; j <= 1; j = j + 1) {
      let sx = min(GRID_SIZE - 1u, max(0u, u32(i) + coord.x));
      let sy = min(GRID_SIZE - 1u, max(0u, u32(j) + coord.y));
      let idx = vec2<u32>(sx, sy);
      let sample = textureLoad(dataTextureC, vec2<i32>(i32(idx.x), i32(idx.y)), 0);
      sum = sum + sample[channel] * kernel[k];
      k = k + 1u;
    }
  }
  return sum;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  if (coord.x >= GRID_SIZE || coord.y >= GRID_SIZE) { return; }
  let idx = coord.y * GRID_SIZE + coord.x;
  let time = u.config.x;
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / f32(GRID_SIZE);
  
  var cur = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rgb;
  
  // Inject chemicals at mouse position
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.05) {
    cur += vec3<f32>(0.1, 0.0, 0.0);
  }
  
  // Spawn seeds via ripples
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 1.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.03) {
          cur += vec3<f32>(0.0, 0.1, 0.0) * (1.0 - ripple_age);
        }
      }
    }
  }
  
  let lap = vec3<f32>(laplacian(coord, 0u), laplacian(coord, 1u), laplacian(coord, 2u));
  let reaction = cur * cur * cur; // placeholder
  let dA = lap * 0.2 - reaction + FEED_RATE * (vec3<f32>(1.0) - cur);
  let dB = lap * 0.1 + reaction - (KILL_RATE + FEED_RATE) * cur;
  let next = clamp(cur + dA + dB, vec3<f32>(0.0), vec3<f32>(1.0));
  textureStore(dataTextureB, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(next, 1.0));
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(next, 1.0));
}
