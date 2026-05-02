// ═══════════════════════════════════════════════════════════════════
//  Digital Lens
//  Category: image
//  Features: mouse-driven, expects-pp-tone-map
//  Complexity: Medium
//  Chunks From: original digital-lens
//  Created: 2026-05-02
//  By: Optimizer Agent
// ═══════════════════════════════════════════════════════════════════

// ── IMMUTABLE 13-BINDING CONTRACT ─────────────────────────────────
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
// ─────────────────────────────────────────────────────────────────

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BlockSize, y=Radius, z=GridOpacity, w=ColorTint
  ripples: array<vec4<f32>, 50>,
};

// ═══ TUNABLE CONSTANTS ════════════════════════════════════════════
const EDGE_SOFTNESS: f32 = 0.05;
const BLOCK_SCALE: f32 = 50.0;
const BLOCK_MIN: f32 = 2.0;
const RADIUS_SCALE: f32 = 0.4;
const RADIUS_MIN: f32 = 0.05;
const TINT_G: f32 = 0.2;
const TINT_BOOST: f32 = 1.5;

// ═══ HELPER FUNCTIONS ═════════════════════════════════════════════

// Aspect-correct distance from UV to mouse position.
fn uv_mouse_dist(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32) -> f32 {
    return length((uv - mouse) * vec2<f32>(aspect, 1.0));
}

// Smooth lens mask: 1.0 inside radius, 0.0 outside radius + softness.
fn lens_mask(dist: f32, radius: f32) -> f32 {
    return 1.0 - smoothstep(radius, radius + EDGE_SOFTNESS, dist);
}

// Quantize UV into pixel blocks for pixelation effect.
fn quantize_uv(uv: vec2<f32>, resolution: vec2<f32>, block_size: f32) -> vec2<f32> {
    let blocks = resolution / block_size;
    return floor(uv * blocks) / blocks + (0.5 / blocks);
}

// Digital grid overlay: 1.0 on grid lines, 0.0 inside cells.
fn grid_value(uv_pixel: vec2<f32>, block_size: f32) -> f32 {
    let gx = step(block_size - 1.0, uv_pixel.x % block_size);
    let gy = step(block_size - 1.0, uv_pixel.y % block_size);
    return max(gx, gy);
}

// Apply matrix-style green tint. Output is HDR-ready (may exceed 1.0).
fn apply_matrix_tint(color: vec4<f32>, strength: f32) -> vec4<f32> {
    let tint = vec4<f32>(0.0, 1.0, TINT_G, 1.0);
    return mix(color, color * tint * TINT_BOOST, strength);
}

// ═══ MAIN COMPUTE KERNEL ══════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);

    // Bounds check
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // ── Parameter unpacking ─────────────────────────────────────
    let block_size = max(BLOCK_MIN, u.zoom_params.x * BLOCK_SCALE + BLOCK_MIN);
    let radius = u.zoom_params.y * RADIUS_SCALE + RADIUS_MIN;
    let grid_opacity = u.zoom_params.z;
    let tint_strength = u.zoom_params.w;

    // ── Lens distance & early exit ──────────────────────────────
    let dist = uv_mouse_dist(uv, mouse, aspect);
    let mask = lens_mask(dist, radius);

    // Early exit: pixels completely outside the lens incur one sample only.
    if (mask <= 0.0) {
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, pixel, original);
        return;
    }

    // ── Core lens effect ────────────────────────────────────────
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let q_uv = quantize_uv(uv, resolution, block_size);
    let pixelated = textureSampleLevel(readTexture, non_filtering_sampler, q_uv, 0.0);

    var lens = apply_matrix_tint(pixelated, tint_strength);

    let grid = grid_value(uv * resolution, block_size);
    lens = mix(lens, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid * grid_opacity);

    // Soft compositing with original (HDR-safe mix)
    let out_color = mix(original, lens, mask);

    textureStore(writeTexture, pixel, out_color);
}
