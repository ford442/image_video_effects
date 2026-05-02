// ═══════════════════════════════════════════════════════════════════
//  Elastic Chromatic
//  Category: image
//  Features: mouse-driven, depth-aware, temporal, audio-reactive
//  Complexity: Low
//  Description: Chromatic channel lag with depth-aware modulation,
//               mouse proximity influence, and optional audio reactivity.
//               HDR-ready for downstream tone-mapping.
//  Bloom Threshold: 0.85
//  Recommended Slot: 1 or 2 (reads from upstream effect)
// ═══════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=LagRed, y=LagBlue, z=MouseInfluence, w=GreenLag
  ripples: array<vec4<f32>, 50>,
};

// ─── Quality & Tuning Constants ────────────────────────────────────
// MAX_LAG caps feedback to prevent complete freeze (still frame).
// MOUSE_FALLOFF controls the radius of mouse proximity influence.
// DEPTH_MIX scales how much depth drives extra lag on background pixels.
// BLUE_SCALE / GREEN_SCALE attenuate per-channel mouse sensitivity.
// AUDIO_SCALE determines how much bass frequencies boost lag.
const MAX_LAG: f32 = 0.995;
const MOUSE_FALLOFF: f32 = 0.5;
const DEPTH_MIX: f32 = 0.35;
const BLUE_SCALE: f32 = 0.5;
const GREEN_SCALE: f32 = 0.3;
const AUDIO_SCALE: f32 = 0.15;

// ─── Helper Functions ──────────────────────────────────────────────
// Returns 0..1 influence based on screen-space distance to mouse.
// Aspect-corrected so the influence radius is circular.
fn mouse_influence(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> f32 {
    let d = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    return smoothstep(MOUSE_FALLOFF, 0.0, d) * strength;
}

// Exponential moving average: blends current sample with history.
// lag = 0.0 → instant response. lag = 0.995 → heavy ghosting.
fn ema(current: f32, history: f32, lag: f32) -> f32 {
    return mix(current, history, lag);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let texel = vec2<i32>(global_id.xy);
    
    // Early exit for out-of-bounds workgroups
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // ─── Uniform Parameters ────────────────────────────────────────
    let baseLagR = u.zoom_params.x;
    let baseLagB = u.zoom_params.y;
    let mouseInfluence = u.zoom_params.z;
    let baseLagG = u.zoom_params.w;

    // ─── Minimized Texture Sampling ────────────────────────────────
    // Only three texture samples per pixel:
    //   1. Current frame color from upstream slot
    //   2. Feedback history from dataTextureC (previous frame output)
    //   3. Depth buffer for depth-aware modulation
    let curr = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ─── Modulation Sources ────────────────────────────────────────
    // Depth-aware lag: objects farther from camera (depth near 0.0)
    // accumulate more temporal lag, creating atmospheric separation.
    let depthMod = (1.0 - depth) * DEPTH_MIX;
    
    // Mouse proximity increases lag, creating a "drag" zone around cursor.
    let mouse = u.zoom_config.yz;
    let influence = mouse_influence(uv, mouse, aspect, mouseInfluence);
    
    // Audio reactivity: bass from plasmaBuffer adds micro-lag on beats.
    let audioBoost = plasmaBuffer[0].x * AUDIO_SCALE;

    // ─── Per-Channel Effective Lag ─────────────────────────────────
    // Red gets full mouse + depth + audio modulation.
    // Blue gets attenuated mouse and depth (classic anaglyph feel).
    // Green gets attenuated mouse only, keeping structural anchoring.
    let lagR = clamp(baseLagR + influence + depthMod + audioBoost, 0.0, MAX_LAG);
    let lagB = clamp(baseLagB + influence * BLUE_SCALE + depthMod * BLUE_SCALE + audioBoost, 0.0, MAX_LAG);
    let lagG = clamp(baseLagG + influence * GREEN_SCALE + audioBoost, 0.0, MAX_LAG);

    // ─── Chromatic Exponential Moving Average ──────────────────────
    let outR = ema(curr.r, history.r, lagR);
    let outG = ema(curr.g, history.g, lagG);
    let outB = ema(curr.b, history.b, lagB);

    // HDR / Pipeline Integration:
    // Preserve input alpha so downstream slots or tone-mapping get correct coverage.
    let finalColor = vec4<f32>(outR, outG, outB, curr.a);

    // ─── Pipeline Outputs ──────────────────────────────────────────
    // writeTexture: primary output for display or next chained slot
    // dataTextureA: feedback history buffer (sampled as dataTextureC next frame)
    // writeDepthTexture: clear depth to avoid stale values leaking
    textureStore(writeTexture, texel, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
