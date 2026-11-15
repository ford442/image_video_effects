// ═══════════════════════════════════════════════════════════════════
//  Sim: Ink Diffusion RGBA
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: Bousseau drying-edge darkening; fibre/photo-valley granulation; capillary water-flux advection & chromatographic backruns (§12.2D); wet-puddle meniscus specular & cellulose translucency
//  A packing: raw state (pigment rgb, water a); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3f) -> vec3f {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + vec3f(b))) / (x * (c * x + vec3f(d)) + vec3f(e)), vec3f(0.0), vec3f(1.0));
}

fn stateAt(p: vec2i, dims: vec2i) -> vec4f {
  return textureLoad(dataTextureC, clamp(p, vec2i(0), dims - vec2i(1)), 0);
}

fn hash21(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let dimsU = textureDimensions(dataTextureC);
  if (gid.x >= dimsU.x || gid.y >= dimsU.y) { return; }
  let p = vec2i(gid.xy);
  let dims = vec2i(dimsU);
  let uv = (vec2f(gid.xy) + vec2f(0.5)) / vec2f(dimsU);
  let aspect = u.config.zw.x / max(u.config.zw.y, 1.0);
  let wetness = clamp(u.zoom_params.x, 0.0, 1.0);
  let diffusion = clamp(u.zoom_params.y, 0.0, 1.0);
  let mixing = clamp(u.zoom_params.z, 0.0, 1.0);
  let evaporation = clamp(u.zoom_params.w, 0.0, 1.0);
  let dt = clamp((1.0 / 60.0), 0.0, 0.033);
  let c = stateAt(p, dims);
  let n = stateAt(p + vec2i(0, 1), dims);
  let s = stateAt(p + vec2i(0, -1), dims);
  let e = stateAt(p + vec2i(1, 0), dims);
  let w = stateAt(p + vec2i(-1, 0), dims);
  let avg = (n + s + e + w) * 0.25;
  let water = clamp(c.a + (avg.a - c.a) * (0.035 + 0.18 * wetness), 0.0, 1.0);
  var pigment = max(c.rgb + (avg.rgb - c.rgb) * (0.012 + 0.16 * diffusion * (0.2 + water)), vec3f(0.0));

  // ── Idea 3: capillary water-flux advection & chromatographic backruns (§12.2D) ──
  // Water-height gradients drive outward capillary flow from wet pools toward fast-drying
  // margins; upwind transport carries finer phthalo/cyan grains farther than heavy mineral
  // pigments, producing ruffled cauliflower backruns when fresh drops hit damp washes.
  let waterGrad = vec2f(e.a - w.a, n.a - s.a);
  let upwindX = select(w.rgb, e.rgb, waterGrad.x > 0.0);
  let upwindY = select(s.rgb, n.rgb, waterGrad.y > 0.0);
  let mobility = vec3f(1.18, 0.96, 0.76) * (0.16 + 0.52 * wetness * (0.35 + diffusion * 0.65));
  let capFlux = (upwindX - c.rgb) * abs(waterGrad.x) + (upwindY - c.rgb) * abs(waterGrad.y);
  pigment = max(pigment + capFlux * mobility * (0.35 + 0.65 * water), vec3f(0.0));

  let chromaMean = vec3f(dot(pigment, vec3f(0.333333)));
  pigment = mix(pigment, chromaMean, 0.012 * mixing * water);

  let audio = clamp(plasmaBuffer[0].xyz, vec3f(0.0), vec3f(2.0));
  let pointer = u.zoom_config.yz;
  let q = (uv - pointer) * vec2f(aspect, 1.0);
  let held = step(0.5, u.zoom_config.w);
  let brush = exp(-dot(q, q) * (210.0 - 100.0 * wetness));
  let rotatingInk = 0.5 + 0.5 * cos(vec3f(0.0, 2.094, 4.189) + u.config.x * 0.7);
  pigment += held * brush * (0.028 + 0.09 * max(audio, vec3f(0.08))) * rotatingInk;
  var nextWater = water + held * brush * 0.045;

  let clickCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < clickCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = u.config.x - event.z;
    let liveMask = f32(age >= 0.0 && age < 2.4);
    let safeAge = max(age, 0.0);
    let cp = event.xy;
    let cq = (uv - cp) * vec2f(aspect, 1.0);
    let radius = 0.04 + safeAge * (0.09 + 0.06 * wetness);
    let ring = liveMask * exp(-pow((length(cq) - radius) * 55.0, 2.0)) * exp(-safeAge * 1.3);
    let hue = 0.5 + 0.5 * cos(vec3f(0.0, 2.094, 4.189) + f32(i) * 1.7);
    pigment += ring * hue * (0.018 + 0.045 * audio.y);
    nextWater += ring * 0.025;
  }

  let fibre = 0.6 * hash21(vec2f(p)) + 0.4 * hash21(floor(vec2f(p) / 3.0) + vec2f(17.0, 5.0));
  pigment *= exp(-dt * (0.08 + 0.42 * evaporation));
  nextWater = clamp(nextWater * exp(-dt * (0.14 + 0.75 * evaporation)), 0.0, 1.0);
  pigment = clamp(pigment + (fibre - 0.5) * 0.0007 * nextWater * (1.0 - nextWater), vec3f(0.0), vec3f(2.0));
  textureStore(dataTextureA, p, vec4f(pigment, nextWater));

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // ── Idea 4: wet-puddle meniscus specular & wet-cellulose translucency ─
  // Water filling air gaps between cotton fibres makes wet paper more translucent to the
  // underlying photo, while beaded puddle slopes (∇water) catch raking studio specular sheen.
  let wetTranslucency = smoothstep(0.05, 0.75, nextWater);
  let paper = mix(vec3f(0.96, 0.94, 0.89), source.rgb, mix(0.52, 0.80, wetTranslucency));
  let meniscusSlope = waterGrad * 14.0 + vec2f(fibre - 0.5) * 0.18 * wetTranslucency;
  let meniscusN = normalize(vec3f(-meniscusSlope, 1.0));
  let halfLight = normalize(vec3f(-0.36, 0.48, 0.80) + vec3f(0.0, 0.0, 1.0));
  let puddleSpec = pow(max(dot(meniscusN, halfLight), 0.0), 48.0) * wetTranslucency * smoothstep(0.006, 0.08, length(waterGrad));

  // Idea 1 — edge darkening (Bousseau et al. 2006)
  let dryness = 1.0 - clamp(nextWater, 0.0, 1.0);
  let densGrad = 0.5 * length(vec2f(dot(e.rgb - w.rgb, vec3f(0.333333)), dot(n.rgb - s.rgb, vec3f(0.333333))));
  let edgeDark = 1.0 + clamp(densGrad * 9.0, 0.0, 1.2) * (0.35 + 0.65 * dryness);
  // Idea 2 — granulation into paper valleys (fibre grain + photo tone)
  let valley = clamp(fibre + (0.5 - dot(source.rgb, vec3f(0.299, 0.587, 0.114))) * 0.5, 0.0, 1.0);
  let granulate = 1.0 + (valley - 0.5) * 0.9 * dryness;
  let absorb = exp(-pigment * edgeDark * granulate * vec3f(2.8, 2.45, 2.65));
  let stained = paper * absorb + pigment.bgr * 0.08 * nextWater + vec3f(1.12, 1.08, 1.02) * puddleSpec * (0.65 + audio.z * 0.25);
  let edge = length(vec2f(e.r - w.r, n.g - s.g));
  let color = aces(max(stained + edge * vec3f(0.08, 0.11, 0.15) + audio * pigment * 0.12, vec3f(0.0)));
  let alpha = clamp(source.a * 0.15 + max(max(pigment.r, pigment.g), pigment.b) * 0.72 + nextWater * 0.22 + puddleSpec * 0.2, 0.0, 1.0);
  textureStore(writeTexture, p, vec4f(color, alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, p, vec4f(clamp(mix(depth, depth * (1.0 - nextWater * 0.12), alpha), 0.0, 1.0), 0.0, 0.0, 0.0));
}
