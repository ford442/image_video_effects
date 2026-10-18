// ═══════════════════════════════════════════════════════════════════
//  Contour Flow
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: coherence-gated ribbon sharpness (exponent mix(4,12,coherence)); two-scale cross-hatch (fine and broad tangents carry opposite-sign ribbon phase); contour-steered click fronts (front vector projected onto the tangent)
//  A packing: linear pre-ACES painting RGBA (exact-C tangent-advection history); ACES on display only
// ═══════════════════════════════════════════════════════════════════
// Multiscale tangent advection with coherent history ribbons. B and extraBuffer are unused.

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(v: vec3<f32>) -> vec3<f32> {
  let x = max(v, vec3<f32>(0.0));
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  // Linear history; guard NaN/garbage left by another shader and bound the HDR loop.
  let h = textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
  return clamp(select(vec4<f32>(0.0), h, h == h), vec4<f32>(0.0), vec4<f32>(6.0));
}

fn gradientAt(uv: vec2<f32>, stepUV: vec2<f32>) -> vec2<f32> {
  let lo = vec2<f32>(0.0);
  let hi = vec2<f32>(1.0);
  let left = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(stepUV.x, 0.0), lo, hi), 0.0).rgb);
  let right = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepUV.x, 0.0), lo, hi), 0.0).rgb);
  let top = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, stepUV.y), lo, hi), 0.0).rgb);
  let bottom = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, stepUV.y), lo, hi), 0.0).rgb);
  return vec2<f32>(right - left, bottom - top);
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.0, 0.31, 0.67) + t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let texel = vec2<f32>(1.0) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let flowSpeed = 0.15 + u.zoom_params.x * 2.8;
  let curlStrength = 0.08 + u.zoom_params.y * 1.4;
  let flowSize = 0.35 + u.zoom_params.z * 2.4;
  let directionAngle = u.zoom_params.w * TAU;
  let rotation = mat2x2<f32>(cos(directionAngle), -sin(directionAngle),
                              sin(directionAngle),  cos(directionAngle));

  let fineGradient = gradientAt(uv, texel);
  let broadGradient = gradientAt(uv, texel * (2.0 + flowSize * 1.5));
  let fineMag = length(fineGradient);
  let broadMag = length(broadGradient);
  let fineTangent = normalize(vec2<f32>(-fineGradient.y, fineGradient.x) + vec2<f32>(0.0001));
  let broadTangent = normalize(vec2<f32>(-broadGradient.y, broadGradient.x) + vec2<f32>(0.0001));
  var tangent = normalize(mix(fineTangent, broadTangent, 0.32 + 0.24 * sin(time * 0.31 + broadMag * 18.0)) + vec2<f32>(0.0001));
  tangent = rotation * tangent;
  let fineTangentR = rotation * fineTangent;
  let broadTangentR = rotation * broadTangent;

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerTangent = vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.0001);
  // FIX: vortex only while held (HEAD kept a 0.18 hover vortex on the idle pointer).
  let heldMask = (1.0 - smoothstep(0.0, 0.42 + u.zoom_params.z * 0.18, pointerDist)) * select(0.0, 1.0, held);
  let vortex = pointerTangent * heldMask * curlStrength;

  var contourFront = 0.0;
  var frontVector = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.6) {
      let delta = (uv - ripple.xy) * aspectVec;
      let dist = length(delta);
      let front = age * (0.28 + bass * 0.08);
      let band = sin((dist - front) * 72.0) * exp(-abs(dist - front) * 30.0) * exp(-age * 1.1);
      contourFront += band;
      frontVector += delta / max(dist, 0.0001) * band;
    }
  }
  // IDEA 3: contour-steered fronts — the radial front push is projected onto the local
  // tangent, so click fronts run along the contours instead of straight out of the click.
  frontVector = tangent * dot(frontVector, tangent);

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let edge = smoothstep(0.018, 0.16 / flowSize + 0.025, fineMag + broadMag * 0.65);
  let audioVelocity = 1.0 + bass * 0.65 + mids * 0.18;
  let velocity = (tangent * (0.45 + edge * 1.4) + vortex + frontVector * 0.55) *
                 flowSpeed * audioVelocity * (0.0025 + depth * 0.0045);
  let ribbonWobble = vec2<f32>(sin(uv.y * 19.0 + time * (1.5 + bass)),
                                cos(uv.x * 17.0 - time * (1.1 + mids))) *
                     curlStrength * (0.001 + treble * 0.0015);
  let advectUV = clamp(uv - velocity - ribbonWobble, vec2<f32>(0.0), vec2<f32>(1.0));
  let history0 = historyAt(advectUV, resolution);
  let history1 = historyAt(advectUV - tangent * texel * (2.0 + flowSize * 2.0), resolution);
  let history2 = historyAt(advectUV + tangent * texel * (3.0 + flowSize), resolution);
  let current = textureSampleLevel(readTexture, u_sampler, advectUV, 0.0);

  // History is linear (up to 6) now; measure coherence in display range so the
  // brightest edges are not always read as incoherent.
  let coherence = 1.0 - clamp(length(aces(history1.rgb) - aces(history2.rgb)), 0.0, 1.0);
  // IDEA 1: coherence-gated ribbon sharpness — coherent history draws thin, hard ribbons
  // (exponent 12); churning history spreads them into soft bands (exponent 4).
  let ribbonExp = mix(4.0, 12.0, coherence);
  // IDEA 2: two-scale cross-hatch — the fine tangent keeps the original ribbon phase, the
  // broad tangent carries the opposite-sign spatial and temporal phase at a coarser pitch,
  // so the two ribbon families counter-run and hatch where the scales disagree.
  let ribbonPhase = luma(history0.rgb) * (12.0 + flowSize * 8.0) +
                    dot(uv * aspectVec, fineTangentR) * (34.0 + flowSize * 18.0) -
                    time * flowSpeed * (2.0 + bass * 2.0);
  let ribbonPhaseBroad = luma(history0.rgb) * (12.0 + flowSize * 8.0) -
                         dot(uv * aspectVec, broadTangentR) * (34.0 + flowSize * 18.0) * 0.55 +
                         time * flowSpeed * (2.0 + bass * 2.0);
  let ribbonsFine = pow(0.5 + 0.5 * sin(ribbonPhase), ribbonExp) * edge;
  let ribbonsBroad = pow(0.5 + 0.5 * sin(ribbonPhaseBroad), ribbonExp) * edge * 0.7;
  let ribbons = ribbonsFine + ribbonsBroad;
  let ribbonColor = spectral(ribbonPhase / TAU + mids * 0.12) * (0.35 + treble * 0.9);
  let ribbonColorBroad = spectral(ribbonPhaseBroad / TAU + 0.5 + mids * 0.12) * (0.35 + treble * 0.9);

  var hdr = mix(history0.rgb * (0.90 - u.zoom_params.x * 0.08), current.rgb, 0.12 + edge * 0.12);
  hdr += ribbonColor * ribbonsFine * coherence * (0.3 + curlStrength * 0.35);
  hdr += ribbonColorBroad * ribbonsBroad * coherence * (0.3 + curlStrength * 0.35);
  hdr += spectral(time * 0.05 + pointerDist) * abs(contourFront) * (0.25 + bass * 0.5);
  hdr += (history1.rgb + history2.rgb) * 0.08 * edge;
  hdr = max(hdr, vec3<f32>(0.0));
  let display = aces(hdr);   // ACES on display only; A keeps the linear painting
  let alpha = clamp(current.a * 0.25 + edge * 0.42 + ribbons * 0.28 + heldMask * 0.12 + abs(contourFront) * 0.18, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + edge * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
}
