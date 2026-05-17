// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples — Optimized
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive
//  Complexity: Medium
//  Upgrades: branchless pixelation, 2-sample chromatic aberration,
//            radial displacement, anti-moiré LOD bias, semantic alpha
//  Created: 2026-05-10
//  By: Phase A Upgrade Agent
// ═══════════════════════════════════════════════════════════════════

// ── Optimizer Notes ───────────────────────────────────────────────
// 1. Per-pixel if (blockSize) replaced by mix(step()) — no divergent branching.
// 2. Chromatic aberration reduced from 3 texture samples to 2.
// 3. Displacement is now radial (dir * wave) instead of diagonal scalar.
// 4. LOD bias scales with displacement magnitude to suppress aliasing.
// 5. Alpha is semantic (1.0) for correct opaque filter chaining.
// ──────────────────────────────────────────────────────────────────

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

const QUANT_STEP: f32 = 24.0;
const ATTEN_SCALE: f32 = 5.0;
const DISP_AMP: f32 = 0.01;
const EPS: f32 = 0.001;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Audio reactivity: bass drives ripple intensity
  let bass = plasmaBuffer[0].x;
  let audioBoost = 1.0 + bass * 0.5;

  // Param unpack
  let speed = u.zoom_params.x * 5.0 + 1.0;
  let blockSize = u.zoom_params.y * 0.1;
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  // Mouse-driven ripple origin
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // Radial distance and normalized direction
  let delta = uvCorrected - mouseCorrected;
  let dist = length(delta);
  let dir = delta / max(dist, 1e-6);

  // Quantized digital wave — adaptive step reduces moiré shimmer
  let quant = floor(dist * QUANT_STEP) / QUANT_STEP;
  let wave = sin(quant * frequency - time * speed);

  // Attenuate and displace radially from cursor
  let strength = 1.0 / (dist * ATTEN_SCALE + 0.5);
  let displacement = dir * wave * strength * DISP_AMP * audioBoost;
  var displacedUV = uv + displacement;

  // Branchless pixelation: mix() + step() replaces per-pixel if
  let activePixel = step(EPS, blockSize);
  let blocks = 1.0 / max(blockSize, EPS);
  let pixelated = floor(displacedUV * blocks) / blocks;
  displacedUV = mix(displacedUV, pixelated, activePixel);

  // Anti-moiré LOD bias: higher lod when displacement magnitude is large
  let lod = clamp(length(displacement) * resolution.x * 0.25, 0.0, 2.0);

  // 2-sample chromatic aberration (reduced from 3 samples)
  let offset = vec2<f32>(aberration, 0.0);
  let sR = textureSampleLevel(readTexture, u_sampler, displacedUV + offset, lod);
  let sB = textureSampleLevel(readTexture, u_sampler, displacedUV - offset, lod);

  // Reconstruct green from both taps for a balanced chromatic split
  let r = sR.r;
  let g = mix(sR.g, sB.g, 0.5);
  let b = sB.b;

  // Semantic alpha: filter output is fully opaque for correct chaining
  let color = vec4<f32>(r, g, b, 1.0);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, color);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
