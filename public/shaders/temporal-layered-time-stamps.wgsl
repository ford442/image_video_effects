// ═══════════════════════════════════════════════════════════════════
//  Temporal Layered Time-Stamps
//  Category: post-processing
//  Features: temporal, history-ring
//  Complexity: Medium
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot (binding-13 infrastructure proof shader)
//
//  Samples ≥4 distinct past frames from the history ring (binding 13),
//  applying per-layer hue rotation and spiral UV distortion to create a
//  psychedelic temporal echo effect.
//
//  extraBuffer layout:
//    [0] = audio bass   [1] = audio mid   [2] = audio treble
//    [3] = reserved     [4] = historyHead (next write target)
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=echoLayers, y=warpStrength, z=colorIntensity, w=blendMix
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const TAU: f32 = 6.28318530718;

// ── Helpers ──────────────────────────────────────────────────────────────────

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = h * 6.0;
  let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
  let m = v - c;
  var rgb: vec3<f32>;
  if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else               { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + m;
}

// ── Main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;

  // Parameters
  let echoLayers  = clamp(u32(u.zoom_params.x * 7.0 + 1.0), 4u, HISTORY_DEPTH);
  let warpAmt     = u.zoom_params.y * 0.06;
  let colorSat    = 0.4 + u.zoom_params.z * 0.6;
  let blendMix    = 0.25 + u.zoom_params.w * 0.65;

  // historyHead: index of the slot we are about to write this frame.
  // Slot (historyHead - age + HISTORY_DEPTH) % HISTORY_DEPTH holds the frame
  // that is `age` frames old (age 1 = most recent stored frame).
  let historyHead = u32(extraBuffer[4]);

  // ── Base frame ──────────────────────────────────────────────────────────────
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // ── Accumulate history layers ───────────────────────────────────────────────
  var accumulated = vec4<f32>(0.0);
  var totalWeight = 0.0;

  for (var age: u32 = 1u; age <= echoLayers; age = age + 1u) {
    let layer = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;

    // Per-layer spiral UV warp: older frames warp more
    let t      = f32(age) / f32(HISTORY_DEPTH);
    let angle  = time * 0.25 + f32(age) * TAU / f32(HISTORY_DEPTH);
    let warpUV = uv + vec2<f32>(
      sin(angle + uv.y * 7.0 + time * 0.3) * warpAmt * t,
      cos(angle + uv.x * 7.0 + time * 0.3) * warpAmt * t
    );
    let sampleUV = clamp(warpUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample the history frame
    let frame = textureSampleLevel(historyTexture, u_sampler, sampleUV, i32(layer), 0.0);

    // Per-layer hue-rotated tint
    let hue  = fract(f32(age) / f32(HISTORY_DEPTH) + time * 0.04);
    let tint = vec4<f32>(hsv2rgb(hue, colorSat, 1.0), 1.0);

    // Exponential weight: recent frames count more
    let weight = exp(-t * 2.5);
    accumulated += frame * tint * weight;
    totalWeight += weight;
  }

  // Normalize
  if (totalWeight > 0.001) {
    accumulated = accumulated / totalWeight;
  }

  // ── Composite: blend base with history layers ────────────────────────────────
  let output = mix(base, accumulated, blendMix);

  textureStore(writeTexture, coord, output);
}
