// ═══ RIPPLE TANK — PASS 2/3: COARSE OPTICS GATHER ══════════════════════════
//  Category: simulation (multipass 2 of 3: step → optics gather → render)
//
//  Reduces the previous-frame wave field (dataTextureC) into a 10×10 coarse
//  "caustic energy" grid stored in extraBuffer. Pass 3 samples the grid
//  bilinearly the SAME frame — extraBuffer is the only same-frame channel in
//  the 13-binding contract (dataTextureA/B are bound write-only, and the CPU
//  re-zeroes extraBuffer[133..255] every frame, so this is frame-local).
//
//  extraBuffer layout used by this chain (audio owns [0..132]):
//    [140 + cy*10 + cx]  mean |∇²u| over cell (cx, cy) — caustic focus energy
//
//  Exactly one thread writes each cell (the thread at the cell's centre
//  pixel), so writes are race-free. All other threads only pass depth through
//  so the depth chain stays coherent mid-chain.
//
//  dataTextureB is never referenced so its feedback copy stays disabled and
//  pass 1's committed state in dataTextureA survives to the next frame.

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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x wave speed, .y damping, .z source, .w boundary
  ripples: array<vec4<f32>, 50>,
};

const GRID: i32 = 10;
const GRID_BASE: i32 = 140;

fn loadHeight(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    let p = clamp(pixel, vec2<i32>(0), res - vec2<i32>(1));
    return textureLoad(dataTextureC, p, 0).r;
}

// Cheap 3×3 cross Laplacian at a sample point
fn laplacian3x3(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    let c = loadHeight(pixel, res);
    let l = loadHeight(pixel + vec2<i32>(-1, 0), res);
    let r = loadHeight(pixel + vec2<i32>( 1, 0), res);
    let t = loadHeight(pixel + vec2<i32>( 0,-1), res);
    let b = loadHeight(pixel + vec2<i32>( 0, 1), res);
    return l + r + t + b - 4.0 * c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let resI = vec2<i32>(res);

    // Depth pass-through so the chain always carries a valid depth mid-chain
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // ── One representative thread per coarse cell does the gather ──────────
    let cellSize = res / f32(GRID);
    let cx = clamp(i32(f32(pixel.x) / cellSize.x), 0, GRID - 1);
    let cy = clamp(i32(f32(pixel.y) / cellSize.y), 0, GRID - 1);
    let centre = vec2<i32>(
        i32((f32(cx) + 0.5) * cellSize.x),
        i32((f32(cy) + 0.5) * cellSize.y)
    );
    if (pixel.x != centre.x || pixel.y != centre.y) { return; }

    // 7×7 stratified samples across the cell, mean absolute curvature.
    // |∇²u| peaks where wavefronts focus — exactly where caustics form.
    let stride = cellSize / 7.0;
    var energy = 0.0;
    for (var j = -3; j <= 3; j++) {
        for (var i = -3; i <= 3; i++) {
            let sp = centre + vec2<i32>(
                i32(f32(i) * stride.x),
                i32(f32(j) * stride.y)
            );
            energy += abs(laplacian3x3(sp, resI));
        }
    }
    energy /= 49.0;

    extraBuffer[GRID_BASE + cy * GRID + cx] = energy;
}
