// ═══════════════════════════════════════════════════════════════════
//  Oscilloscope Overlay
//  Category: image
//  Features: mouse-driven, overlay, hdr-ready
//  Complexity: Low
//  Chunks From: original oscilloscope-overlay
//  Created: 2026-05-03
//  By: Optimizer
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
  zoom_params: vec4<f32>,  // x=Amplitude, y=Thickness, z=WaveOpacity, w=ScanAlpha
  ripples: array<vec4<f32>, 50>,
};

const LUMA_WEIGHTS: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);
const SCAN_COLOR: vec3<f32> = vec3<f32>(1.0, 0.2, 0.2);
const PHOSPHOR_COLOR: vec3<f32> = vec3<f32>(0.2, 1.0, 0.5);
const GRID_COLOR: vec3<f32> = vec3<f32>(0.12, 0.25, 0.12);
const CENTER_Y: f32 = 0.5;

fn luma(color: vec3<f32>) -> f32 {
  return dot(color, LUMA_WEIGHTS);
}

// Branchless grid intensity for oscilloscope aesthetic
fn gridIntensity(uv: vec2<f32>, spacing: f32, thick: f32) -> f32 {
  let g = fract(uv / spacing + 0.5);
  let d = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)) * spacing;
  return smoothstep(thick, 0.0, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / res;

  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
    return;
  }

  // Parameters
  let amplitude = u.zoom_params.x;
  let thickness = max(0.001, u.zoom_params.y * 0.02);
  let waveOpacity = u.zoom_params.z;
  let scanAlpha = u.zoom_params.w;
  let scanY = u.zoom_config.z;

  // Background sample
  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Shared scanline sample for scan indicator + waveform
  let scanUV = vec2<f32>(uv.x, scanY);
  let scanSample = textureSampleLevel(readTexture, u_sampler, scanUV, 0.0).rgb;
  let scanLuma = luma(scanSample);

  // Scan line indicator
  let distScan = abs(uv.y - scanY);
  let scanLine = smoothstep(thickness, 0.0, distScan) * scanAlpha;

  // Waveform: luma-driven Y displacement
  let waveY = CENTER_Y + (scanLuma - CENTER_Y) * amplitude;
  let distWave = abs(uv.y - waveY);
  let waveVal = smoothstep(thickness, 0.0, distWave) * waveOpacity;

  // Subtle branchless oscilloscope grid
  let gridVal = gridIntensity(uv, 0.1, 0.001) * 0.12;

  // Composite: mix scan line, add waveform and grid
  var col = bg;
  col = mix(col, SCAN_COLOR, scanLine);
  col = col + PHOSPHOR_COLOR * waveVal;
  col = col + GRID_COLOR * gridVal;

  // HDR-ready: alpha carries bloom weight for downstream tone mapping
  let bloomWeight = scanLine * 0.5 + waveVal * 0.8 + gridVal * 0.15;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, bloomWeight));
}
