// ═══════════════════════════════════════════════════════════════════
//  Liquid — canonical interactive capillary surface.
//  Category: liquid-effects
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: capillary precursor ring (anomalous dispersion); foam drains into troughs; Snell vector refraction (§12.2F); dispersive wake train behind each click front (§12.2D deep-water dispersion); sun glint on lit ripple flanks (native)
//  A packing: raw — R=height, G=velocity, B=curvature foam, A=coverage.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
const TAU: f32 = 6.28318530718;
const SNELL_DEPTH: f32 = 4.0;   // column depth scale: calibrated so mean offset ~ HEAD's thin-lens offset
const WAKE_K: f32 = 1.2;        // dispersion strength of the wake train
const WAKE_AMP: f32 = 1.8;      // wake amplitude relative to the main ring (0 = HEAD)
const GLINT_AMP: f32 = 1.1;     // sun glint strength (0 = HEAD)

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let viscosity = u.zoom_params.x; let turbulence = u.zoom_params.y;
  let rippleStrength = u.zoom_params.z; let colorShift = u.zoom_params.w;
  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  var height = select(0.14, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  let hL = select(0.14, l.r, initialized); let hR = select(0.14, r.r, initialized);
  let hD = select(0.14, d.r, initialized); let hU = select(0.14, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;

  // ── Rescue 1: the spring that lived here never persisted ─────────────
  // The host re-uploads extraBuffer[133..255] as zero every frame, so the
  // spring state was always re-seeded to the raw cursor and pointerVelocity
  // was identically 0 (its `length(pointerVelocity)` impulse term was dead).
  // The cursor is used directly; nothing about the picture changes.
  let pointer = u.zoom_config.yz;
  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 72.0);
  let held = select(0.15, 1.0, u.zoom_config.w > 0.5);
  var impulse = mouseMask * held * (0.01 + rippleStrength * 0.055);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      // Rescue 2: pow(negative, 2.0) is undefined in WGSL (dist < front behind the ring) -> plain squares.
      let front = age * (0.16 + bass * 0.05);
      let ringArg = (dist - front) * 42.0;
      let ring = exp(-ringArg * ringArg) * exp(-age * mix(0.85, 1.45, viscosity));
      impulse += ring * sin(age * (6.0 + mids * 3.0)) * (0.025 + rippleStrength * 0.075); clickEnergy += ring;
      // ── Idea 1: capillary precursor ring ──────────────────────────
      // Capillary waves have anomalous dispersion — short wavelengths
      // outrun long ones — which is why a drop on water throws a fringe of
      // fine ripples AHEAD of the main ring. Faster, narrower, higher
      // frequency, and damped harder by viscosity, since viscous damping
      // grows with k^2.
      let capFront = front * mix(1.9, 1.45, viscosity);
      let capArg = (dist - capFront) * 95.0;
      let precursor = exp(-capArg * capArg) * exp(-age * mix(1.6, 2.8, viscosity));
      impulse += precursor * sin(age * 19.0 + dist * 180.0) * (0.008 + rippleStrength * 0.03);
      clickEnergy += precursor * 0.5;
      // ── Idea 4: dispersive wake train (§12.2D deep-water dispersion) ──
      // The other half of the dispersion story. Gravity waves are NORMAL
      // (phase speed c ~ sqrt(lambda)): the long crest leads and ever
      // shorter ones trail it, so a pebble drop throws a TRAIN — crests
      // behind the front that spread apart with age and crowd together
      // toward the centre. Crest j trails at front / sqrt(1 + K*j) (the
      // wavelength of crest j is lambda0 / (1 + K*j)), alternating sign,
      // damped harder than the main ring (shorter waves), and gated in
      // over the first half second so it separates from the front.
      let wakeGate = smoothstep(0.08, 0.45, age) * exp(-age * mix(0.6, 1.3, viscosity));
      var wakeAmp = WAKE_AMP;
      for (var j = 1; j <= 3; j = j + 1) {
        let crest = front * inverseSqrt(1.0 + WAKE_K * f32(j));
        let wArg = (dist - crest) * 34.0;
        let sgn = 1.0 - 2.0 * f32((j + 1) & 1);   // +, -, + : crest, trough, crest
        wakeAmp = wakeAmp * 0.72;
        let w = exp(-wArg * wArg) * wakeGate;
        impulse += sgn * w * wakeAmp * (0.02 + rippleStrength * 0.05);
        clickEnergy += w * wakeAmp * 0.2;
      }
    }
  }
  let p = (uv - 0.5) * aspectVec;
  let capillaryNoise = sin(p.y * (10.0 + turbulence * 12.0) + time * (0.45 + bass * 0.2))
    * cos(p.x * (9.0 + turbulence * 10.0) - time * (0.38 + mids * 0.16));
  let tension = mix(0.15, 0.055, viscosity); let damping = mix(0.91, 0.986, viscosity);
  velocity = clamp(velocity * damping + laplacian * tension + (0.14 - height) * 0.014
    + capillaryNoise * turbulence * 0.0022 + impulse, -0.85, 0.85);
  height = clamp(height + velocity * mix(0.095, 0.035, viscosity), 0.01, 1.0);
  // ── Idea 2: foam drains into troughs ──────────────────────────────
  // HEAD's foam only decayed where it was born. Real foam slides off crests
  // under gravity. Semi-Lagrangian transport of B from the uphill neighbour
  // moves it downslope, so it gathers in the troughs and lines them.
  let slope = vec2<f32>(hR - hL, hU - hD);
  let uphillX = select(l.b, r.b, slope.x > 0.0);
  let uphillY = select(d.b, t.b, slope.y > 0.0);
  let slopeX = abs(slope.x) / (abs(slope.x) + abs(slope.y) + 1e-5);
  let drainW = clamp(length(slope) * 6.0, 0.0, 0.35) * select(0.0, 1.0, initialized);
  let drainedFoam = mix(c.b, mix(uphillY, uphillX, slopeX), drainW);
  let foam = clamp(max(drainedFoam * mix(0.9, 0.97, viscosity), abs(laplacian) * 9.0 + abs(velocity) * 0.6 + clickEnergy * 0.38), 0.0, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.01, 0.11, height)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + rippleStrength * 13.0);
  let normal = normalize(vec3<f32>(gradient, 0.24 + viscosity * 0.2));
  // ── Idea 3: Snell vector refraction (§12.2F) ─────────────────────────
  // HEAD displaced the photo by normal.xy * (0.012 + height*0.052): a thin-
  // lens guess. The camera ray is refracted at the surface (n = 1.33), and
  // its lateral travel scales with the water column under the pixel, so the
  // magnification grows with BOTH slope and depth (steep flanks over deep
  // water bend most). refract() bends toward -N: a mound converges the photo.
  let refr = refract(vec3<f32>(0.0, 0.0, -1.0), normal, 0.7518797);
  let lateral = refr.xy / max(-refr.z, 0.2);
  let column = (0.012 + height * 0.052) * SNELL_DEPTH;
  let sourceUV = clamp(uv + lateral * column / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  // ── Idea 5: sun glint (native to a water surface) ───────────────────
  // A low sun upper-left, seen over the perturbed normal with a Blinn half-
  // vector: only slopes that face the sun flash, so glints sparkle along the
  // lit flank of every ripple and vanish on flat water.
  let sunH = vec3<f32>(-0.213, -0.266, 0.941);
  let sunCone = smoothstep(0.965, 1.0, dot(normal, sunH));   // 0 on flat water (dot = 0.941), 1 facing the sun
  let glint = sunCone * sunCone;
  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let caustic = pow(clamp(abs(laplacian) * 21.0 + clickEnergy * 0.3, 0.0, 1.0), 2.2);
  let tint = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.19, 0.41) + colorShift + height * vec3<f32>(0.42, 0.51, 0.63)));
  let color = source.rgb * exp(-height * vec3<f32>(0.3, 0.14, 0.06))
    + tint * fresnel * (0.14 + colorShift * 0.18 + mids * 0.12)
    + vec3<f32>(0.7, 0.94, 1.12) * caustic * (0.16 + treble * 0.22)
    + vec3<f32>(0.76, 0.88, 1.0) * foam * (0.08 + bass * 0.08)
    + vec3<f32>(1.0, 0.96, 0.88) * glint * GLINT_AMP * (0.6 + treble * 0.9) * coverage;
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.22 + height * 0.58) + fresnel * 0.07 + foam * 0.04, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.9, height * 0.28 + foam * 0.025), 0.0, 0.0, 0.0));
}
