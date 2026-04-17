// ═══════════════════════════════════════════════════════════════════════════════
//  Shared Memory Template - Drop-in for neighbor-heavy shaders
//  Copy this pattern for liquid, reaction-diffusion, cellular automata, etc.
//
//  TEXTURE SAMPLING GUIDE:
//  - textureLoad(tex, coord, mip): Integer pixel coords, no sampler, fastest
//    Use when: You have exact pixel coordinates (e.g., gid.xy, tile loading)
//  - textureSample(tex, sampler, uv): Normalized UV with filtering
//    Use when: You need bilinear filtering (e.g., image distortion effects)
//  - textureSampleLevel(tex, sampler, uv, lod): Explicit mip level
//    Use when: You need LOD control (e.g., Gaussian pyramid, mipmapping)
//
//  PERFORMANCE: textureLoad > textureSampleLevel(..., 0.0) > textureSample
// ═══════════════════════════════════════════════════════════════════════════════

// Your existing bindings...
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;  // Persistent data

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED MEMORY SETUP
// ═══════════════════════════════════════════════════════════════════════════════
const TILE_SIZE: u32 = 16u;
const HALO: u32 = 1u;
const TILE_PADDED: u32 = 18u;

// Declare your shared memory here (f32, vec2, vec4 as needed)
var<workgroup> tileData: array<array<f32, 18>, 18>;

// ═══════════════════════════════════════════════════════════════════════════════
// COOPERATIVE LOADING - OPTIMIZED with textureLoad
// 
// Uses textureLoad for integer pixel coordinates (faster than textureSampleLevel)
// textureLoad bypasses the sampler and is ~10-20% faster for exact pixel reads
// ═══════════════════════════════════════════════════════════════════════════════

// Helper to load with bounds clamping using textureLoad (faster!)
fn loadPixel(coord: vec2<i32>) -> f32 {
  let resI = vec2<i32>(textureDimensions(dataTextureC, 0));
  let clamped = clamp(coord, vec2<i32>(0), resI - vec2<i32>(1));
  return textureLoad(dataTextureC, clamped, 0).r;  // 0 = mip level
}

fn loadTileToSharedMemory(
  gid: vec3<u32>,
  lid: vec3<u32>,
  resolution: vec2<f32>
) {
  let resI = vec2<i32>(resolution);
  let baseCoord = vec2<i32>(gid.xy) - vec2<i32>(i32(HALO));
  
  // Center load (integer coords = use textureLoad)
  let primaryCoord = baseCoord + vec2<i32>(lid.xy);
  tileData[lid.y + HALO][lid.x + HALO] = loadPixel(primaryCoord);
  
  // Right edge
  if (lid.x == TILE_SIZE - 1u) {
    let rightCoord = baseCoord + vec2<i32>(i32(TILE_SIZE), i32(lid.y));
    tileData[lid.y + HALO][TILE_SIZE + HALO] = loadPixel(rightCoord);
  }
  
  // Bottom edge
  if (lid.y == TILE_SIZE - 1u) {
    let bottomCoord = baseCoord + vec2<i32>(i32(lid.x), i32(TILE_SIZE));
    tileData[TILE_SIZE + HALO][lid.x + HALO] = loadPixel(bottomCoord);
  }
  
  // Corner
  if (lid.x == TILE_SIZE - 1u && lid.y == TILE_SIZE - 1u) {
    let cornerCoord = baseCoord + vec2<i32>(i32(TILE_SIZE), i32(TILE_SIZE));
    tileData[TILE_SIZE + HALO][TILE_SIZE + HALO] = loadPixel(cornerCoord);
  }
  
  // Left edge (clamped by loadPixel)
  if (lid.x == 0u) {
    let leftCoord = baseCoord + vec2<i32>(-1, i32(lid.y));
    tileData[lid.y + HALO][0u] = loadPixel(leftCoord);
  }
  
  // Top edge (clamped by loadPixel)
  if (lid.y == 0u) {
    let topCoord = baseCoord + vec2<i32>(i32(lid.x), -1);
    tileData[0u][lid.x + HALO] = loadPixel(topCoord);
  }
  
  // Top-left corner
  if (lid.x == 0u && lid.y == 0u) {
    let tlCoord = baseCoord + vec2<i32>(-1, -1);
    tileData[0u][0u] = loadPixel(tlCoord);
  }
  
  workgroupBarrier();
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED MEMORY SAMPLING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════
fn sampleShared(lid: vec3<u32>, offsetX: i32, offsetY: i32) -> f32 {
  let x = clamp(i32(lid.x) + offsetX + i32(HALO), 0, 17);
  let y = clamp(i32(lid.y) + offsetY + i32(HALO), 0, 17);
  return tileData[y][x];
}

// 5-point Laplacian stencil
fn laplacianShared(lid: vec3<u32>) -> f32 {
  let c = sampleShared(lid, 0, 0);
  let l = sampleShared(lid, -1, 0);
  let r = sampleShared(lid, 1, 0);
  let b = sampleShared(lid, 0, -1);
  let t = sampleShared(lid, 0, 1);
  return (l + r + b + t - 4.0 * c);
}

// 9-point Laplacian (more accurate)
fn laplacian9Shared(lid: vec3<u32>) -> f32 {
  let c = sampleShared(lid, 0, 0);
  let l = sampleShared(lid, -1, 0);
  let r = sampleShared(lid, 1, 0);
  let b = sampleShared(lid, 0, -1);
  let t = sampleShared(lid, 0, 1);
  let lb = sampleShared(lid, -1, -1);
  let rb = sampleShared(lid, 1, -1);
  let lt = sampleShared(lid, -1, 1);
  let rt = sampleShared(lid, 1, 1);
  return (0.25 * (lb + rb + lt + rt) + 0.5 * (l + r + b + t) - 3.0 * c);
}

// Gradient
fn gradientShared(lid: vec3<u32>) -> vec2<f32> {
  let dx = sampleShared(lid, 1, 0) - sampleShared(lid, -1, 0);
  let dy = sampleShared(lid, 0, 1) - sampleShared(lid, 0, -1);
  return vec2<f32>(dx, dy) * 0.5;
}

// Normal from height field
fn normalFromHeightShared(lid: vec3<u32>, scale: f32) -> vec3<f32> {
  let dx = sampleShared(lid, 1, 0) - sampleShared(lid, -1, 0);
  let dy = sampleShared(lid, 0, 1) - sampleShared(lid, 0, -1);
  return normalize(vec3<f32>(-dx * scale, -dy * scale, 2.0));
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(workgroup_id) wid: vec3<u32>,
  @builtin(local_invocation_id) lid: vec3<u32>
) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(gid.xy) / resolution;
  
  // Bounds check
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // STEP 1: Load data into shared memory
  // ═══════════════════════════════════════════════════════════════════════════════
  loadTileToSharedMemory(gid, lid, resolution);
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // STEP 2: Your computation using shared memory (FAST!)
  // ═══════════════════════════════════════════════════════════════════════════════
  let lapH = laplacianShared(lid);
  let gradH = gradientShared(lid);
  let normal = normalFromHeightShared(lid, 1.0);
  
  // Example: Simple wave equation
  let height = sampleShared(lid, 0, 0);
  let newHeight = height + lapH * 0.1;  // Your physics here
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // STEP 3: Write output
  // ═══════════════════════════════════════════════════════════════════════════════
  let color = vec3<f32>(newHeight * 0.5 + 0.5);
  textureStore(writeTexture, gid.xy, vec4<f32>(color, 1.0));
}
