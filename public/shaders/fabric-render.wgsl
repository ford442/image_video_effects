// ═══════════════════════════════════════════════════════════════════
//  Fabric of Reality — render
//  Category: simulation
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: shear springs (constraint); catenary tension (verlet); open weave; frayed yarn ends
//  A packing: commits raw (position.xy, previous.xy). Display ACES is writeTexture.
// ═══════════════════════════════════════════════════════════════════
// Tear mask via dataB load. Positions via exact C.

#include "_prelude.wgsl"

const THREAD_DENSITY: f32 = 3.0;
const FABRIC_BASE_ALPHA: f32 = 0.82;
const STRAINED_ALPHA: f32 = 0.58;
const TORN_ALPHA: f32 = 0.22;

fn fabricSSS(strain: f32, baseColor: vec3<f32>) -> vec3<f32> {
  let threadScatter = strain * 0.35;
  let gapTint = vec3<f32>(0.85, 0.88, 1.0);
  return mix(baseColor, baseColor * gapTint, threadScatter);
}

fn neighborPos(c: vec2<i32>, size: vec2<u32>, fallback: vec2<f32>) -> vec2<f32> {
  let hi = vec2<i32>(max(i32(size.x) - 1, 0), max(i32(size.y) - 1, 0));
  let p = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), hi), 0).xy;
  return select(p, fallback, length(p) < 0.001);
}

fn clothStrain(coord: vec2<u32>, size: vec2<u32>, uv: vec2<f32>, pos: vec2<f32>) -> vec3<f32> {
  // B is write-only, so the tear mask cannot be loaded. Recompute the same
  // structural and bias strain the tear pass stores.
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let restLen = texelSize.x;
  let restDiag = length(texelSize);
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
  let ic = vec2<i32>(coord);
  var totalStrain = 0.0;
  var torn = 0.0;
  if (coord.x > 0u) {
    let d = length(pos - neighborPos(ic + vec2<i32>(-1, 0), size, uv + vec2<f32>(-texelSize.x, 0.0)));
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    torn = select(torn, 1.0, d >= tearThreshold * restLen);
  }
  if (coord.y > 0u) {
    let d = length(pos - neighborPos(ic + vec2<i32>(0, -1), size, uv + vec2<f32>(0.0, -texelSize.y)));
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    torn = select(torn, 1.0, d >= tearThreshold * restLen);
  }
  if (coord.x > 0u && coord.y > 0u) {
    let d = length(pos - neighborPos(ic + vec2<i32>(-1, -1), size, uv + vec2<f32>(-texelSize.x, -texelSize.y)));
    totalStrain = totalStrain + abs(d - restDiag) / max(restDiag, 1e-5) * 0.5;
    torn = select(torn, 1.0, d >= tearThreshold * restDiag);
  }
  if (coord.x < size.x - 1u && coord.y > 0u) {
    let d = length(pos - neighborPos(ic + vec2<i32>(1, -1), size, uv + vec2<f32>(texelSize.x, -texelSize.y)));
    totalStrain = totalStrain + abs(d - restDiag) / max(restDiag, 1e-5) * 0.5;
    torn = select(torn, 1.0, d >= tearThreshold * restDiag);
  }
  return vec3<f32>(clamp(totalStrain * 2.0, 0.0, 1.0), torn, 0.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calculateFabricAlpha(strain: f32, isTorn: bool, threadDensity: f32) -> f32 {
  var alpha = FABRIC_BASE_ALPHA;
  if (isTorn) {
    alpha = TORN_ALPHA;
  } else if (strain > 0.5) {
    let stretchFactor = smoothstep(0.5, 1.0, strain);
    alpha = mix(FABRIC_BASE_ALPHA, STRAINED_ALPHA, stretchFactor);
  }
  let densityAlpha = exp(-threadDensity * 0.3);
  alpha = mix(alpha, alpha * 0.85, densityAlpha * 0.3);
  return clamp(alpha, 0.18, 0.92);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;

  let posState = textureLoad(dataTextureC, vec2<i32>(coord), 0);
  let posReady = select(posState, vec4<f32>(uv, uv), length(posState.xy) < 0.001);
  let pos = posReady.xy;
  let strainNow = clothStrain(coord, size, uv, pos);
  let totalStrain = strainNow.r;
  let isTorn = strainNow.g > 0.5;
  let weavePhase = fract(uv.x * 12.0 + uv.y * 8.0 + time * 0.2 + treble * 0.1);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, pos, 0.0);
  let fabricColor = fabricSSS(totalStrain, sourceColor.rgb);

  // Iridescent strain — psychedelic weave, not academic wireframe
  let strainColor = mix(
    vec3<f32>(0.15, 0.45, 0.95),
    vec3<f32>(1.0, 0.25, 0.55),
    totalStrain
  );
  let weaveTint = vec3<f32>(
    0.5 + 0.5 * sin(weavePhase * 6.28 + time * 0.4),
    0.5 + 0.5 * sin(weavePhase * 6.28 + 2.09 + bass * 2.0),
    0.5 + 0.5 * sin(weavePhase * 6.28 + 4.18 + treble)
  );
  var finalColor = mix(fabricColor, strainColor, totalStrain * 0.4);
  finalColor = mix(finalColor, finalColor * weaveTint, 0.22);
  if (isTorn) {
    let tearGlow = vec3<f32>(1.0, 0.45, 0.2) * strainNow.g * (0.45 + treble * 0.35);
    finalColor = finalColor + tearGlow;
  }

  // Mouse spotlight on the cloth
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(pos - mouse);
  let spotlight = exp(-mouseDist * mouseDist * 28.0) * (0.15 + u.zoom_config.w * 0.25);
  finalColor = finalColor + vec3<f32>(0.4, 0.7, 1.0) * spotlight;

  // ── Idea 3: open weave ──────────────────────────────────────────────
  // Stiffness is how tight the cloth is woven. Strain opens the gaps
  // between warp and weft so the sheet reads as yarn.
  let stiffness = clamp(u.zoom_params.x, 0.0, 1.0);
  let threads = mix(16.0, 52.0, stiffness);
  let cell = fract(pos * threads);
  let onWarp = smoothstep(0.22, 0.04, abs(cell.x - 0.5));
  let onWeft = smoothstep(0.22, 0.04, abs(cell.y - 0.5));
  let yarn = max(onWarp, onWeft);
  let gap = (1.0 - yarn) * (0.2 + totalStrain * 0.8);
  finalColor = mix(finalColor, finalColor * vec3<f32>(0.42, 0.46, 0.55), clamp(gap, 0.0, 1.0));
  finalColor = finalColor + vec3<f32>(0.07, 0.06, 0.04) * yarn * (1.0 - totalStrain);

  // ── Idea 3b: frayed yarn ends ───────────────────────────────────────
  // A torn cell grows short loose fibers. They follow the weave phase
  // the tear pass already stores.
  let fiber = fract(pos.x * 90.0 + pos.y * 37.0 + weavePhase * 4.0);
  let fray = select(0.0, smoothstep(0.62, 0.95, fiber) * strainNow.g, isTorn);
  finalColor = finalColor + vec3<f32>(0.9, 0.74, 0.5) * fray * 0.5;

  let threadDensity = select(THREAD_DENSITY, 0.12, isTorn);
  var fabricAlpha = calculateFabricAlpha(totalStrain, isTorn, threadDensity);
  fabricAlpha = clamp(fabricAlpha * mix(1.0, 0.7, gap) * (1.0 - fray * 0.2), 0.12, 0.95);
  finalColor = acesToneMap(finalColor);

  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, fabricAlpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pos, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(coord), posReady);
}
