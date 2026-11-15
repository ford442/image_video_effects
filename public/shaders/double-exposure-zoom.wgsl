// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Zoom
//  Category: artistic
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: plate registration drift; highlight-keyed second plate; Cauchy radial zoom-shutter streak (§12.2F); sprocket-frame edgeMask & film-rebate border
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn filmResponse(c: vec3<f32>) -> vec3<f32> {
  let safeC = max(c, vec3<f32>(0.0));
  let lifted = pow(safeC, vec3<f32>(1.15, 1.05, 0.95));
  let compressed = lifted / (lifted + vec3<f32>(0.25));
  return pow(max(compressed, vec3<f32>(0.0)), vec3<f32>(0.85));
}

fn cauchyScale(B: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.650, 0.550, 0.450) * vec3<f32>(0.650, 0.550, 0.450);
  let n = 1.0 + B / lam2;
  return n / n.y;
}

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let coord = vec2<i32>(global_id.xy);

  let time = u.config.x;
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rot = (u.zoom_params.x - 0.5) * 6.28318;
  let zoomRaw = u.zoom_params.y;
  let edgeFade = u.zoom_params.z;
  let audioReact = u.zoom_params.w;

  let zoomMod = zoomRaw + bass * audioReact * 0.4;
  let zoom = clamp(pow(2.0, (zoomMod - 0.5) * 4.0), 0.01, 100.0);

  let col1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax = (mouse - 0.5) * (1.0 - depth) * 0.08;

  // Idea 1 — analog sandwich registration drift (continuous, not strobed).
  let drift = vec2<f32>(sin(time * 0.37), cos(time * 0.29)) * (0.003 + treble * 0.002);

  var uv2 = uv - mouse + parallax + drift;
  uv2.x = uv2.x * aspect;
  let c = cos(rot);
  let s = sin(rot);
  uv2 = vec2<f32>(uv2.x * c - uv2.y * s, uv2.x * s + uv2.y * c);
  uv2.x = uv2.x / aspect;
  uv2 = uv2 / zoom;
  uv2 = uv2 + mouse;

  let edgeDist = min(min(uv2.x, 1.0 - uv2.x), min(uv2.y, 1.0 - uv2.y));
  let edgeMask = smoothstep(0.0, 0.05 + edgeFade * 0.45, edgeDist);

  // ── Idea 3: radial zoom-rack streak & Cauchy focal dispersion (§12.2F) ─
  // Racking a zoom barrel during exposure pulls radial streaks from the pivot
  // with non-linear R/G/B focal magnification rather than a flat diagonal shift.
  let radialFromPivot = uv2 - mouse;
  let zoomExcursion = abs(zoomMod - 0.5) * 1.6 + bass * audioReact * 0.35;
  let dispersionB = (0.0022 + (1.0 - edgeMask) * 0.0055) * (0.35 + zoomExcursion);
  let cScale = cauchyScale(dispersionB);
  var accumPlate2 = vec3<f32>(0.0);
  for (var tap = -1; tap <= 1; tap = tap + 1) {
    let shutterScale = 1.0 + f32(tap) * 0.014 * zoomExcursion;
    let rTap = clamp(mouse + radialFromPivot * cScale.x * shutterScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let gTap = clamp(mouse + radialFromPivot * cScale.y * shutterScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let bTap = clamp(mouse + radialFromPivot * cScale.z * shutterScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let wTap = select(0.25, 0.50, tap == 0);
    accumPlate2 += vec3<f32>(
      textureSampleLevel(readTexture, u_sampler, rTap, 0.0).r,
      textureSampleLevel(readTexture, u_sampler, gTap, 0.0).g,
      textureSampleLevel(readTexture, u_sampler, bTap, 0.0).b
    ) * wTap;
  }
  var col2 = vec4<f32>(
    accumPlate2,
    textureSampleLevel(readTexture, u_sampler, clamp(uv2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a
  );

  let lum1 = luminance(col1.rgb);
  let lum2 = luminance(col2.rgb);
  // Idea 2 — highlight-keyed second plate (bright plate-2 prints through).
  let highlightKey = smoothstep(0.45, 0.82, lum2);
  let matte = mix(smoothstep(0.1, 0.6, lum2), highlightKey, 0.7);

  let screen = 1.0 - (1.0 - col1.rgb) * (1.0 - col2.rgb);
  let soft = 2.0 * col1.rgb * col2.rgb + col1.rgb * col1.rgb * (1.0 - 2.0 * col2.rgb);
  let blendedRGB = mix(screen, soft, matte * 0.5);

  // ── Idea 4: sprocket-frame edgeMask gate & warm film-rebate border ─────
  // Clamped out-of-frame pixels fade cleanly via edgeMask instead of smearing,
  // with a subtle amber rebate line right at Plate 2's negative frame edge.
  let plateExposure = (0.55 + highlightKey * 0.35) * edgeMask;
  let rebateBorder = exp(-pow((edgeDist - 0.008) / 0.012, 2.0)) * step(0.0, edgeDist) * (1.0 - edgeFade * 0.65);
  let keyed = mix(col1.rgb, blendedRGB, plateExposure) + vec3<f32>(0.18, 0.08, 0.02) * rebateBorder;

  var film = filmResponse(keyed);
  let inFrameLeak = smoothstep(0.4, 0.0, max(edgeDist, 0.0)) * step(-0.02, edgeDist) * (0.1 + bass * 0.15);
  film += vec3<f32>(inFrameLeak * 1.2, inFrameLeak * 0.6, inFrameLeak * 0.2);
  let vignette = 1.0 - smoothstep(0.3, 0.8, clamp(edgeDist, 0.0, 1.0)) * 0.5 * edgeMask;
  film = acesToneMap(max(film * vignette, vec3<f32>(0.0)) * (1.0 + mids * 0.3));

  let prevFrame = textureLoad(dataTextureC, coord, 0);
  let trailAmt = 0.12 + bass * audioReact * 0.2;
  let finalRGB = mix(film, prevFrame.rgb, trailAmt);

  let blendRatio = (matte * 0.5 + 0.3) * mix(0.35, 1.0, edgeMask);
  let lumConfidence = smoothstep(0.05, 0.5, max(lum1, lum2));
  let alpha = clamp(col1.a * 0.25 + blendRatio * lumConfidence * (0.4 + depth * 0.6), 0.0, 1.0);
  let finalColor = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
