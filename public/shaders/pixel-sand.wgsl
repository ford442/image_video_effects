// Pixel Sand Falling Automata (minimal skeleton)
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // sand grid
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // temp grid
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

// GRID dimensions (tunable)
const GRID_WIDTH: u32 = 1280u;
const GRID_HEIGHT: u32 = 720u;

fn cell_index(x: u32, y: u32) -> u32 {
  return y * GRID_WIDTH + x;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let x = gid.x;
  let y = gid.y;
  if (x >= GRID_WIDTH || y >= GRID_HEIGHT) { return; }
  let idx = cell_index(x, y);
  let time = u.config.x;
  let uv = vec2<f32>(f32(x) / f32(GRID_WIDTH), f32(y) / f32(GRID_HEIGHT));
  
  var cell = textureLoad(dataTextureC, vec2<i32>(i32(x), i32(y)), 0);
  
  // Spawn grains at mouse position
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.02) {
    cell = vec4<f32>(0.8, 0.6, 0.3, 1.0);
  }
  
  // Spawn grains at ripples
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 0.5) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.03) {
          cell = vec4<f32>(0.9, 0.7, 0.4, 1.0);
        }
      }
    }
  }
  
  if (cell.a == 0.0) { // treat as empty
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), cell);
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), cell);
    return;
  }
  let mass = cell.r; // normalized
  let gravity = mix(-1.0, 2.0, mass);
  var newY = i32(y) + i32(round(gravity));
  var targetX = i32(x);
  var targetY = clamp(newY, 0, i32(GRID_HEIGHT) - 1);
  let targetCell = textureLoad(dataTextureC, vec2<i32>(targetX, targetY), 0);
  if (targetCell.a == 0.0) {
    textureStore(dataTextureB, vec2<i32>(targetX, targetY), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(targetX), i32(targetY)), cell);
  } else {
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), cell);
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), cell);
  }
}
