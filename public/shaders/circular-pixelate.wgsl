// ═══════════════════════════════════════════════════════════════════
//  Circular Pixelate
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-16, 2026-11-10
//  Ideas: hex diaphragm on the round lenslet; grout seam between cells; aperture-shaped PSF integration (7-tap hex rosette instead of one point sample); cat's-eye optical vignetting (second pupil disc toward the frame edge)
//  A packing: ACES display RGBA (unchanged)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const HEX_SIZE: vec2<f32> = vec2<f32>(1.0, 1.7320508);

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn getHex(p: vec2<f32>) -> vec4<f32> {
  let centerA = round(p / HEX_SIZE);
  let centerB = round((p - HEX_SIZE * 0.5) / HEX_SIZE) + 0.5;
  let offA = p - centerA * HEX_SIZE;
  let offB = p - centerB * HEX_SIZE;
  if (dot(offA, offA) < dot(offB, offB)) {
    return vec4<f32>(offA, centerA);
  }
  return vec4<f32>(offB, centerB);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
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
  return textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
}

fn spectrum(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.02, 0.35, 0.68) + t));
}

fn hexBlade(local: vec2<f32>) -> f32 {
  let d0 = abs(local.x);
  let d1 = abs(local.x * 0.5 + local.y * 0.8660254);
  let d2 = abs(local.x * 0.5 - local.y * 0.8660254);
  return max(d0, max(d1, d2));
}

fn hexSeam(p: vec2<f32>) -> f32 {
  let centerA = round(p / HEX_SIZE);
  let centerB = round((p - HEX_SIZE * 0.5) / HEX_SIZE) + 0.5;
  let offA = p - centerA * HEX_SIZE;
  let offB = p - centerB * HEX_SIZE;
  let gap = abs(dot(offA, offA) - dot(offB, offB));
  return 1.0 - smoothstep(0.0, 0.06, gap);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let density = 10.0 + u.zoom_params.x * 100.0;
  let radiusParam = clamp(u.zoom_params.y, 0.0, 1.0);
  let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
  let backgroundMix = clamp(u.zoom_params.w, 0.0, 1.0);
  let gridScale = vec2<f32>(density, density / max(aspect, 0.001));
  let hex = getHex(uv * gridScale);
  let local = hex.xy;
  let cellId = hex.zw;
  let cellCenterUV = (cellId * HEX_SIZE) / gridScale;

  let pointerDist = length((uv - mouse) * aspectVec);
  let heldDilation = smoothstep(0.34, 0.0, pointerDist) * select(0.18, 1.0, held);
  var clickWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.30 + bass * 0.08);
      clickWave += sin((dist - front) * 74.0) * exp(-abs(dist - front) * 33.0) * exp(-age * 1.35);
    }
  }

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let apertureRadius = clamp(0.10 + radiusParam * 0.46 + heldDilation * 0.13 +
                             bass * 0.035 + clickWave * 0.04, 0.045, 0.62);
  let distanceToCenter = length(local) * 1.15;
  // Idea 1 — hex diaphragm clips the round dome.
  var stopDist = mix(distanceToCenter, hexBlade(local) * 1.35, 0.72);
  // ── Idea 4: cat's-eye optical vignetting ────────────────────────────────
  // Away from the optical axis the barrel clips the entrance pupil: a second
  // disc, shifted toward the frame centre, is intersected with the diaphragm
  // (intersection of two shapes = max of their stop distances), so cells near
  // the frame edge turn lemon-shaped, long axis tangential. The centre of the
  // frame has no shift, so centre cells are exactly the hex diaphragm above.
  // (local axes are isotropic: local = physical * density / aspect.)
  let frameOff = (cellCenterUV - vec2<f32>(0.5)) * aspectVec;
  // Fades out as the aperture fills the cell (Radius → 1): a pupil that already
  // touches the lattice walls has no room to turn into a lemon, and the shifted
  // disc would just be clipped into diagonal staircases.
  let catRoom = 1.0 - smoothstep(0.34, 0.54, apertureRadius);
  let vig = smoothstep(0.02, 0.30, dot(frameOff, frameOff)) * 0.85 * catRoom;
  let toCentre = -frameOff / max(length(frameOff), 1e-4);
  let pupil2 = local - toCentre * vig * apertureRadius;
  let stopDist2 = mix(length(pupil2) * 1.15, hexBlade(pupil2) * 1.35, 0.72);
  // Shape, not coverage: the two-disc overlap loses area f(vig) ≈ 1 − 0.74·vig + 0.22·vig²
  // (exact lens-intersection area, fitted), so the stop radius is widened by 1/√f — the
  // cells turn lemon-shaped at ~HEAD's average coverage instead of just dimming at the edge.
  let catArea = max(1.0 - 0.74 * vig + 0.22 * vig * vig, 0.3);
  stopDist = max(stopDist, stopDist2) * sqrt(catArea);
  let edgeWidth = mix(0.10, 0.008, hardness);
  let aperture = 1.0 - smoothstep(max(apertureRadius - edgeWidth, 0.0),
                                  apertureRadius + edgeWidth, stopDist);
  let normalizedLocal = local / max(apertureRadius, 0.001);
  let lensZ = sqrt(max(1.0 - dot(normalizedLocal, normalizedLocal), 0.0));
  let lensNormal = normalize(vec3<f32>(normalizedLocal, lensZ + 0.001));
  let refraction = lensNormal.xy * (0.006 + depth * 0.014) * (1.0 + heldDilation * 0.7);
  let sampleBase = clamp(cellCenterUV + refraction, vec2<f32>(0.0), vec2<f32>(1.0));
  let chromaAmount = (0.0015 + mids * 0.003 + treble * 0.002) * aperture;
  let chromaDir = normalize(local + vec2<f32>(0.0001));
  // ── Idea 3: aperture-shaped PSF integration ─────────────────────────────
  // HEAD read ONE point sample per pixel; a lenslet spot has a finite
  // footprint shaped like its aperture. Seven taps (centre + six hex
  // neighbours at a radius that grows with the Radius slider) are averaged,
  // so textured photos stop speckling at high Density. The red/blue CA taps
  // stay as a differential about this mean (CA magnitude unchanged).
  let psfRadius = clamp(apertureRadius * 0.9, 0.04, 0.40);
  let centreTap = textureSampleLevel(readTexture, u_sampler, sampleBase, 0.0);
  var psfSum = centreTap;
  for (var k = 0; k < 6; k = k + 1) {
    let ang = f32(k) * 1.0471976;
    let ringOff = vec2<f32>(cos(ang), sin(ang)) * psfRadius / gridScale;
    psfSum = psfSum + 0.7 * textureSampleLevel(readTexture, u_sampler,
                                              clamp(sampleBase + ringOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  }
  let sampled = psfSum / (1.0 + 6.0 * 0.7);
  let redTap = textureSampleLevel(readTexture, u_sampler,
                                  clamp(sampleBase + chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let blueTap = textureSampleLevel(readTexture, u_sampler,
                                   clamp(sampleBase - chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let red = sampled.r + (redTap - centreTap.r);
  let green = sampled.g;
  let blue = sampled.b + (blueTap - centreTap.b);
  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = historyAt(sampleBase - chromaDir * clickWave * 0.004, resolution);

  let apertureAngle = atan2(local.y, local.x);
  let glintDirection = vec2<f32>(cos(time * 0.7 + mids), sin(time * 0.7 + mids));
  let glint = pow(max(dot(lensNormal.xy, glintDirection), 0.0), 18.0) * aperture * (0.25 + treble * 1.2);
  let rim = smoothstep(apertureRadius - edgeWidth * 3.0, apertureRadius, stopDist) * aperture;
  let cellHue = hash12(cellId + 0.37) + apertureAngle / TAU + time * 0.025;
  let prism = spectrum(cellHue + mids * 0.12);
  var hdr = vec3<f32>(red, green, blue);
  hdr = mix(hdr, history.rgb, 0.035 + rim * 0.05);
  hdr += prism * glint * (0.35 + treble * 0.5);
  hdr += prism * rim * (0.08 + mids * 0.18);
  hdr += spectrum(cellHue + 0.33) * abs(clickWave) * aperture * 0.16;
  // Idea 2 — grout where two hex cells meet, outside the aperture.
  let seam = hexSeam(uv * gridScale);
  hdr = mix(hdr, hdr * vec3<f32>(0.12, 0.13, 0.15), seam * (1.0 - aperture));
  let lensDisplay = aces(max(hdr, vec3<f32>(0.0)));
  let effectAlpha = clamp(sampled.a * aperture + rim * 0.18 + glint * 0.16, 0.0, 1.0);
  let lenslet = vec4<f32>(lensDisplay, effectAlpha);
  let result = mix(original, lenslet, backgroundMix);

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
