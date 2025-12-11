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
  let cell = textureLoad(readTexture, vec2<i32>(i32(x), i32(y)), 0);
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
  let targetCell = textureLoad(readTexture, vec2<i32>(targetX, targetY), 0);
  if (targetCell.a == 0.0) {
    textureStore(dataTextureB, vec2<i32>(targetX, targetY), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(targetX), i32(targetY)), cell);
  } else {
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), cell);
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), cell);
  }
}
