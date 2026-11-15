// ═══════════════════════════════════════════════════════════════════
//  Gen String Theory Structure
//  Category: advanced-hybrid
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: string core and sheath; fold-count material (§12.2E); rotational wake
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<u32>(global_id.xy);
  if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }

  let uvFull = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let gap = mix(0.28, 0.72, clamp(u.zoom_params.x, 0.0, 1.0));
  let vibeFreq = mix(8.0, 32.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let trailAmt = clamp(u.zoom_params.z, 0.0, 1.0);
  let glowAmp = mix(0.02, 0.08, clamp(u.zoom_params.w, 0.0, 1.0));

  var z = uv * 3.0;
  var folds = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    let angle = time * 0.2 + length(z) * (1.0 + bass * 0.5);
    let c = cos(angle);
    let s = sin(angle);
    z = vec2<f32>(c * z.x - s * z.y, s * z.x + c * z.y);
    // ── Idea 2: fold-count material (§12.2E), signs before abs ──────
    folds = folds + select(0.0, 1.0, z.x < 0.0) + select(0.0, 1.0, z.y < 0.0);
    z = abs(z) - vec2<f32>(gap + mids * 0.2);
    z = z * 1.5;
  }

  let dist = length(z);
  let vibe = sin(dist * vibeFreq - time * 5.0) * cos(z.x * 15.0 + time * 3.0);
  let av = abs(vibe);

  // ── Idea 1: tight core plus a wider sheath. Default peak matches ──
  // the old 0.05 / 0.01 spike (glowAmp 0.5 → 0.05).
  let core = (glowAmp * 0.8) / (av + 0.008);
  let sheath = (glowAmp * 2.4) / (av + 0.06);
  let glow = core * 0.86 + sheath * 0.35;

  var col = vec3<f32>(0.5 + 0.5 * sin(z.x * 5.0), 0.5 + 0.5 * cos(z.y * 5.0), 0.8) * glow * (0.5 + treble);
  let foldMat = clamp(folds / 8.0, 0.0, 1.0);
  col = mix(col, col * vec3<f32>(0.55, 0.85, 1.15) + vec3<f32>(0.04, 0.07, 0.14) * glow, foldMat * 0.55);

  let inputColor = textureSampleLevel(readTexture, u_sampler, clamp(uvFull, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  var finalRGB = mix(inputColor.rgb, col, 0.7);

  // ── Idea 3: unwind one step of the domain rotation ────────────────
  let back = 0.018;
  let cs = cos(back);
  let sn = sin(back);
  let spun = vec2<f32>(cs * uv.x + sn * uv.y, -sn * uv.x + cs * uv.y);
  let prevFull = clamp((spun * resolution.y + resolution * 0.5) / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
  let prevPx = clamp(vec2<i32>(prevFull * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let prevColor = textureLoad(dataTextureC, prevPx, 0).rgb;
  finalRGB = mix(finalRGB, prevColor, trailAmt);

  let alpha = clamp(inputColor.a * 0.2 + clamp(glow, 0.0, 1.0) * 0.65 + foldMat * 0.15, 0.0, 1.0);
  let mapped = aces(max(finalRGB, vec3<f32>(0.0)));
  textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvFull, 0.0).r;
  let relief = clamp(glow * 0.12, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(sceneDepth, 1.0 - relief, 0.5), 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(mapped, alpha));
}
