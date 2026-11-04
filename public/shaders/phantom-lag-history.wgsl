// ═══════════════════════════════════════════════════════════════════
//  Phantom Lag History
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-01
//  Ideas: age-tint; luma-weighted persist; neighbor glow; attack flash
//  A packing: display RGB + luminance history in A (A.a)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let maxC = vec2<i32>(resolution) - vec2<i32>(1);

  let decayEcho = 0.9 + u.zoom_params.x * 0.09;
  let echoX = (u.zoom_params.y - 0.5) * 0.05;
  let echoY = (u.zoom_params.z - 0.5) * 0.05;
  let hueShift = u.zoom_params.w;

  let decayHistory = mix(0.005, 0.3, u.zoom_params.x);
  let glowIntensity = u.zoom_params.y * 3.0;
  let colorShift = u.zoom_params.z;
  let diffusion = u.zoom_params.w;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let currentLuma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let historyUV = clamp(uv - vec2<f32>(echoX, echoY), vec2<f32>(0.0), vec2<f32>(1.0));
  let historyCoord = clamp(vec2<i32>(historyUV * resolution), vec2<i32>(0), maxC);
  let history = textureLoad(dataTextureC, historyCoord, 0);
  let prevState = textureLoad(dataTextureC, coord, 0);
  let prevAvgLuma = prevState.a;

  // Idea 2 — luma-weighted persist (brights hang).
  let persist = mix(decayEcho, min(decayEcho + 0.06, 0.985), smoothstep(0.2, 0.85, prevAvgLuma));
  var newHistory = mix(current, history, persist);

  let old = newHistory;
  newHistory.r = mix(old.r, old.g, hueShift * 0.1);
  newHistory.g = mix(old.g, old.b, hueShift * 0.1);
  newHistory.b = mix(old.b, old.r, hueShift * 0.1);

  let newAvgLuma = mix(prevAvgLuma, currentLuma, decayHistory);
  let glowAmount = max(0.0, newAvgLuma - currentLuma);
  let glowColor = vec3<f32>(1.0, 0.85, 0.6) * glowAmount * glowIntensity;

  var displayColor = newHistory.rgb + glowColor;
  // Idea 1 — age-tint: older luma goes cooler.
  let age = clamp(newAvgLuma - currentLuma, 0.0, 1.0);
  let cool = vec3<f32>(0.75, 0.88, 1.12);
  displayColor *= mix(vec3<f32>(1.0), cool, age * 0.45 * (0.6 + treble * 0.3));
  let historyTint = vec3<f32>(
    1.0 + colorShift * 0.3,
    1.0 - colorShift * 0.1,
    1.0 - colorShift * 0.2
  );
  displayColor *= mix(vec3<f32>(1.0), historyTint, smoothstep(0.0, 0.5, newAvgLuma));
  // ── Idea 3: attack flash ─────────────────────────────────────────
  // New light flashes white before the cool age-tint takes it.
  let attack = smoothstep(0.02, 0.22, currentLuma - prevAvgLuma);
  displayColor += vec3<f32>(1.0) * attack * 0.28 * (0.45 + bass * 0.35 + mids * 0.15);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
  let boostedAvg = mix(newAvgLuma, 1.0, mouseInfluence * 0.5);

  let rippleCount = min(u32(u.config.y), 50u);
  var rippleBoost = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let ageR = time - ripple.z;
    let live = f32(ageR < 2.0 && rDist < 0.1);
    rippleBoost += smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - ageR * 0.5) * live;
  }
  let finalAvgLuma = mix(boostedAvg, 1.0, rippleBoost * 0.3);

  let ps = vec2<i32>(1, 0);
  let left = textureLoad(dataTextureC, clamp(coord - ps, vec2<i32>(0), maxC), 0);
  let right = textureLoad(dataTextureC, clamp(coord + ps, vec2<i32>(0), maxC), 0);
  let down = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let up = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let diffusedAvg = (left.a + right.a + down.a + up.a) * 0.125 + finalAvgLuma * 0.5;
  let _diff = diffusion;
  // ── Idea 4: neighbor glow ────────────────────────────────────────
  // The four luma taps already loaded for diffusion bloom where they
  // outshine the live pixel.
  let neighborLuma = (left.a + right.a + down.a + up.a) * 0.25;
  let neighborGlow = max(0.0, neighborLuma - currentLuma);
  displayColor += vec3<f32>(1.0, 0.85, 0.6) * neighborGlow * glowIntensity * 0.35;

  let luma = dot(displayColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(0.75, 1.0, luma * persist);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAlpha = mix(0.6, 1.0, depth);
  let finalAlpha = clamp((alpha + depthAlpha) * 0.5 + bass * 0.05, 0.0, 1.0);

  displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(2.0));
  displayColor = displayColor / (1.0 + displayColor * 0.3);
  let mapped = aces(max(displayColor, vec3<f32>(0.0)));

  textureStore(dataTextureA, coord, vec4<f32>(mapped, diffusedAvg));
  textureStore(writeTexture, coord, vec4<f32>(mapped, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
