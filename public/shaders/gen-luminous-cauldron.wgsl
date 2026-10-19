// ═══════════════════════════════════════════════════════════════════
//  Luminous Cauldron
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14, 2026-10-19
//  Ideas: Minnaert bubble-collapse capillary rings where bubbles burst at the surface; meniscus rim caustic at the pot lip;
//         bubble lensing of the caustic net with TIR dark rims (Snell vector refraction, §12.2F); plume-gated bubble
//         nucleation in the hot convection band; steam veil scattering the brew glow
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Boil Rate, .y = Convection, .z = Foam, .w = Radiance

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.1, 29.6)));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * noise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn causticPattern(p: vec2<f32>, time: f32) -> f32 {
  var c = 0.0;
  c += 0.5 + 0.5 * sin(p.x * 12.0 + time * 2.3);
  c += 0.5 + 0.5 * sin(p.y * 14.0 - time * 1.7);
  c += 0.5 + 0.5 * sin((p.x + p.y) * 9.0 + time * 2.9);
  c += 0.5 + 0.5 * sin(length(p) * 16.0 - time * 3.1);
  return c * 0.25;
}

fn heatShimmer(uv: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
  let warp = vec2<f32>(
    fbm(uv * 4.0 + vec2<f32>(time * 0.7, 0.0), 3),
    fbm(uv * 4.0 + vec2<f32>(0.0, time * 0.6), 3)
  );
  return uv + (warp - 0.5) * strength;
}

// Same swirl-convection band as main(), evaluated at an arbitrary pot point
// (used to ask "is this bubble's centre in a hot upwelling?").
fn convectionAt(pc: vec2<f32>, time: f32, boilRate: f32, convection: f32, mids: f32, mouseDown: bool) -> f32 {
  let rB = length(pc);
  let stirC = select(0.0, 2.5 * exp(-rB * 2.0), mouseDown);
  let sw = atan2(pc.y, pc.x) + time * boilRate + stirC;
  return 0.5 + 0.5 * sin(sw * 6.0 + rB * 12.0 - time * convection * (1.0 + mids * 0.4));
}

// Minnaert collapse ring: a bubble that bursts at the free surface launches a
// short-lived capillary ring whose wavelength shrinks as it spreads and decays.
fn collapseRing(d: f32, age: f32, strength: f32) -> f32 {
  if (age < 0.0 || age > 1.2) { return 0.0; }
  let front = age * 0.55;
  let env = exp(-abs(d - front) * 28.0) * (1.0 - age / 1.2);
  return strength * env * (0.6 + 0.4 * cos((d - front) * 90.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Smoothed bass envelope state (relocated from extraBuffer[0] to guarded slot 133)
  var smoothBass = bass;
  if (arrayLength(&extraBuffer) > 138u) {
    let prevBass = extraBuffer[133];
    smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = smoothBass;
    }
  }
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w > 0.5;

  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let boilRate = mix(0.1, 2.2, zp.x) * (1.0 + select(0.0, 0.6, mouseDown));
  let convection = mix(0.2, 2.0, zp.y);
  let foam = mix(0.0, 1.0, zp.z);
  let radiance = mix(0.3, 2.5, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.2;

  let shimmerUv = heatShimmer(uv, time, 0.015 * convection * (1.0 + mids * 0.4));
  var pShimmer = shimmerUv * 2.0 - 1.0;
  pShimmer.x = pShimmer.x * aspect;
  pShimmer = pShimmer - mouse * 0.2;

  let rBowl = length(p);
  let bowl = smoothstep(1.05, 0.2, rBowl);
  // Held mouse stirs the brew: extra swirl winding toward the centre
  let stir = select(0.0, 2.5 * exp(-rBowl * 2.0), mouseDown);
  let swirl = atan2(p.y, p.x) + time * boilRate + stir;
  let convectionWaves = 0.5 + 0.5 * sin(swirl * 6.0 + rBowl * 12.0 - time * convection * (1.0 + mids * 0.4));

  var bubbles = 0.0;
  var bubbleGlow = 0.0;
  var collapse = 0.0;
  var lensOffset = vec2<f32>(0.0);
  var tirRim = 0.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let fi = f32(i);
    let gridScale = 12.0 + fi * 8.0;
    let rise = time * boilRate * (0.08 + fi * 0.04);
    let bubbleGrid = floor((shimmerUv + vec2<f32>(0.0, rise)) * gridScale);
    let bubbleRnd = hash21(bubbleGrid + fi * 13.7);
    let bubbleCellRaw = fract((shimmerUv + vec2<f32>(0.0, rise)) * gridScale) - 0.5;
    let offset = (hash22(bubbleGrid + fi * 13.7) - 0.5) * 0.6;
    let bubbleCell = bubbleCellRaw - offset;
    let r = 0.12 + bubbleRnd * 0.18 + fi * 0.03;
    let d = sdSphere(vec3<f32>(bubbleCell, 0.0), r);

    // ── Idea 4: plume-gated nucleation ──
    // Boiling nucleates where the hot plume upwells. Evaluate the swirl
    // convection band at this bubble's centre (one value per bubble, so a
    // bubble is never cut by the band edge): the hot orange trough lowers the
    // survival threshold, the cool violet crest raises it.
    let bubbleCenterUv = (bubbleGrid + 0.5 + offset) / gridScale - vec2<f32>(0.0, rise);
    var pc = bubbleCenterUv * 2.0 - 1.0;
    pc.x = pc.x * aspect;
    pc = pc - mouse * 0.2;
    let hotPlume = 1.0 - convectionAt(pc, time, boilRate, convection, mids, mouseDown);
    let plumeBias = (0.5 - hotPlume) * 0.24;
    let alive = step(0.72 - fi * 0.1 - smoothBass * 0.08 + plumeBias, bubbleRnd);
    let s = smoothstep(0.08, -0.04, d) * alive;
    bubbles += s;
    bubbleGlow += exp(-max(d, 0.0) * 8.0) * s * 0.5;

    // ── Idea 3: bubble lensing of the caustic net (Snell, §12.2F) ──
    // The bubble already has a centre and radius, so it has a hemispherical
    // normal. Refract the straight-down view ray liquid -> gas (eta = 1.33):
    // the refracted xy shifts where the caustic net is read, and past the
    // critical angle (k < 0) total internal reflection gives the dark rim a
    // real gas bubble shows in liquid.
    let bn2 = dot(bubbleCell, bubbleCell) / max(r * r, 1e-4);
    let nz = sqrt(max(1.0 - bn2, 0.0));
    let nrm = vec3<f32>(bubbleCell / max(r, 1e-3), nz);
    let eta = 1.33;
    let kSnell = 1.0 - eta * eta * (1.0 - nz * nz);
    let refr = eta * vec3<f32>(0.0, 0.0, -1.0) + (eta * nz - sqrt(max(kSnell, 0.0))) * nrm;
    let inLens = step(bn2, 1.0) * alive;
    let passes = step(0.0, kSnell);
    lensOffset += refr.xy * (r / gridScale) * 6.0 * inLens * passes;
    tirRim += inLens * (1.0 - passes);

    // Minnaert collapse: in the fixed surface frame each bubble bursts at its own
    // phase; the collapse lands in a surface cell and radiates a capillary ring.
    let popCell = floor(shimmerUv * gridScale * 0.5);
    let popRnd = hash21(popCell + fi * 7.3);
    let popPeriod = 1.6 + popRnd * 2.4;
    let popAge = fract(time * boilRate * 0.35 / popPeriod + popRnd) * popPeriod;
    let popOff = (hash22(popCell + fi * 3.1 + floor(time * boilRate * 0.35 / popPeriod + popRnd)) - 0.5) * 0.5;
    let popLocal = (fract(shimmerUv * gridScale * 0.5) - 0.5 - popOff) / (gridScale * 0.5);
    let popDist = length(popLocal) * 6.0;
    let popsHere = step(0.55 - smoothBass * 0.25, popRnd);
    collapse += collapseRing(popDist, popAge, popsHere * (0.5 + foam));
  }
  bubbles = sat(bubbles);
  bubbleGlow = sat(bubbleGlow);
  tirRim = sat(tirRim);

  // Idea 3 (cont.): the caustic net is read through the bubble lenses.
  let caustics = causticPattern(pShimmer * 1.5 + lensOffset, time) * bowl * radiance * (1.0 - 0.6 * tirRim);

  // Click ripples: each click drops a bubble that collapses into a large Minnaert ring
  let rippleCount = min(u32(u.config.y), 50u);
  for (var k: u32 = 0u; k < rippleCount; k = k + 1u) {
    let rp = u.ripples[k];
    let age = time - rp.z;
    if (age < 0.0 || age > 2.4) { continue; }
    var dv = uv - rp.xy;
    dv.x = dv.x * aspect;
    collapse += collapseRing(length(dv) * 0.5, age * 0.5, 1.6);
  }
  collapse = sat(collapse) * bowl;

  let froth = bubbles * foam;

  // Meniscus rim caustic: liquid climbs the pot wall, the curved meniscus focuses
  // caustic light into a thin bright band just inside the lip.
  let lipR = 0.86 + 0.015 * sin(atan2(p.y, p.x) * 9.0 + time * convection) + smoothBass * 0.02;
  let mBand = (rBowl - lipR) * 38.0;
  let mFocus = (rBowl - (lipR - 0.035)) * 70.0;
  let meniscusBand = exp(-mBand * mBand);
  let meniscusFocus = exp(-mFocus * mFocus);
  let rimFlicker = 0.6 + 0.4 * causticPattern(vec2<f32>(atan2(p.y, p.x) * 0.6, rBowl), time * 1.3);
  let meniscus = (meniscusBand * 0.5 + meniscusFocus * rimFlicker) * radiance * (1.0 + treble * 0.4);

  let sparks = step(0.997 - treble * 0.03, hash21(floor((shimmerUv + vec2<f32>(time * 0.04, -time * 0.03)) * 260.0)));
  let sparkPulse = 0.5 + 0.5 * sin(time * 18.0 + hash21(floor(shimmerUv * 260.0)) * 40.0);

  var color = vec3<f32>(0.02, 0.01, 0.04);
  color = color + vec3<f32>(0.5, 0.15, 0.95) * bowl * convectionWaves * radiance * (1.0 + mids * 0.3);
  color = color + vec3<f32>(1.0, 0.5, 0.15) * bowl * (1.0 - convectionWaves) * (0.4 + smoothBass * 0.5);
  color = color + vec3<f32>(0.2, 0.9, 1.0) * caustics * (0.6 + treble * 0.3);
  color = color + vec3<f32>(0.95, 1.0, 0.85) * froth * 0.7 * (1.0 + treble * 0.3);
  color = color + vec3<f32>(0.6, 0.85, 1.0) * sparks * sparkPulse * (0.3 + treble);
  color = color + vec3<f32>(1.0, 0.7, 0.3) * bubbleGlow * 0.4 * (1.0 + smoothBass * 0.5);
  color = color + vec3<f32>(0.85, 0.95, 1.0) * collapse * (0.5 + 0.5 * foam) * (1.0 + bass * 0.4);
  color = color + vec3<f32>(1.0, 0.82, 0.45) * meniscus * 0.8;

  // ── Idea 5: steam veil ──
  // A boil throws vapour off the surface. Wisps ride the brew's rotation
  // (rotated by the same boilRate that drives the swirl), are densest over
  // the hot band and over fresh bursts, and forward-scatter the pot's own
  // glow — they soften and lift the brew rather than painting white fog.
  let steamRot = -time * boilRate * 0.3;
  let cs = cos(steamRot);
  let sn = sin(steamRot);
  let pRot = vec2<f32>(cs * pShimmer.x - sn * pShimmer.y, sn * pShimmer.x + cs * pShimmer.y);
  let wisp = fbm(pRot * 2.4 + vec2<f32>(0.0, time * 0.15), 4);
  let steamSrc = 0.35 + 0.65 * (1.0 - convectionWaves) + collapse * 0.8;
  let steam = sat(smoothstep(0.42, 0.78, wisp) * bowl * steamSrc * (0.15 + 0.12 * boilRate));
  let brewScatter = vec3<f32>(0.78, 0.62, 0.88) * (0.25 + 0.2 * radiance);
  color = mix(color, brewScatter, steam);

  let prevCoord = clamp(coord, vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, prevCoord, 0);
  color = mix(color, prev.rgb * 0.9, 0.03 + smoothBass * 0.01);

  color = acesToneMap(max(color * 1.1, vec3<f32>(0.0)));

  // Alpha: liquid coverage inside the pot, plus froth / collapse / rim light density
  let alpha = sat(bowl * 0.75 + froth * 0.2 + collapse * 0.3 + meniscus * 0.25 + bubbleGlow * 0.1 + steam * 0.2);
  let outColor = vec4<f32>(color, alpha);
  // Depth: bowl surface height, lifted by bubbles and collapse ring crests
  let depth = sat(bowl * 0.6 + bubbles * 0.2 + collapse * 0.15 + convectionWaves * 0.05);

  textureStore(writeTexture, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outColor);
}
