// ═══════════════════════════════════════════════════════════════════
//  gen_capabilities v3 — Optimized
//  Category: generative / system-monitor
//  Upgrades: branchless-bars, halton-noise, named-consts, pm-alpha,
//            binding-contract-order, uniform-branch-removal
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ── Palette & Tuning ─────────────────────────────────────────────
const GRID_COL    = vec3<f32>(0.00, 0.10, 0.10);
const CURSOR_A    = vec3<f32>(0.00, 1.00, 1.00);
const CURSOR_B    = vec3<f32>(1.00, 0.00, 1.00);
const CROSS_COL   = vec3<f32>(0.00, 1.00, 0.00);
const BAR_COL     = vec3<f32>(0.00, 0.80, 0.20);
const SCAN_COL    = vec3<f32>(0.50, 0.50, 1.00);
const GRID_SZ     = 4.0;
const GRID_W      = 0.02;
const CURSOR_R    = 0.05;
const CROSS_R     = 0.20;
const TRAIL_DECAY = 0.92;
const NOISE_AMP   = 0.04;
const SCAN_SPEED  = 0.20;
const GLITCH_AMP  = 2.0;

// ── Halton-style hash (less banding than bare fractal) ───────────
fn halton2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ── Segment SDF ──────────────────────────────────────────────────
fn segment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = uv - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return smoothstep(0.005, 0.0, length(pa - ba * h));
}

// ── Primary controls (branchless, uniform-driven) ────────────────
fn applyControls(rgb: vec3<f32>, a: f32) -> vec4<f32> {
  let intensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speed     = mix(0.25, 5.00, clamp(u.zoom_params.y, 0.0, 1.0));
  let pulse     = 0.92 + 0.08 * sin(u.config.x * speed);
  let contrast  = mix(0.75, 1.60, clamp(u.zoom_params.z, 0.0, 1.0));
  let mDist     = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mInf      = mix(0.95, 1.15, clamp(u.zoom_params.w * mDist * 2.0, 0.0, 1.0));
  let tuned     = pow(max(rgb * intensity * pulse * mInf, vec3<f32>(0.0)), vec3<f32>(1.0 / contrast));
  return vec4<f32>(tuned * a, a);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res  = u.config.zw;
  let uv   = vec2<f32>(gid.xy) / res;
  let px   = vec2<i32>(gid.xy);
  let time = u.config.x;

  // Aspect-correct NDC
  let aspect = res.x / res.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;
  var mouse = u.zoom_config.yz * 2.0 - 1.0;
  mouse.x *= aspect;

  var color = vec3<f32>(0.0);

  // ── 1. Grid ────────────────────────────────────────────────────
  let grid = abs(fract(p * GRID_SZ - 0.5) - 0.5);
  let gridLine = 1.0 - smoothstep(0.0, GRID_W, min(grid.x, grid.y));
  color += GRID_COL * gridLine;

  // ── 2. Cursor (branchless uniform blend via step) ──────────────
  let d = length(p - mouse);
  let cursor = 1.0 - smoothstep(0.0, CURSOR_R, d);
  let clickT = step(0.5, u.zoom_config.w);
  let cursorColor = mix(CURSOR_A, CURSOR_B, clickT);
  color += cursorColor * cursor;

  // ── 3. Crosshairs ──────────────────────────────────────────────
  let cross = max(
    segment(p, mouse - vec2<f32>(CROSS_R, 0.0), mouse + vec2<f32>(CROSS_R, 0.0)),
    segment(p, mouse - vec2<f32>(0.0, CROSS_R), mouse + vec2<f32>(0.0, CROSS_R))
  );
  color += CROSS_COL * cross * 0.5;

  // ── 4. Data Bars (branchless position mask) ────────────────────
  let barId = floor(uv.x * 20.0);
  let barH  = halton2(vec2<f32>(barId, floor(time * 5.0))) * 0.08;
  let inZone = 1.0 - smoothstep(0.0, 0.1, uv.y);   // bottom strip
  let inBar  = 1.0 - smoothstep(0.0, barH, uv.y);   // per-bar height
  color += BAR_COL * inZone * inBar;

  // ── 5. Scanline ────────────────────────────────────────────────
  let scanY = fract(time * SCAN_SPEED) * 2.0 - 1.0;
  let scan = 1.0 - smoothstep(0.0, 0.01, abs(p.y - scanY));
  color += SCAN_COL * scan * 0.3;

  // ── 6. Glitch history (single textureLoad, no sampler cost) ────
  let glitch = vec2<i32>(i32(sin(uv.y * 50.0 + time * 10.0) * GLITCH_AMP * u.zoom_config.w), 0);
  let hist = textureLoad(dataTextureC, px + glitch, 0).rgb * TRAIL_DECAY;
  color = max(color, hist);

  // Film grain via Halton (same cost, less banding)
  color += (halton2(uv + fract(time * 0.137)) - 0.5) * NOISE_AMP;

  // Alpha encodes bloom weight for post-process slot chaining
  let bloom = gridLine * 0.15 + cursor * 0.5 + scan * 0.35;
  let alpha = clamp(bloom + length(color) * 0.25, 0.0, 1.0);
  let out = applyControls(color, alpha);

  textureStore(writeTexture, px, out);
  textureStore(dataTextureA, gid.xy, vec4<f32>(color, alpha));
}
