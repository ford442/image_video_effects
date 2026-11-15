// ═══════════════════════════════════════════════════════════════
//  RGB ISO Lines
//  Category: interactive-mouse
//  Features: parallax, contour-lines, wavelength-dependent-alpha,
//            audio-reactive, upgraded-rgba, iso-runners, held-drag,
//            bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23, 2026-11-15
//  Ideas: index contours; downslope ticks
//  A packing: linear display RGBA (ACES on writeTexture). C is that composite
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const WAVELENGTH_RED: f32 = 650.0;
const WAVELENGTH_GREEN: f32 = 550.0;
const WAVELENGTH_BLUE: f32 = 450.0;

fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn isoLine(v: f32, freq: f32, width: f32) -> f32 {
    let d = abs(fract(v * freq) - 0.5);
    return smoothstep(0.5 - width - 0.02, 0.5 - width, d);
}

// Every fifth contour: the coarse fract (freq/5) is near a boundary.
fn indexWeight(v: f32, freq: f32) -> f32 {
    let coarse = abs(fract(v * freq * 0.2) - 0.5);
    return smoothstep(0.42, 0.50, coarse);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(pixel) / vec2<f32>(dims);
  let time = u.config.x;
  let held = f32(u.zoom_config.w > 0.5);
  let mouse = u.zoom_config.yz;
  let prev = textureLoad(dataTextureC, pixel, 0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let thickness = mix(0.01, 0.45, u.zoom_params.x) * (1.0 + mids * 0.4);
  let freq = mix(5.0, 50.0, u.zoom_params.y) * (1.0 + bass * 0.5);
  let parallax_amt = mix(0.0, 0.1, u.zoom_params.z) * (1.0 + treble * 0.5) * (1.0 + held * 0.35);
  let offset = (mouse - vec2<f32>(0.5)) * parallax_amt;

  let r_val = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g_val = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b_val = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let line_width = thickness * 0.5;
  let indexWidth = min(line_width * 2.4, 0.42);

  // ── Idea 1: index contours ──────────────────────────────────────
  // Same iso test. Every fifth line, per channel, uses the wider width.
  let r_line = max(isoLine(r_val, freq, line_width), isoLine(r_val, freq, indexWidth) * indexWeight(r_val, freq));
  let g_line = max(isoLine(g_val, freq, line_width), isoLine(g_val, freq, indexWidth) * indexWeight(g_val, freq));
  let b_line = max(isoLine(b_val, freq, line_width), isoLine(b_val, freq, indexWidth) * indexWeight(b_val, freq));
  let line_col = vec3<f32>(r_line, g_line, b_line);
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * mix(0.0, 0.5, u.zoom_params.w);
  var final_col = line_col + base;

  // ── Idea 2: downslope ticks ─────────────────────────────────────
  // Green is the unshifted field. Ticks step along its gradient and
  // only land on a contour, so the line shows which way the value falls.
  let texel = 1.0 / max(vec2<f32>(dims), vec2<f32>(1.0));
  let gDx = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g - g_val;
  let gDy = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g - g_val;
  let slope = vec2<f32>(gDx, gDy);
  let slopeLen = length(slope);
  let down = slope / max(slopeLen, 1e-4);
  let tickPhase = fract(dot(uv, down) * freq * 2.2);
  let tick = smoothstep(0.12, 0.0, abs(tickPhase - 0.5));
  let lineMask = max(r_line, max(g_line, b_line));
  let slopeGate = smoothstep(0.002, 0.02, slopeLen);
  final_col += vec3<f32>(0.92, 0.94, 0.9) * tick * lineMask * slopeGate * 0.55;

  let runners = smoothstep(0.09, 0.0, abs(fract((r_val + g_val) * freq * 0.5 - time * (1.7 + bass * 2.0)) - 0.5));
  let ticks = smoothstep(0.08, 0.0, abs(fract(uv.y * freq * 0.35 + time * 0.9) - 0.5));
  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
      click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.48) * 66.0) * (1.0 - age / 1.4));
    }
  }
  let slick = hsv2rgb(vec3<f32>(fract(g_val + time * 0.1 + mids * 0.2), 0.72, 1.0));
  final_col = mix(final_col, final_col * slick * 1.25, 0.28 + treble * 0.18);
  final_col += slick * (runners * 0.26 + ticks * 0.18 + click * 0.5);

  let parallaxLength = length(offset);
  let dispersionThickness = parallaxLength * 10.0;
  let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
  let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + click * 0.1 + lineMask * 0.08, 0.0, 1.0);
  let alphaModulatedColor = vec3<f32>(final_col.r * alphaR, final_col.g * alphaG, final_col.b * alphaB);
  let linearRgb = max(mix(alphaModulatedColor, prev.rgb * 0.86, 0.22), vec3<f32>(0.0));
  let linearA = clamp(mix(finalAlpha, prev.a * 0.86, 0.22), 0.0, 1.0);
  let shown = vec4<f32>(aces(linearRgb), linearA);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeTexture, pixel, shown);
  textureStore(dataTextureA, pixel, vec4<f32>(linearRgb, linearA));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + (r_line + g_line + b_line) * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}
