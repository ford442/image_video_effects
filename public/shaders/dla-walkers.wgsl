// ═══════════════════════════════════════════════════════════════════
//  DLA Crystals — Walkers
//  Category: artistic
//  Features: mouse-driven, audio-reactive, sim-ring
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: tip screening; branch-angle facets; attraction reach
//  A packing: raw sim (frozen, time, hue, facet angle). No display write
// ═══════════════════════════════════════════════════════════════════
//  One invocation per walker. Walkers live in the @group(1) sim ring
//  (src/contracts/bind_group1.json), not in extraBuffer.
//  simState[i]: .xy position (pixels), .z hue seed, .w alive flag
//  zoom_params: .x walker speed, .y attract, .z stickiness, .w branch angle

#include "_prelude.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(2) var<uniform> simParams: SimParams;

const TAU: f32 = 6.28318530718;
const MAX_STEPS: u32 = 4u;

fn pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

fn rand(seed: ptr<function, u32>) -> f32 {
  *seed = pcg(*seed);
  return f32(*seed) / 4294967295.0;
}

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

fn spawn(seed: ptr<function, u32>, res: vec2<f32>) -> vec4<f32> {
  let pos = vec2<f32>(rand(seed), rand(seed)) * (res - vec2<f32>(1.0));
  return vec4<f32>(pos, rand(seed), 1.0);
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= simParams.stateCount) { return; }

  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (resI.x < 2 || resI.y < 2) { return; }

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let walkerSpeed = mix(0.5, 3.0, u.zoom_params.x);
  let attractStrength = mix(0.0, 0.5, u.zoom_params.y);
  let stickiness = clamp(mix(0.25, 0.95, u.zoom_params.z + bass * 0.08), 0.0, 1.0);
  let branchAngle = u.zoom_params.w;

  var seed = pcg(i ^ pcg(simParams.frame + 0x9e3779b9u));
  var w = simState[i];

  let outside = any(w.xy < vec2<f32>(0.0)) || any(w.xy > res - vec2<f32>(1.0));
  if (simParams.frame == 0u || w.w < 0.5 || outside) {
    simState[i] = spawn(&seed, res);
    return;
  }

  // Attraction toward the pointer seed, else the canvas centre.
  let mouse = u.zoom_config.yz;
  let inCanvas = all(mouse >= vec2<f32>(0.0)) && all(mouse <= vec2<f32>(1.0));
  let goal = select(vec2<f32>(0.5), mouse, inCanvas) * res;

  var pos = w.xy;
  let steps = clamp(u32(walkerSpeed + 0.5), 1u, MAX_STEPS);
  // ── Idea 3: attraction reach — faster walkers sense frozen crystal farther out
  let reach = f32(clamp(i32(round(walkerSpeed * 2.0)), 2, 6));
  var crystalPull = vec2<f32>(0.0);
  for (var k = 0; k < 8; k = k + 1) {
    let angK = f32(k) * TAU / 8.0;
    let probe = vec2<i32>(pos + vec2<f32>(cos(angK), sin(angK)) * reach);
    let sensed = load(probe, resI);
    crystalPull = select(crystalPull, crystalPull + vec2<f32>(cos(angK), sin(angK)), sensed.r > 0.5);
  }
  for (var s = 0u; s < steps; s = s + 1u) {
    let ang = rand(&seed) * TAU;
    let toTarget = goal - pos;
    let pull = select(vec2<f32>(0.0), normalize(toTarget), dot(toTarget, toTarget) > 1.0);
    let dir = normalize(vec2<f32>(cos(ang), sin(ang)) + pull * attractStrength * 1.5 + crystalPull * 0.35 + vec2<f32>(1e-4));
    let next = clamp(pos + dir, vec2<f32>(0.0), res - vec2<f32>(1.0));
    let p = vec2<i32>(next);

    // Never walk into the crystal — bounce off it instead.
    if (load(p, resI).r > 0.5) { continue; }
    pos = next;

    var hueSum = 0.0;
    var hueCount = 0.0;
    for (var dy = -1; dy <= 1; dy = dy + 1) {
      for (var dx = -1; dx <= 1; dx = dx + 1) {
        if (dx == 0 && dy == 0) { continue; }
        let n = load(p + vec2<i32>(dx, dy), resI);
        if (n.r > 0.5) {
          hueSum += n.b;
          hueCount += 1.0;
        }
      }
    }

    if (hueCount > 0.0) {
      // ── Idea 1: tip screening — a fjord (many frozen neighbors) sticks less than a tip
      let tipGate = mix(1.0, 0.28, clamp(hueCount / 5.0, 0.0, 1.0));
      // ── Idea 2: branch-angle facets — stick peaks on a 2-to-6-fold set of directions
      let fold = 2.0 + clamp(branchAngle, 0.0, 1.0) * 4.0;
      let growthAngle = atan2(dir.y, dir.x);
      let facet = pow(max(abs(cos(growthAngle * fold)), 0.0), 4.0);
      let stickGate = clamp(stickiness * tipGate * (0.35 + 0.65 * facet), 0.0, 1.0);
      if (rand(&seed) < stickGate) {
        // Freeze: this walker becomes crystal, then respawns elsewhere.
        let hue = fract(hueSum / hueCount + (rand(&seed) - 0.5) * 0.06 + treble * 0.05 + attractStrength * 0.08);
        textureStore(dataTextureA, p, vec4<f32>(1.0, time, hue, fract(growthAngle / TAU + 0.5)));
        simState[i] = spawn(&seed, res);
        return;
      }
    }
  }

  // Trail stamp: free pixel remembers when a walker last passed (render fades it).
  let here = vec2<i32>(pos);
  if (load(here, resI).r < 0.5) {
    textureStore(dataTextureA, here, vec4<f32>(0.0, time, w.z, 0.0));
  }
  simState[i] = vec4<f32>(pos, w.z, 1.0);
}
