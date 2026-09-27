// ═══════════════════════════════════════════════════════════════════
//  WASM HLS Physarum Swarm
//  Category: generative
//  Features: agent-based, audio-reactive, mouse-driven, video-food,
//            upgraded-rgba, temporal-feedback, chromatic-trails
//  Complexity: High
//  Created: 2026-06-28
//  Upgraded: 2026-09-27  (RESCUED: HEAD kept agent state in extraBuffer, which the runtime
//            re-uploads every frame, so every agent re-seeded and the sim was static noise)
//  Ideas: peristaltic cytoplasm streaming pulses along vein heading; tube-shaded veins
//         (trail-gradient normal + specular) with a foraging-front colour where mass > trail
//  A packing: raw sim state (trail, mx, my, hue); ACES on writeTexture only
//  Rescue: Eulerian agents. |m| = agent mass, m/|m| = heading. No extraBuffer use.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const FLOOR: f32 = 0.07;   // RESCUE: mass floor / re-inflation (opposing streams never annihilate the field)
const CAP: f32 = 0.6;
const JC: f32 = 0.6;       // RESCUE: convergence gain (Jacobian of the agent flow piles mass onto veins)
const DIRG: f32 = 0.05;
const RHO0: f32 = 0.15;
const WANDER: f32 = 0.15;
const DEC_REF: f32 = 0.04125; // 1 - decay at the saved default slider (0.75 -> 0.959)

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash32(seed: u32) -> f32 {
  var x = seed;
  x ^= x >> 16u;
  x *= 0x7feb352du;
  x ^= x >> 15u;
  x *= 0x846ca68bu;
  x ^= x >> 16u;
  return f32(x) / f32(0xffffffffu);
}

fn wrapi(c: vec2<i32>) -> vec2<i32> {
  let d = vec2<i32>(i32(u.config.z), i32(u.config.w));
  return ((c % d) + d) % d;
}

// RESCUE: seed path. C is zero-initialised (first frame / resize): give every pixel hash mass + heading.
fn seedState(c: vec2<i32>) -> vec4<f32> {
  let w = u32(u.config.z);
  let id = u32(c.y) * w + u32(c.x);
  let ang = hash32(id * 3u + 2u) * 6.28318;
  let mass = RHO0 * (0.5 + hash32(id * 3u));
  return vec4<f32>(0.0, mass * cos(ang), mass * sin(ang), 0.0);
}

// Exact load of C (torus wrap); all-zero texel => seeded state.
fn state(c: vec2<i32>) -> vec4<f32> {
  let cw = wrapi(c);
  let s = textureLoad(dataTextureC, cw, 0);
  if (dot(s, s) == 0.0) { return seedState(cw); }
  return s;
}

fn velocity(c: vec2<i32>, speed: f32) -> vec2<f32> {
  let m = state(c).yz;
  return speed * m / max(length(m), DIRG);
}

fn sense(pos: vec2<f32>, angle: f32, sensorDist: f32, res: vec2<f32>) -> f32 {
  let dir = vec2<f32>(cos(angle), sin(angle));
  let sc = wrapi(vec2<i32>(floor(pos + dir * sensorDist)));
  let trail = textureLoad(dataTextureC, sc, 0).r;
  let uv = (vec2<f32>(sc) + 0.5) / res;
  let foodColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let food = (foodColor.r + foodColor.g + foodColor.b) * 0.333;
  return trail + food * 2.5;
}

fn paletteChromatic(t: f32, audio: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5 + audio * 0.3, 0.5, 0.5 - audio * 0.2);
  let c = vec3<f32>(1.0, 1.0, 0.8);
  let d = vec3<f32>(0.1 + audio * 0.3, 0.4, 0.7 - audio * 0.2);
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters (roles and ranges unchanged)
  let sensorAngle = mix(0.3, 1.2, u.zoom_params.x);
  let sensorDist = mix(5.0, 25.0, u.zoom_params.y);
  let decayRate = mix(0.85, 0.995, u.zoom_params.z);
  let depositAmount = mix(0.3, 2.0, u.zoom_params.w);

  let idx = gid.y * dims.x + gid.x;
  let frameSeed = u32(time * 1000.0);
  let pos = vec2<f32>(coord);

  // Audio-reactive turn speed / move speed / deposit (kept from HEAD)
  let turnSpeed = 0.5 + bass * 3.0 + mid * 1.5;
  let audioDeposit = depositAmount * (1.0 + bass * 2.0);
  let moveSpeed = 1.5 + treble * 1.0;
  let dTurn = min(turnSpeed * sensorAngle, 0.9);

  // ── RESCUE 1: semi-Lagrangian gather of agent mass/heading from p - u ─────────
  let u0 = velocity(coord, moveSpeed);
  let sp = pos - u0;
  let sw = sp - floor(sp / res) * res;
  let f0 = floor(sw);
  let fr = sw - f0;
  let ic = vec2<i32>(f0);
  var massAdv = 0.0;
  var bestS = -1.0;
  var bestM = vec2<f32>(0.0);
  var bestH = 0.0;
  for (var k = 0; k < 4; k++) {
    let ox = k & 1;
    let oy = k >> 1;
    let wt = select(1.0 - fr.x, fr.x, ox == 1) * select(1.0 - fr.y, fr.y, oy == 1);
    let s = state(ic + vec2<i32>(ox, oy));
    let mm = length(s.yz);
    massAdv += wt * mm;                    // scalar mass average: never cancels
    let sc = wt * mm;
    if (sc > bestS) { bestS = sc; bestM = s.yz; bestH = s.w; }   // winner-take-all heading
  }

  // ── RESCUE 2: Jacobian of the flow. Converging streams pile mass onto veins. ──
  let uE = velocity(coord + vec2<i32>(1, 0), moveSpeed);
  let uW = velocity(coord + vec2<i32>(-1, 0), moveSpeed);
  let uS = velocity(coord + vec2<i32>(0, 1), moveSpeed);
  let uN = velocity(coord + vec2<i32>(0, -1), moveSpeed);
  let dux_dx = 0.5 * (uE.x - uW.x);
  let dux_dy = 0.5 * (uS.x - uN.x);
  let duy_dx = 0.5 * (uE.y - uW.y);
  let duy_dy = 0.5 * (uS.y - uN.y);
  let jac = clamp((1.0 - dux_dx) * (1.0 - duy_dy) - dux_dy * duy_dx, 0.5, 2.0);

  var angle = atan2(bestM.y, bestM.x);
  if (massAdv < 1e-6) { angle = hash32(idx * 11u + frameSeed) * 6.28318; }

  // Sense in three directions (HEAD weights: trail + food * 2.5)
  let wF = sense(pos, angle, sensorDist, res);
  let wL = sense(pos, angle + sensorAngle, sensorDist, res);
  let wR = sense(pos, angle - sensorAngle, sensorDist, res);

  if (wF > wL && wF > wR) {
    // Straight
  } else if (wF < wL && wF < wR) {
    let rnd = hash32(idx * 7u + frameSeed);
    if (rnd > 0.5) { angle += dTurn; } else { angle -= dTurn; }
  } else if (wL > wR) {
    angle += dTurn;
  } else {
    angle -= dTurn;
  }
  angle += WANDER * (hash32(idx * 13u + frameSeed) - 0.5);

  // Mouse attraction (HEAD: 150 px radius, blend * 0.3). Shortest-arc blend, zero-vector guard.
  let mousePos = u.zoom_config.yz * res;
  let distToMouse = distance(pos, mousePos);
  let mouseInfluence = 150.0;
  if (distToMouse < mouseInfluence && distToMouse > 1e-3) {
    let dirToMouse = (mousePos - pos) / distToMouse;
    let desiredAngle = atan2(dirToMouse.y, dirToMouse.x);
    let blend = 1.0 - distToMouse / mouseInfluence;
    let dl = (desiredAngle - angle + 3.14159265) - 6.28318531 * floor((desiredAngle - angle + 3.14159265) / 6.28318531) - 3.14159265;
    angle += dl * blend * 0.3;
  }

  let massNew = clamp(max(massAdv, FLOOR) * (1.0 + JC * (jac - 1.0)), FLOOR, CAP);
  let mNew = massNew * vec2<f32>(cos(angle), sin(angle));

  // ── Trail: 3x3 blur (torus) + decay + deposit proportional to agent mass ──────
  var sumT = 0.0;
  var sumM = vec2<f32>(0.0);
  var sumAbsM = 0.0;
  var tN: array<f32, 9>;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let s = state(coord + vec2<i32>(i, j));
      tN[(j + 1) * 3 + (i + 1)] = s.x;
      sumT += s.x;
      sumM += s.yz;
      sumAbsM += length(s.yz);
    }
  }
  let diffused = (sumT / 9.0) * decayRate;
  let depositScale = (1.0 - decayRate) / DEC_REF;   // decay changes persistence, not brightness
  let trailNew = clamp(diffused + 0.05 * audioDeposit * massNew * (1.0 - diffused) * depositScale, 0.0, 1.0);
  let hueNew = mix(bestH, time * 0.05, 0.01);

  // A = raw sim state (trail, mx, my, hue). No ACES on stored fields.
  textureStore(dataTextureA, coord, vec4<f32>(trailNew, mNew.x, mNew.y, hueNew));

  // ═══ Display ═══════════════════════════════════════════════════════
  // IDEA 2: tube shading. Normal from the trail gradient (3x3 of C), diffuse + specular.
  let gx = 0.5 * (tN[5] - tN[3]);
  let gy = 0.5 * (tN[7] - tN[1]);
  let hs = 8.0 / (sumT / 9.0 + 0.06);
  let nrm = normalize(vec3<f32>(-gx * hs, -gy * hs, 1.0));
  let L = normalize(vec3<f32>(-0.45, -0.55, 0.7));
  let Hh = normalize(L + vec3<f32>(0.0, 0.0, 1.0));
  let diff = max(dot(nrm, L), 0.0);
  let spec = pow(max(dot(nrm, Hh), 0.0), 28.0);

  // IDEA 2b: foraging front = mass is high but trail has not caught up with the trail that mass implies.
  let teq = 1.21 * audioDeposit * massNew;
  let young = sat((teq - trailNew) / (0.3 * teq + 0.02));
  let front = smoothstep(0.3, 0.5, massNew) * young;

  // IDEA 1: peristaltic streaming. Pulse phase runs along the local heading (mass-weighted 3x3 mean).
  let coherence = length(sumM) / (sumAbsM + 1e-4);
  let hdir = sumM / max(length(sumM), 1e-5);
  let phase = dot(pos, hdir) * (6.28318 / 24.0) - time * 3.0;
  let pulse = 0.5 + 0.5 * sin(phase);
  let veinW = coherence * smoothstep(0.03, 0.2, trailNew);
  let streak = mix(1.0, 0.55 + 0.9 * pulse, veinW);

  let cov = sat(pow(trailNew, 0.7) * 1.6);
  let baseCol = paletteChromatic(hueNew + trailNew * 2.0, bass);
  var tube = baseCol * (0.3 + 0.9 * diff) * streak + vec3<f32>(spec * 0.6);
  tube = mix(tube, vec3<f32>(1.0, 0.78, 0.28) * (0.6 + 0.8 * diff), front * 0.85);
  let cov2 = max(cov, front * 0.8);

  let uv = pos / res;
  let vidColor = textureSampleLevel(readTexture, u_sampler, (pos + 0.5) / res, 0.0).rgb;
  var col = mix(vidColor, tube, cov2);
  col += vec3<f32>(0.2, 0.1, 0.4) * bass * trailNew * 0.5;      // audio bloom (kept)

  col = acesFilm(col);
  let alpha = mix(0.35, 1.0, cov2);   // semantic: vein / foraging-front coverage

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));

  let depthUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
