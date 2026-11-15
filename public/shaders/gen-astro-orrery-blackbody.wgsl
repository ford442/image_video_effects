// ═══════════════════════════════════════════════════════════════════
//  Astro Orrery Blackbody
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: flanking orrery rings; blackbody chromaticity (§12.2F); orbital wake
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Tanner Helland, 1000–12000 K. ~2000 K is the original annulus orange.
fn blackbodyChromaticity(kelvin: f32) -> vec3<f32> {
  let t = clamp(kelvin, 1000.0, 12000.0) * 0.01;
  let hot = t >= 66.0;
  let r = select(1.0, clamp(329.69873 * pow(max(t - 60.0, 0.05), -0.13320476) / 255.0, 0.0, 1.0), hot);
  let gLo = clamp((99.4708026 * log(max(t, 0.05)) - 161.119568) / 255.0, 0.0, 1.0);
  let gHi = clamp((288.12217 * pow(max(t - 60.0, 0.05), -0.07551485)) / 255.0, 0.0, 1.0);
  let g = select(gLo, gHi, hot);
  let bLo = clamp((138.51773 * log(max(t - 10.0, 0.05)) - 305.0448) / 255.0, 0.0, 1.0);
  let b = select(select(0.0, bLo, t > 19.0), 1.0, hot);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<u32>(global_id.xy);
  if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }

  let uvFull = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  var uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let ringSpread = clamp(u.zoom_params.x, 0.0, 1.0);
  let temperature = clamp(u.zoom_params.y, 0.0, 1.0);
  let trailAmt = clamp(u.zoom_params.z, 0.0, 1.0);
  let starDensity = clamp(u.zoom_params.w, 0.0, 1.0);

  // The pointer shifts the mechanism. At the centre of the frame the offset is zero.
  let mouse = u.zoom_config.yz;
  let center = (mouse - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 0.45;
  uv = uv - center;

  var col = vec3<f32>(0.0);

  let thresh = mix(0.992, 0.90, starDensity);
  for (var i = 1.0; i < 4.0; i = i + 1.0) {
    let st = uv * i * 5.0 + time * 0.05 / i;
    let id = floor(st);
    let fst = fract(st) - 0.5;
    let rand = hash12(id);
    let starOn = step(thresh, rand);
    let starGlow = starOn * 0.01 / (length(fst) + 0.001);
    // ── Idea 2: star temperature from the existing hash (§12.2F) ────
    let starK = mix(2800.0, 11000.0, rand);
    col += blackbodyChromaticity(starK) * starGlow * (1.0 + treble * 2.0);
  }

  let r = length(uv);
  let a = atan2(uv.y, uv.x);
  let diskFreq = 20.0 - mids * 5.0;
  let diskPattern = max(sin(r * diskFreq - time * 2.0 + a * 3.0), 0.0);
  let mainMask = smoothstep(0.4, 0.3, r) * smoothstep(0.1, 0.15, r);
  let mainK = mix(1400.0, 9000.0, temperature);
  let bassGain = 1.0 + bass * 3.0;
  // Default temperature 0.08 ≈ 2000 K, the original orange (1, 0.5, 0.1).
  col += blackbodyChromaticity(mainK) * diskPattern * mainMask * bassGain;

  // ── Idea 1: same spiral on an inner and an outer ring ─────────────
  let flank = smoothstep(0.08, 0.45, ringSpread);
  let innerMask = smoothstep(0.10, 0.055, r) * smoothstep(0.02, 0.04, r);
  let outerMask = smoothstep(0.62, 0.50, r) * smoothstep(0.40, 0.46, r);
  col += blackbodyChromaticity(min(mainK + 2800.0, 12000.0)) * diskPattern * innerMask * flank * bassGain * 0.85;
  col += blackbodyChromaticity(max(mainK - 550.0, 1000.0)) * diskPattern * outerMask * flank * bassGain * 0.75;

  let inputColor = textureSampleLevel(readTexture, u_sampler, clamp(uvFull, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  var finalRGB = mix(inputColor.rgb, col, 0.6);

  // ── Idea 3: orbital wake, a step against the spiral's rotation ────
  let tang = vec2<f32>(-sin(a), cos(a));
  let prevFull = clamp(uvFull - tang * 6.0 / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
  let prevPx = clamp(vec2<i32>(prevFull * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let prevColor = textureLoad(dataTextureC, prevPx, 0).rgb;
  finalRGB = mix(finalRGB, prevColor, trailAmt);

  let alpha = clamp(inputColor.a * 0.25 + mainMask * 0.55 + flank * (innerMask + outerMask) * 0.35 + length(col) * 0.08, 0.0, 1.0);
  let mapped = aces(max(finalRGB, vec3<f32>(0.0)));
  textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvFull, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(sceneDepth, 1.0 - mainMask, 0.4), 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(mapped, alpha));
}
