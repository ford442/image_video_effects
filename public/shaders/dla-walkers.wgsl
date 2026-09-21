// ═══ DLA CRYSTALS — BROWNIAN WALKERS (graph node 2 of 3) ═══════════════════
//  One invocation per walker (dispatch "simState"). Walkers are real particles
//  in the group-1 sim ring (src/contracts/bind_group1.json), not pixels:
//    simState[i] : .xy position (working-texture pixels), .z life (frames, 0 = respawn),
//                  .w personal heading bias (radians)
//  They read the freeze mask through dataC (A → C copy before this node) and,
//  on contact, freeze their pixel into dataA and respawn next frame. Free
//  pixels they cross get walker dust in dataA.a.
//  Upgrade ideas: (1) real Brownian walkers in simState, (2) hex-lattice snap
//  — Branch Angle pulls each step onto six 60° directions for snowflake arms,
//  (3) walker dust trails, (4) bass-driven stickiness surges.
//  zoom_params: .x walker speed, .y attraction, .z stickiness, .w branch angle
//  Audio: extraBuffer[0] bass (read only). Never writes extraBuffer.

#include "_prelude.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;

const TAU: f32 = 6.28318530718;
const HEX_STEP: f32 = 1.04719755120; // 60°
const MAX_LIFE: f32 = 900.0;

fn pcg(v: u32) -> u32 {
  let s = v * 747796405u + 2891336453u;
  let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
  return (w >> 22u) ^ w;
}

fn rand01(seed: ptr<function, u32>) -> f32 {
  *seed = pcg(*seed);
  return f32(*seed) * (1.0 / 4294967295.0);
}

fn mask(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= simParams.stateCount) { return; }

  let res = u.config.zw;
  let resI = vec2<i32>(res);
  let time = u.config.x;
  let bass = extraBuffer[0];

  let walkerSpeed = u.zoom_params.x;
  let attract = u.zoom_params.y;
  let stickiness = clamp(mix(0.2, 0.95, u.zoom_params.z) + bass * 0.2, 0.0, 1.0);
  let hexSnap = u.zoom_params.w;
  let steps = 1u + u32(walkerSpeed * 5.0);
  let stepLen = mix(0.8, 1.6, walkerSpeed);

  var seed = pcg(i * 9781u + simParams.frame * 6271u + 1u);
  let w = simState[i];

  // Respawn: fresh start, dead walker, or too old (keeps the field evenly stirred).
  if (time < 0.05 || w.z <= 0.0 || w.z > MAX_LIFE) {
    let p = vec2<f32>(rand01(&seed), rand01(&seed)) * res;
    let heading = rand01(&seed) * TAU;
    // Spawning inside the crystal wastes a walker — stay dead and retry next frame.
    let alive = select(1.0, 0.0, mask(vec2<i32>(p), resI).r > 0.5);
    simState[i] = vec4<f32>(p, alive, heading);
    return;
  }

  var pos = w.xy;
  let attractor = u.zoom_config.yz * res;

  for (var s = 0u; s < steps; s = s + 1u) {
    var a = rand01(&seed) * TAU + w.w * 0.15;
    a = mix(a, round(a / HEX_STEP) * HEX_STEP, hexSnap);
    var stepV = vec2<f32>(cos(a), sin(a)) * stepLen;

    let toward = attractor - pos;
    let d = length(toward);
    if (d > 1.0) {
      stepV += toward / d * attract * 0.6;
    }

    let next = clamp(pos + stepV, vec2<f32>(0.5), res - vec2<f32>(0.5));
    let nextI = vec2<i32>(next);
    // Never walk into the crystal; touching it happens from outside.
    if (mask(nextI, resI).r < 0.5) {
      pos = next;
    }

    let here = vec2<i32>(pos);
    var hueSum = 0.0;
    var hueCount = 0.0;
    var tint = 0.0;
    for (var dy = -1; dy <= 1; dy = dy + 1) {
      for (var dx = -1; dx <= 1; dx = dx + 1) {
        if (dx == 0 && dy == 0) { continue; }
        let n = mask(here + vec2<i32>(dx, dy), resI);
        if (n.r > 0.5) {
          hueSum += n.b;
          hueCount += 1.0;
          tint = max(tint, n.a);
        }
      }
    }

    if (hueCount > 0.0 && rand01(&seed) < stickiness) {
      let hue = fract(hueSum / hueCount + (rand01(&seed) - 0.5) * 0.02);
      textureStore(dataTextureA, here, vec4<f32>(1.0, 0.0, hue, tint));
      simState[i] = vec4<f32>(pos, 0.0, w.w);
      return;
    }
  }

  // Dust: a same-frame freeze by another walker at this texel may lose the race;
  // that walker simply respawns, so the crystal never gains a false pixel.
  let here = vec2<i32>(pos);
  if (mask(here, resI).r < 0.5) {
    textureStore(dataTextureA, here, vec4<f32>(0.0, 0.0, 0.0, 1.0));
  }
  simState[i] = vec4<f32>(pos, w.z + 1.0, w.w);
}
