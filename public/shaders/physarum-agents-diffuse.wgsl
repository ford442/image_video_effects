// ═══ PHYSARUM AGENTS — DIFFUSE (pixels) ═══════════════════════════════════
//  First node of the physarum-agents graph (Jones 2010 Lagrangian physarum on the sim ring).
//  Reads last frame's trail field (dataC), writes the diffused field to dataA:
//      T = blur3x3(T_prev) * keep        (wrapped: the agents live on a torus)
//  The planner copies dataA → dataC before the agent step, so the agents sense this field and
//  deposit on top of it. CPU spec: scripts/sim_models/physarum_agents.py (`diffuse`).
//  A/C packing: .r trail, .g time of the last deposit on the texel, .ba unused
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
  let keep = mix(0.80, 0.985, u.zoom_params.w);
  var trail = sum / 9.0 * keep;

  // Pheromone bloom: each recent click adds a soft bump for BLOOM_LIFE seconds.
  let res = vec2<f32>(ri);
  let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < BLOOM_LIFE) {
      let d = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
      trail = trail + 0.25 * exp(-dot(d, d) / (0.035 * 0.035)) * (1.0 - age / BLOOM_LIFE);
    }
  }

  let here = textureLoad(dataTextureC, p, 0);
  textureStore(dataTextureA, p, vec4<f32>(min(trail, TRAIL_CAP), here.g, 0.0, 0.0));
}
