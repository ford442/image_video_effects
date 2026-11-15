// ═══════════════════════════════════════════════════════════════════
//  Fire Smoke Volumetric Fog
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: sub-pixel Boussinesq buoyant advection (§12.2D), baroclinic plume roll-up & persistent hearth ember bed; depth-occluded 7-slice volume, Henyey-Greenstein flame in-scattering (§12.2F) & Planckian Color Temperature blackbody (§12.2F)
//  A packing: raw (smoke density, temperature, soot, lateral momentum)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3f) -> vec3f {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + vec3f(b))) / (x * (c * x + vec3f(d)) + vec3f(e)), vec3f(0.0), vec3f(1.0));
}

fn stateAt(p: vec2i, d: vec2i) -> vec4f {
  return textureLoad(dataTextureC, clamp(p, vec2i(0), d - vec2i(1)), 0);
}

fn bilerpState(pos: vec2f, d: vec2i) -> vec4f {
  let p0 = vec2i(floor(pos));
  let f = fract(pos);
  let s00 = stateAt(p0, d);
  let s10 = stateAt(p0 + vec2i(1, 0), d);
  let s01 = stateAt(p0 + vec2i(0, 1), d);
  let s11 = stateAt(p0 + vec2i(1, 1), d);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn hash21(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2f(1.0, 0.0)), w.x),
    mix(hash21(i + vec2f(0.0, 1.0)), hash21(i + vec2f(1.0, 1.0)), w.x),
    w.y
  );
}

fn blackbodyFlame(temp: f32, colorTemp: f32) -> vec3f {
  let t = clamp(temp * mix(0.65, 1.55, colorTemp), 0.0, 2.6);
  let coal = vec3f(2.8, 0.16, 0.015);
  let amber = vec3f(5.6, 1.35, 0.12);
  let solar = vec3f(6.4, 4.1, 1.45);
  let blueCore = vec3f(4.6, 5.5, 7.2);
  let low = mix(coal, amber, smoothstep(0.08, 0.75, t));
  let mid = mix(low, solar, smoothstep(0.65, 1.55, t));
  return mix(mid, blueCore, smoothstep(1.45, 2.45, t) * colorTemp);
}

fn henyeyGreenstein(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  let denom = max(1.0 + g2 - 2.0 * g * cosTheta, 0.04);
  return (1.0 - g2) / (12.56637 * denom * sqrt(denom));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let du = textureDimensions(dataTextureC);
  if (gid.x >= du.x || gid.y >= du.y) { return; }

  let p = vec2i(gid.xy);
  let d = vec2i(du);
  let resF = vec2f(du);
  let uv = (vec2f(gid.xy) + 0.5) / resF;
  let time = u.config.x;
  let dt = 1.0 / 60.0;
  let audio = clamp(plasmaBuffer[0].xyz, vec3f(0.0), vec3f(2.0));

  let fireIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let smokeParam = clamp(u.zoom_params.y, 0.0, 1.0);
  let turb = clamp(u.zoom_params.z, 0.0, 1.0);
  let colorTemp = clamp(u.zoom_params.w, 0.0, 1.0);

  let heatGain = 0.5 + 2.5 * fireIntensity;
  let smokeGain = 0.3 + 2.0 * smokeParam;
  let fogDepth = 0.55 + 2.25 * smokeParam;

  let c = stateAt(p, d);
  let n = stateAt(p + vec2i(0, -1), d);
  let s = stateAt(p + vec2i(0, 1), d);
  let e = stateAt(p + vec2i(1, 0), d);
  let w = stateAt(p + vec2i(-1, 0), d);
  let avg = (n + s + e + w) * 0.25;

  // ── Idea 1: sub-pixel Boussinesq buoyant advection (§12.2D) & baroclinic vorticity ──
  // Screen y=0 is top: buoyant plumes rise toward -y by sampling upstream at +y (below).
  let buoyancy = max(0.26 + 1.55 * c.y - 0.18 * c.z, 0.04) * (1.0 + audio.x * 0.22);
  let swirlEddy = (valueNoise(uv * (6.0 + turb * 10.0) + vec2f(0.0, time * 0.8)) - 0.5) * turb * 0.55;
  let backOffset = vec2f(-(c.w * 0.42 + swirlEddy), buoyancy) * dt * resF;
  let adv = bilerpState(vec2f(p) + backOffset, d);

  var density = mix(adv.x, avg.x, 0.022 + 0.055 * turb);
  var temp = mix(adv.y, avg.y, 0.032);
  var soot = mix(adv.z, avg.z, 0.018);
  var momentum = mix(adv.w, avg.w, 0.045);

  // Baroclinic torque: horizontal temperature gradient spins smoke flanks into rolling mushroom caps
  let baroclinic = (e.y - w.y) * (0.24 + 0.42 * turb);
  momentum += baroclinic + (s.x - n.x + w.x - e.x) * 0.08 * turb + swirlEddy * 0.06;

  // Persistent bottom ember hearth + bright scene ignition pockets + hover/held pointer torch
  let baseScene = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sceneLuma = dot(baseScene.rgb, vec3f(0.2126, 0.7152, 0.0722));
  let hearthTongues = valueNoise(vec2f(uv.x * (7.0 + turb * 8.0), time * 0.95))
                    * valueNoise(vec2f(uv.x * 15.0 - time * 0.4, time * 1.4));
  let bottomHearth = exp(-max(1.0 - uv.y, 0.0) * 20.0) * (0.35 + 1.15 * hearthTongues);
  let lumaEmbers = smoothstep(0.72, 0.98, sceneLuma) * exp(-max(1.0 - uv.y, 0.0) * 4.5) * 0.22;
  let emberBed = (bottomHearth + lumaEmbers) * (0.35 + 0.85 * fireIntensity);

  let aspect = u.config.zw.x / max(u.config.zw.y, 1.0);
  let mp = u.zoom_config.yz;
  let q = (uv - mp) * vec2f(aspect, 1.0);
  let held = select(0.18, 1.0, u.zoom_config.w > 0.5);
  let torch = held * exp(-dot(q, q) * 260.0);

  let totalIgnition = emberBed * 0.55 + torch;
  temp += totalIgnition * (0.048 + audio.z * 0.10) * heatGain;
  density += (emberBed * 0.45 + torch) * (0.022 + audio.x * 0.065) * smokeGain;
  soot += (emberBed * 0.38 + torch) * (0.011 + audio.y * 0.03);
  momentum += torch * (audio.y - audio.z) * 0.08;

  let clicks = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < clicks; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    let isLive = f32(age >= 0.0 && age < 1.8);
    let safeAge = clamp(age, 0.0, 1.8);
    let cq = (uv - event.xy) * vec2f(aspect, 1.0);
    let ring = isLive * exp(-pow((length(cq) - (0.03 + safeAge * 0.2)) * 60.0, 2.0)) * exp(-safeAge * 1.7);
    density += ring * (0.022 + audio.x * 0.04);
    temp += ring * (0.032 + audio.z * 0.07);
    soot += ring * 0.014;
    momentum += ring * sign(cq.x + 0.0001) * 0.05;
  }

  density = clamp(density * exp(-dt * (0.24 + 0.18 / smokeGain)), 0.0, 2.5);
  temp = clamp(temp * exp(-dt * (0.72 + 0.18 / heatGain)), 0.0, 2.5);
  soot = clamp(soot * exp(-dt * 0.18), 0.0, 2.0);
  momentum = clamp(momentum * exp(-dt * 1.35), -1.5, 1.5);
  textureStore(dataTextureA, p, vec4f(density, temp, soot, momentum));

  // ── Idea 2: depth-occluded 7-slice volume, Henyey-Greenstein scatter (§12.2F) & Planckian Color Temperature ──
  let sceneDepth = textureLoad(readDepthTexture, p, 0).r;
  let refractUV = clamp(uv + vec2f(momentum, -temp) / resF * (5.0 + 4.0 * fireIntensity), vec2f(0.0), vec2f(1.0));
  let sceneSample = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);

  let flameDir = normalize(vec3f(e.y - w.y, n.y - s.y, 0.45));
  let hgPhase = henyeyGreenstein(clamp(flameDir.z, -1.0, 1.0), 0.52) * 2.8;
  let neighborHeat = max(avg.y, temp * 0.85);
  let smokeAlbedo = mix(vec3f(0.13, 0.11, 0.10), vec3f(0.09, 0.12, 0.16), colorTemp) * (0.65 + soot * 0.45);
  let flameCol = blackbodyFlame(temp, colorTemp);
  let scatterCol = blackbodyFlame(neighborHeat * 0.85, colorTemp);

  var trans = 1.0;
  var volume = vec3f(0.0);
  for (var j = 0; j < 7; j++) {
    let z = (f32(j) + 0.5) / 7.0;
    let billow = valueNoise(uv * (5.5 + f32(j) * 2.2 + turb * 6.0) + vec2f(momentum * 0.35, time * (0.45 + 0.12 * f32(j))));
    let depthGate = smoothstep(z - 0.14, z + 0.14, 1.08 - sceneDepth * 0.68);
    let layer = density * (0.52 + 0.72 * billow) * depthGate;
    let absorb = exp(-layer * fogDepth * 0.18);
    let scatterWeight = (1.0 - absorb) * hgPhase;
    let coreEmit = flameCol * temp * temp * (1.0 - z * 0.75) * 0.065 * depthGate;
    let inScatter = (smokeAlbedo * 0.85 + scatterCol * neighborHeat * scatterWeight * 0.38) * layer * 0.16;
    volume += trans * (coreEmit + inScatter);
    trans *= absorb;
  }

  volume += density * vec3f(audio.x * 0.07, audio.y * 0.04, audio.z * 0.06);
  let finalRGB = aces(max(sceneSample.rgb * trans + volume, vec3f(0.0)));
  let plumeAlpha = clamp((1.0 - trans) + clamp(temp * 0.25, 0.0, 0.35) + sceneSample.a * 0.15, 0.04, 1.0);
  let outDepth = clamp(mix(sceneDepth, 0.18 + 0.52 * (1.0 - trans), clamp(1.0 - trans, 0.0, 0.85)), 0.0, 1.0);

  textureStore(writeTexture, p, vec4f(finalRGB, plumeAlpha));
  textureStore(writeDepthTexture, p, vec4f(outDepth, 0.0, 0.0, 0.0));
}
