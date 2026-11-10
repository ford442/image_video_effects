// ═══════════════════════════════════════════════════════════════════
//  vortex-warp-coupled
//  Category: advanced-hybrid
//  Features: vortex-warp, fluid-simulation, mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: vortex-warp, mouse-fluid-coupling
//  Created: 2026-04-18
//  Upgraded: 2026-11-09
//  Ideas: vorticity confinement (§12.2D); dye meniscus lens (§12.2F thickness-gradient refraction);
//         cursor-motion dye wake + flow carry (the fluid now reaches the picture without clicks)
//  A packing: raw sim state (vel.x, vel.y, curl, dens); texels (0,0)/(1,0) are NOT fluid — cursor-track state
//             [mouse, fract(time), 0.7371] / [smoothed cursor velocity, 0, 0.7371], read back through C
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Vortex warp rotation coupled with viscous fluid dynamics.
//  The fluid velocity field drives additional vortex rotation,
//  creating coupled fluid-vortex dynamics. Fluid thickness modulates
//  warp strength, and vortices stir the fluid in return.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

const TRACK_SENTINEL: f32 = 0.7371;
// Vorticity confinement: eps = K*(1 - viscosity) capped at MAX (so MAX for viscosity < 0.94, none at 1.0), force
// clamped per component, and the result energy-bounded (see main) so it can never out-live the cursor.
const CONFINE_K: f32 = 40.0;
const CONFINE_MAX: f32 = 2.4;
const CONFINE_FORCE: f32 = 0.2;    // per-component force cap per frame
const CONFINE_SOFT: f32 = 1e-4;    // soft normalisation of grad|omega|
// Cursor MOTION leaves a dye wake (mirrors the click's dye injection) and the fluid velocity carries the photo.
// Both scale with the dead-zoned cursor speed / the decaying velocity, so a parked cursor changes nothing and
// everything fades at the Viscosity rate.
const DYE_WAKE: f32 = 0.08;
const FLOW_CARRY: f32 = 0.04;

// Round to the nearest representable binary16 value (10 mantissa bits, round-half-even) without
// pack2x16float, which naga-wasm only accepts with an extra capability. Inputs here are uv in [0,1].
// Integer rounding of the f32 bit pattern: drop the low 13 mantissa bits with round-half-even (the carry into the
// exponent is correct too), no log2/exp2.
fn quantF16(x: f32) -> f32 {
  let ax = max(abs(x), 6.103515625e-5);        // smallest normal f16: below it the step is constant
  let bits = bitcast<u32>(ax);
  let rounded = (bits + 0x0FFFu + ((bits >> 13u) & 1u)) & 0xFFFFE000u;
  return sign(x) * bitcast<f32>(rounded);
}

// Exact history load at an IN-RANGE texel. The two cursor-track texels (0,0)/(1,0) hold no fluid: read them as still water.
fn fetchC(cc: vec2<i32>) -> vec4<f32> {
  let isTrack = (cc.y == 0) && (cc.x < 2);
  return select(textureLoad(dataTextureC, cc, 0), vec4<f32>(0.0), isTrack);
}

// Exact, edge-clamped history load.
fn loadC(c: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return fetchC(clamp(c, vec2<i32>(0), dims - vec2<i32>(1)));
}

// Bilinear from four exact loads (no filtering sampler on rgba32float history). Texel centres sit at
// (i+0.5)/res, so callers pass a PIXEL-CENTRE uv ((gid+0.5)/res): with gid/res HEAD sampled half a texel off and
// every advect step dragged dye and velocity toward +x,+y.
fn bilerpC(uv: vec2<f32>, res: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let p = uv * res - vec2<f32>(0.5);
  let fp = floor(p);
  let f = p - fp;
  // clamp the two row and two column indices once (edge clamp), then gather the four corners
  let lo = clamp(vec2<i32>(fp), vec2<i32>(0), dims - vec2<i32>(1));
  let hi = clamp(vec2<i32>(fp) + vec2<i32>(1), vec2<i32>(0), dims - vec2<i32>(1));
  let a = fetchC(lo);
  let b = fetchC(vec2<i32>(hi.x, lo.y));
  let c = fetchC(vec2<i32>(lo.x, hi.y));
  let d = fetchC(hi);
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let strengthBase = (u.zoom_params.x - 0.5) * 10.0;
  let radius = u.zoom_params.y * 0.5 + 0.05;
  let twistBase = u.zoom_params.z * 10.0;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;

  // Cursor motion. HEAD kept the previous cursor in A(0,0) and then overwrote that same texel with fluid state at
  // the end of main, so prevMouse was ~(0,0) and mouseVel = mousePos*60 stirred the fluid with the cursor POSITION.
  // The track now rides texels (0,0)/(1,0) of A (read back as C) and the fluid never writes them.
  // The track is only consumed where the cursor has influence (everything it feeds is multiplied by `influence`)
  // and by the two track texels themselves, so every other pixel skips the two loads and the filter maths.
  let px = vec2<f32>(1.0) / resolution;
  let uvC = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / resolution;
  let toMouse = (uvC - mousePos) * vec2<f32>(aspect, 1.0);   // fluid-side positions use the pixel centre
  let distMouse = length(toMouse);
  let influence = smoothstep(radius, 0.0, distMouse);
  let isTrackTexel = (coord.y == 0) && (coord.x < 2);

  var mouseQ = vec2<f32>(0.0);
  var sVel = vec2<f32>(0.0);
  if (influence > 0.0 || isTrackTexel) {
    let trackA = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let trackB = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let trackOk = abs(trackA.w - TRACK_SENTINEL) < 0.001 && abs(trackB.w - TRACK_SENTINEL) < 0.001;
    // A may be rgba16float: quantise the cursor to what A can hold so an idle cursor diffs to exactly 0.
    mouseQ = vec2<f32>(quantF16(mousePos.x), quantF16(mousePos.y));
    let trackDt = fract(time - trackA.z);
    let trackLive = trackOk && trackDt > 0.002 && trackDt < 0.25;
    let instVel = (mouseQ - trackA.xy) / max(trackDt, 0.002);
    sVel = select(vec2<f32>(0.0), trackB.xy, trackOk);
    sVel = select(sVel, mix(trackB.xy, instVel, 0.5), trackLive);
    let sSpeed = length(sVel);
    // dead zone below 0.03 uv/s, cap at 6 uv/s (HEAD's x60 saturated the +/-0.5 clamp on any real move)
    sVel = sVel * (smoothstep(0.03, 0.08, sSpeed) * min(1.0, 6.0 / max(sSpeed, 1e-4)));
  }
  let mouseVel = sVel;
  let mouseSpeed = length(mouseVel);

  // Read previous fluid state. At the pixel centre the bilinear footprint IS the texel: one exact load.
  let cC = fetchC(coord);
  let prevVel = cC.xy;

  // Advect fluid. Still water (no velocity here) back-traces to its own texel, so the four-tap gather is skipped
  // (identical to the gather at a pixel centre up to float noise).
  let backUV = uvC - prevVel * px * 2.0;
  var advected = cC;
  if (prevVel.x != 0.0 || prevVel.y != 0.0) {
    advected = bilerpC(backUV, resolution, dims);
  }

  var vel = advected.xy * viscosity;
  var dens = advected.w * viscosity;

  // Mouse force
  vel = vel + mouseVel * influence * 0.5;

  // Vortex force from fluid
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * mouseSpeed * 2.0;

  // Dye wake: the cursor already stirs velocity; it now also lays dye where it moves (a click does the same
  // below). Dead-zoned speed -> a parked cursor injects nothing; the wake decays with dens * viscosity.
  dens = dens + influence * min(mouseSpeed, 1.0) * DYE_WAKE;

  // Click ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uvC - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  // Neighbour history shared by both ideas (exact loads; .xy velocity, .z stored curl, .w dye thickness).
  // The stencil radius is ~height/96 texels (2 at 192 px, 6 at 576 px): the swirls confinement re-injects and the
  // lens' dye gradient then have a resolution-independent SIZE instead of a one-texel (noise) scale.
  let sr = clamp(i32(round(resolution.y / 96.0)), 1, 8);
  let invR = 1.0 / f32(sr);
  let cE = loadC(coord + vec2<i32>(sr, 0), dims);
  let cW = loadC(coord + vec2<i32>(-sr, 0), dims);
  let cS = loadC(coord + vec2<i32>(0, sr), dims);
  let cN = loadC(coord + vec2<i32>(0, -sr), dims);

  // ── Idea 1: vorticity confinement (§12.2D) ──────────────────────────
  // Semi-Lagrangian advection + viscosity bleed off small swirls. Re-inject them: omega = dvy/dx - dvx/dy from the
  // stored field, N = grad|omega| / |grad|omega||, force = eps * (N x omega) — it spins existing vortices up
  // (never starts one: a still fluid has omega = 0 and no gradient). Force magnitude is capped so the existing
  // +/-0.5 velocity clamp is not the only thing keeping it bounded. It may only REDIRECT the flow and give back
  // at most half of the viscous loss: the speed after confinement is capped at |vel|*(1 + (1-viscosity)/2), so
  // |vel| still decays every frame (no stirring -> the fluid comes to rest; confinement cannot sustain a vortex).
  let curlHere = 0.5 * invR * ((cE.y - cW.y) - (cS.x - cN.x));
  let gradOmega = 0.5 * invR * vec2<f32>(abs(cE.z) - abs(cW.z), abs(cS.z) - abs(cN.z));
  // Dead-still neighbourhood with no velocity here (exactly zero in, exactly zero out) skips the maths. Any nonzero
  // velocity — even a tiny one — still goes through the energy bound below, which also zeroes residual drift: the
  // confinement loop amplifies 1-ulp differences, so this skip must stay bit-exact.
  if (curlHere != 0.0 || gradOmega.x != 0.0 || gradOmega.y != 0.0 || vel.x != 0.0 || vel.y != 0.0) {
    let nOmega = gradOmega / (length(gradOmega) + CONFINE_SOFT);
    let confineEps = min(CONFINE_K * (1.0 - viscosity), CONFINE_MAX);
    let confine = vec2<f32>(nOmega.y, -nOmega.x) * curlHere * confineEps;
    let velCap = length(vel) * (1.0 + 0.5 * (1.0 - viscosity));
    let velConf = vel + clamp(confine, vec2<f32>(-CONFINE_FORCE), vec2<f32>(CONFINE_FORCE));
    vel = velConf * min(1.0, velCap / max(length(velConf), 1e-5));
  }

  // Edge damping
  let edgeDist = min(min(uvC.x, 1.0 - uvC.x), min(uvC.y, 1.0 - uvC.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // ═══ COUPLED VORTEX WARP ═══
  // Fluid velocity adds to vortex rotation
  let fluidVortexStrength = length(vel) * 5.0;
  let strength = strengthBase + fluidVortexStrength * sign(strengthBase);
  let twist = twistBase + dens * 2.0;

  let diff = uv - mousePos;
  let diffAspect = diff * vec2<f32>(aspect, 1.0);
  let dist = length(diffAspect);

  var finalUV = uv;
  var distortionMag = 0.0;
  var percent = 0.0;

  if (dist < radius) {
    percent = (radius - dist) / radius;
    let weight = percent * percent;
    let theta = weight * strength;
    let spiralAngle = twist * weight * dist;
    let totalAngle = theta + spiralAngle;
    distortionMag = abs(strength) * percent * percent + abs(twist) * percent * dist * 0.1;

    let s = sin(totalAngle);
    let c = cos(totalAngle);
    let squareDiff = vec2<f32>(diff.x * aspect, diff.y);
    let rotatedSquareDiff = vec2<f32>(
      squareDiff.x * c - squareDiff.y * s,
      squareDiff.x * s + squareDiff.y * c
    );
    let rotatedDiff = vec2<f32>(rotatedSquareDiff.x / aspect, rotatedSquareDiff.y);
    finalUV = mousePos + rotatedDiff;
  }

  // ── Idea 2: dye meniscus lens (§12.2F) ──────────────────────────────
  // A film of dye is a lens at its edge: the picture bends along the thickness gradient (down-gradient of the
  // stored dye, in height units so it is isotropic on screen). Flat or absent dye -> zero gradient -> no-op.
  let gradDens = 0.5 * invR * vec2<f32>(cE.w - cW.w, cS.w - cN.w) * resolution.y;
  var meniscus = -gradDens * 0.006 * vec2<f32>(1.0 / aspect, 1.0);
  meniscus = meniscus * min(1.0, 0.03 / max(length(meniscus), 1e-5));

  // Sample with fluid blur
  let blurAmount = dens * 0.02;
  // The fluid velocity also carries the photo itself (small, bounded: |vel| <= 0.707 -> <= 0.03 uv).
  let blurUV = finalUV + vel * (blurAmount * 5.0 + FLOW_CARRY) + meniscus;
  let warpedSample = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0);

  // Color absorption
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
  let tinted = warpedSample.rgb * fluidTint;

  // Specular highlight
  var specular = 0.0;
  if (influence > 0.0 && dens > 0.0) {
    specular = pow(hash12(uv * 300.0 + time * 2.0), 20.0) * influence * dens * 3.0;
  }
  let outColor = max(tinted + vec3<f32>(0.9, 0.95, 1.0) * specular, vec3<f32>(0.0));

  // Pressure-based alpha
  let pressureAlpha = mix(0.9, 0.6, percent);
  let scatteringLoss = distortionMag * 0.3;
  let finalAlpha = clamp(warpedSample.a * pressureAlpha - scatteringLoss, 0.4, 1.0);

  // Store fluid state: (vel.x, vel.y, honest curl of the stored field, dye). Texels (0,0)/(1,0) carry the cursor track.
  var aOut = vec4<f32>(vel, curlHere, dens);
  if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(mouseQ, fract(time), TRACK_SENTINEL); }
  if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(sVel, 0.0, TRACK_SENTINEL); }
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeTexture, coord, vec4<f32>(outColor, finalAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMod = 1.0 + distortionMag * 0.05;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
