// ═══ PHYSARUM AGENTS — STEP (sim ring, simState dispatch) ═════════════════
//  One invocation per agent (Jones 2010). Agents live in the @group(1) sim ring
//  (src/contracts/bind_group1.json); there is no neighbour search, so no spatial hash.
//  simState[i]: .xy position (px, torus), .z heading (rad), .w alive flag
//  Per step, mirroring scripts/sim_models/physarum_agents.py:
//    sense   F, L, R = trail + FOOD_W * food at pos + SO * dir(h), dir(h ± SA)   (nearest texel)
//    steer   F > L and F > R: keep;  F < L and F < R: ±RA at random;  else toward the larger side
//    move    pos += SS * dir(h), wrapped onto the torus
//    deposit dataA(texel) = dataC(texel) + dep
//  Food is the source image's red channel; a held pointer is an extra attractant.
//  zoom_params: .x sense angle, .y sense distance, .z move speed, .w persistence (deposit / decay)
//
//  The deposit race: storage textures have no atomics and WGSL has no f32 atomics, so agents on the
//  same texel race and the last writer wins. Every agent on a texel writes the same value
//  (dataC(texel) + dep, the frame time), so the race has exactly one outcome: at most one deposit per
//  texel per frame, deterministically. The numpy model de-duplicates texels to match. (DLA and
//  Murmuration write per-agent values and accept a nondeterministic winner; here the trail must not
//  depend on scheduling, because it steers the next frame.)

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
const FOOD_W: f32 = 0.6;        // food (image red) weight in the sensor sum
const WANDER: f32 = 0.12;       // rad of random wander per step
const DEP0: f32 = 0.4;          // deposit at the default persistence
const KEEP_DEFAULT: f32 = 0.8925; // mix(0.80, 0.985, 0.5)
const TRAIL_CAP: f32 = 8.0;
const MODEL_DENSITY: f32 = 0.25; // agents per s² in the numpy model (4096 agents on 128²)

fn pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

fn rnd(seed: ptr<function, u32>) -> f32 {
  *seed = pcg(*seed);
  return f32(*seed) / 4294967295.0;
}

/// Wrap onto [0, res). The select catches the float edge where p - res*floor(p/res) rounds to res.
fn wrapPos(p: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  let q = p - res * floor(p / res);
  return select(q, vec2<f32>(0.0), q >= res);
}

fn texelOf(p: vec2<f32>, ri: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(floor(p)), vec2<i32>(0), ri - vec2<i32>(1));
}

struct Lure {
  on: bool,
  pos: vec2<f32>,
  invR2: f32,
};

/// What a sensor at `pos + dist * dir(ang)` smells: trail, food, and the held pointer.
fn sense(pos: vec2<f32>, ang: f32, dist: f32, res: vec2<f32>, ri: vec2<i32>, lure: Lure) -> f32 {
  let q = wrapPos(pos + vec2<f32>(cos(ang), sin(ang)) * dist, res);
  let t = texelOf(q, ri);
  var v = textureLoad(dataTextureC, t, 0).r + FOOD_W * textureLoad(readTexture, t, 0).r;
  if (lure.on) {
    let d = q - lure.pos;
    v = v + 1.5 * exp(-dot(d, d) * lure.invR2);
  }
  return v;
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= simParams.stateCount) { return; }
  let res = u.config.zw;
  if (res.x < 8.0 || res.y < 8.0) { return; }
  let ri = vec2<i32>(res);

  var seed = pcg(i ^ pcg(simParams.frame + 0x9e3779b9u));
  let a = simState[i];
  let valid = all(a.xy >= vec2<f32>(0.0)) && all(a.xy < res) && a.z == a.z && abs(a.z) < 1e4;
  if (simParams.frame == 0u || !valid) {
    simState[i] = vec4<f32>(vec2<f32>(rnd(&seed), rnd(&seed)) * res, rnd(&seed) * TAU, 1.0);
    return;
  }

  // Scale that keeps agents per s² equal to the model's, so the mesh looks the same at any working
  // size and on any OOM-ladder rung.
  let s = clamp(sqrt(MODEL_DENSITY * res.x * res.y / f32(simParams.stateCount)), 1.0, 3.0);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let sa = mix(0.25, 1.00, u.zoom_params.x);
  let ra = 1.5 * sa;
  let so = mix(3.0, 18.0, u.zoom_params.y) * s;
  let ss = mix(0.5, 2.5, u.zoom_params.z) * s * (1.0 + 0.4 * bass);
  let keep = mix(0.80, 0.985, u.zoom_params.w);
  let dep = DEP0 * (1.0 - keep) / (1.0 - KEEP_DEFAULT) * (1.0 + 1.5 * bass);

  let mouse = u.zoom_config.yz;
  let inCanvas = all(mouse >= vec2<f32>(0.0)) && all(mouse <= vec2<f32>(1.0));
  let lureR = 0.09 * res.y;
  let lure = Lure(inCanvas && u.zoom_config.w > 0.5, mouse * res, 1.0 / (lureR * lureR));

  let f = sense(a.xy, a.z, so, res, ri, lure);
  let l = sense(a.xy, a.z + sa, so, res, ri, lure);
  let r = sense(a.xy, a.z - sa, so, res, ri, lure);
  let coin = select(-1.0, 1.0, rnd(&seed) < 0.5);
  var turn = 0.0;
  if (f > l && f > r) {
    turn = 0.0;
  } else if (f < l && f < r) {
    turn = coin * ra;
  } else if (l > r) {
    turn = ra;
  } else {
    turn = -ra;
  }
  var h = a.z + turn + WANDER * (rnd(&seed) - 0.5);
  h = h - TAU * floor(h / TAU);
  let pos = wrapPos(a.xy + vec2<f32>(cos(h), sin(h)) * ss, res);
  simState[i] = vec4<f32>(pos, h, 1.0);

  // Deposit: every agent on this texel writes this exact value (see the header).
  let t = texelOf(pos, ri);
  let c = textureLoad(dataTextureC, t, 0);
  textureStore(dataTextureA, t, vec4<f32>(min(c.r + dep, TRAIL_CAP), u.config.x, 0.0, 0.0));
}
