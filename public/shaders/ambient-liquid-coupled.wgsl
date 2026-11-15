// Ambient Liquid Coupled — two persistent height layers joined by a membrane.
// Raw A ownership: R=top height, G=top velocity, B=lower height, A=lower velocity.
// Upgraded: 2026-11-15
// Ideas: compound double refraction of the lower layer + Beer–Lambert tint of both layers by their water column (§12.2F); torn-film rim bead (native); live vortex twist via an A-texel pointer track (rescue)
// A packing: raw coupled-height state (unchanged). Corner texels (0,0)/(1,0) of A carry the pointer track [mouse,0,sentinel] / [smoothed per-frame delta,0,sentinel]; those two pixels' sim state is sacrificed.
#include "_prelude.wgsl"
const TAU: f32 = 6.28318530718;
const TRACK_SENTINEL: f32 = 0.7371;       // survives rgba16float (nearest 0.7373)
const COMPOUND: f32 = 0.8;                // how much of the top-surface bend the lower layer's ray inherits (0 = HEAD)
const GAP0: f32 = 0.06;                   // gap at which the Beer tint is neutral (HEAD's fixed tint)
const BEER_SIGMA: vec3<f32> = vec3<f32>(2.4, 1.0, 0.4);   // water eats red first
const BEER_TOP: f32 = 0.4;                // top-layer absorption strength (0 = HEAD)
const RIM_AMP: f32 = 1.0;                 // torn-film rim strength (0 = HEAD)

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn isTrack(p: vec2<i32>) -> bool { return p.y == 0 && p.x < 2; }
// Neighbour of the sim: the two track texels are not sim state, so they read as the centre value (Neumann).
fn simLoad(p: vec2<i32>, centre: vec4<f32>, dims: vec2<i32>) -> vec4<f32> {
  let q = clampPixel(p, dims);
  return select(textureLoad(dataTextureC, q, 0), centre, isTrack(q));
}
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
  let waveStrength = u.zoom_params.x; let viscosity = u.zoom_params.y;
  let vortexStrength = u.zoom_params.z; let layerSeparation = u.zoom_params.w;
  // The track texels hold no sim state: they borrow the pixel below as their own state.
  let own = textureLoad(dataTextureC, pixel, 0);
  let below = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let c = select(own, below, isTrack(pixel));
  let l = simLoad(pixel + vec2<i32>(-1, 0), c, dims);
  let r = simLoad(pixel + vec2<i32>(1, 0), c, dims);
  let d = simLoad(pixel + vec2<i32>(0, -1), c, dims);
  let t = simLoad(pixel + vec2<i32>(0, 1), c, dims);
  let initialized = dot(abs(c), vec4<f32>(1.0)) > 0.00001;
  var topHeight = select(0.1, c.r, initialized); var topVelocity = select(0.0, c.g, initialized);
  var lowerHeight = select(0.08, c.b, initialized); var lowerVelocity = select(0.0, c.a, initialized);
  let topL = select(0.1, l.r, initialized); let topR = select(0.1, r.r, initialized);
  let topD = select(0.1, d.r, initialized); let topU = select(0.1, t.r, initialized);
  let lowL = select(0.08, l.b, initialized); let lowR = select(0.08, r.b, initialized);
  let lowD = select(0.08, d.b, initialized); let lowU = select(0.08, t.b, initialized);
  let lapTop = topL + topR + topD + topU - 4.0 * topHeight;
  let lapLower = lowL + lowR + lowD + lowU - 4.0 * lowerHeight;

  // ── Rescue 1: vortex_strength was dead ────────────────────────────────
  // HEAD's pointer spring lived in extraBuffer[133..138], which the host
  // re-uploads as zero every frame: pointerVelocity was identically 0 and
  // the only use of `vortex_strength` (the twist) never fired. The cursor
  // track now rides texels (0,0) and (1,0) of A (read back as C), as in
  // cyber-lens. No clock is stored (rgba16float cannot hold one): the track
  // is the smoothed per-frame cursor delta, so a stroke's total twist is its
  // path length whatever the frame rate. Nominal 60 Hz turns it into uv/s.
  let rawPointer = u.zoom_config.yz;
  let tA = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let tB = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let trackOk = abs(tA.w - TRACK_SENTINEL) < 0.002 && abs(tB.w - TRACK_SENTINEL) < 0.002;
  let cursorStep = clamp(rawPointer - tA.xy, vec2<f32>(-0.08), vec2<f32>(0.08));
  let cursorSmooth = select(vec2<f32>(0.0), mix(tB.xy, cursorStep, 0.35), trackOk);
  let pointer = rawPointer;
  let pointerVelocity = cursorSmooth * 60.0;

  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 58.0); let held = select(0.12, 1.0, u.zoom_config.w > 0.5);
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist, mouseDist > 0.001);
  let pointerTwist = dot(pointerVelocity, tangent / aspectVec) * mouseMask * vortexStrength;
  var topImpulse = mouseMask * held * (0.012 + waveStrength * 0.05) + pointerTwist * 0.012;
  var lowerImpulse = -mouseMask * held * layerSeparation * 0.025 - pointerTwist * 0.007;
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      // Rescue 2: pow(negative, 2.0) is undefined in WGSL (dist < front behind the ring) -> a plain square.
      let ringArg = (dist - age * (0.14 + bass * 0.06)) * 40.0;
      let ring = exp(-ringArg * ringArg) * exp(-age * 1.0);
      topImpulse += ring * sin(age * 6.5) * (0.02 + waveStrength * 0.055);
      lowerImpulse -= ring * cos(age * 5.2) * (0.012 + layerSeparation * 0.035); clickEnergy += ring;
    }
  }
  let p = (uv - 0.5) * aspectVec;
  let ambientTop = sin(p.x * 11.0 + time * (0.42 + bass * 0.16)) * cos(p.y * 9.0 - time * 0.31);
  let ambientLower = cos(p.x * 7.0 - time * (0.24 + mids * 0.12)) * sin(p.y * 13.0 + time * 0.27);
  let coupling = (lowerHeight - topHeight + 0.02) * (0.035 + layerSeparation * 0.12);
  let damping = mix(0.91, 0.986, viscosity);
  topVelocity = clamp(topVelocity * damping + lapTop * mix(0.13, 0.055, viscosity) + coupling
    + ambientTop * waveStrength * 0.0018 + topImpulse, -0.8, 0.8);
  lowerVelocity = clamp(lowerVelocity * damping + lapLower * mix(0.1, 0.045, viscosity) - coupling
    + ambientLower * waveStrength * 0.0015 + lowerImpulse, -0.7, 0.7);
  topHeight = clamp(topHeight + topVelocity * mix(0.085, 0.038, viscosity), 0.005, 0.9);
  lowerHeight = clamp(lowerHeight + lowerVelocity * mix(0.072, 0.032, viscosity), 0.005, 0.8);
  var storedA = vec4<f32>(topHeight, topVelocity, lowerHeight, lowerVelocity);
  storedA = select(storedA, vec4<f32>(rawPointer, 0.0, TRACK_SENTINEL), pixel.x == 0 && pixel.y == 0);
  storedA = select(storedA, vec4<f32>(cursorSmooth, 0.0, TRACK_SENTINEL), pixel.x == 1 && pixel.y == 0);
  textureStore(dataTextureA, pixel, storedA);

  let topGradient = vec2<f32>(topL - topR, topD - topU) * (5.0 + waveStrength * 10.0);
  let lowGradient = vec2<f32>(lowL - lowR, lowD - lowU) * (4.0 + layerSeparation * 8.0);
  let topNormal = normalize(vec3<f32>(topGradient, 0.28)); let lowerNormal = normalize(vec3<f32>(lowGradient, 0.34));
  // ── Idea 2: torn-film rim (native) ───────────────────────────────────
  // The edge of a hole in a film is not soft: surface tension gathers the
  // liquid into a thick bead that lenses the light and catches a highlight on
  // the lit side with a shadow on the other. The gap gradient comes free from
  // the 4 neighbours of BOTH layers already loaded for the Laplacians.
  let gapGrad = vec2<f32>((topL - lowL) - (topR - lowR), (topD - lowD) - (topU - lowU));
  let gapSlope = length(gapGrad);
  let gapDir = gapGrad / max(gapSlope, 0.0001);
  // slope per uv (the differences span 2 px), so the rim has the same width at any working size
  let rim = smoothstep(0.4, 3.0, gapSlope * res.y * 0.5) * RIM_AMP;
  let bulge = gapDir * rim * 0.007 / aspectVec;   // the bead refracts both layers
  let bead = rim * dot(gapDir, vec2<f32>(-0.6, -0.8));   // + lit flank / - shadow flank

  let topOffset = topNormal.xy * (0.012 + topHeight * 0.045) / aspectVec;
  let topUV = clamp(uv + topOffset + bulge, vec2<f32>(0.001), vec2<f32>(0.999));
  // ── Idea 1: compound refraction + Beer–Lambert gap tint (§12.2F) ────────
  // The lower layer is seen THROUGH the top surface, so its ray is bent by
  // the top slope as well as by the membrane (HEAD used the membrane only),
  // and it is absorbed by the water it crosses: the gap between the surfaces
  // along the ray. Red goes first, so a thick gap turns the lower layer deep
  // blue and a torn-through gap (lower above top) shows it undimmed and warm.
  let lowerUV = clamp(uv - lowerNormal.xy * (0.01 + lowerHeight * 0.055) / aspectVec + (topOffset * COMPOUND + bulge), vec2<f32>(0.001), vec2<f32>(0.999));
  let topLayer = textureSampleLevel(readTexture, u_sampler, topUV, 0.0);
  let lowerLayer = textureSampleLevel(readTexture, u_sampler, lowerUV, 0.0);
  let gapWater = max(topHeight - lowerHeight, 0.0) / max(topNormal.z, 0.5);
  let beer = clamp(exp(-(gapWater - GAP0) * BEER_SIGMA), vec3<f32>(0.45), vec3<f32>(1.35));
  // The top sample is absorbed by its own column too, measured from the resting depth (0.1) so a quiet surface keeps HEAD's look and
  // swells darken/blue-shift while troughs run clear.
  let beerTop = clamp(exp(-(topHeight - 0.1) * BEER_SIGMA * BEER_TOP), vec3<f32>(0.5), vec3<f32>(1.4));
  let separation = clamp(abs(topHeight - lowerHeight) * (2.0 + layerSeparation * 4.0) + clickEnergy * 0.18, 0.0, 1.0);
  let membrane = smoothstep(0.02, 0.35, abs(topHeight - lowerHeight));
  let spectral = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.32, 0.67) + topHeight * 0.5 - lowerHeight * 0.35 + time * 0.012));
  let fresnel = 0.025 + 0.975 * pow(clamp(1.0 - topNormal.z, 0.0, 1.0), 5.0);
  var color = mix(topLayer.rgb * beerTop, lowerLayer.rgb * vec3<f32>(0.78, 0.9, 1.08) * beer, separation * layerSeparation)
    + spectral * membrane * (0.08 + mids * 0.1) + vec3<f32>(0.42, 0.72, 1.0) * fresnel * (0.13 + treble * 0.1);
  color = max(color + vec3<f32>(0.9, 0.97, 1.1) * bead * (0.1 + layerSeparation * 0.2) * (0.6 + treble * 0.6), vec3<f32>(0.0));
  let alpha = clamp(max(topLayer.a, lowerLayer.a * separation) + membrane * 0.09 + fresnel * 0.06 + rim * 0.05, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.88, topHeight * 0.3 + lowerHeight * 0.18 + membrane * 0.03 + rim * 0.02), 0.0, 0.0, 0.0));
}
