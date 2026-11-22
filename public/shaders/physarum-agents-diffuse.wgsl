// ═══════════════════════════════════════════════════════════════════
//  Physarum Agents — Diffuse
//  Category: simulation
//  Features: temporal-persistence
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: sheath anisotropy; fresh-front sparing
//  A packing: raw trail (.r amount, .g last deposit time). No display write
// ═══════════════════════════════════════════════════════════════════
//  First node of the physarum-agents graph (Jones 2010 Lagrangian physarum on the sim ring).
//  Reads last frame's trail field (dataC), writes the diffused field to dataA.
//  The planner copies dataA → dataC before the agent step, so the agents sense this field and
//  deposit on top of it. CPU spec: scripts/sim_models/physarum_agents.py (`diffuse`).
//  zoom_params: .w persistence → keep = mix(0.80, 0.985)
//  Pheromone bloom: a click drops a fading bump of trail that the network reroutes toward.

#include "_prelude.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(2) var<uniform> simParams: SimParams;

const TRAIL_CAP: f32 = 8.0;
const BLOOM_LIFE: f32 = 0.6;   // seconds a click keeps feeding its bloom

fn wrapTexel(p: vec2<i32>, ri: vec2<i32>) -> vec2<i32> {
  return ((p % ri) + ri) % ri;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let p = vec2<i32>(gid.xy);

  // Ring (re)armed: drop whatever field the previous shader left behind.
  if (simParams.frame == 0u) {
    textureStore(dataTextureA, p, vec4<f32>(0.0));
    return;
  }

  var sum = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      sum = sum + textureLoad(dataTextureC, wrapTexel(p + vec2<i32>(dx, dy), ri), 0).r;
    }
  }
  let east = textureLoad(dataTextureC, wrapTexel(p + vec2<i32>(1, 0), ri), 0).r;
  let west = textureLoad(dataTextureC, wrapTexel(p + vec2<i32>(-1, 0), ri), 0).r;
  let north = textureLoad(dataTextureC, wrapTexel(p + vec2<i32>(0, 1), ri), 0).r;
  let south = textureLoad(dataTextureC, wrapTexel(p + vec2<i32>(0, -1), ri), 0).r;
  let gx = east - west;
  let gy = north - south;
  let g2 = gx * gx + gy * gy;
  let axis = select(vec2<f32>(1.0, 0.0), vec2<f32>(gx, gy) / sqrt(max(g2, 1e-8)), g2 > 1e-6);
  let alongW = max(abs(axis.x) + abs(axis.y), 1e-4);
  let along = (east * abs(axis.x) + west * abs(axis.x) + north * abs(axis.y) + south * abs(axis.y)) / (2.0 * alongW);
  // ── Idea 1: sheath anisotropy — blur along the trail, less across the tube
  let blurred = mix(sum / 9.0, along, 0.45);
  let here = textureLoad(dataTextureC, p, 0);
  let time = u.config.x;
  let age = max(time - here.g, 0.0);
  let fresh = exp(-age * 3.0);
  let keep = mix(0.80, 0.985, u.zoom_params.w);
  // ── Idea 2: fresh-front sparing — a recent deposit decays less than an abandoned tube
  let keepFront = mix(keep, min(keep + 0.03, 0.992), fresh);
  var trail = blurred * keepFront;

  // Pheromone bloom: each recent click adds a soft bump for BLOOM_LIFE seconds.
  let res = vec2<f32>(ri);
  let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let bloomAge = time - rp.z;
    if (bloomAge >= 0.0 && bloomAge < BLOOM_LIFE) {
      let d = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
      trail = trail + 0.25 * exp(-dot(d, d) / (0.035 * 0.035)) * (1.0 - bloomAge / BLOOM_LIFE);
    }
  }

  textureStore(dataTextureA, p, vec4<f32>(min(trail, TRAIL_CAP), here.g, 0.0, 0.0));
}
