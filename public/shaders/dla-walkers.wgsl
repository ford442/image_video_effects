// ═══ DLA CRYSTALS — WALKERS (sim ring, simState dispatch) ═════════════════
//  One invocation per walker. Walkers live in the @group(1) sim ring
//  (src/contracts/bind_group1.json), not in extraBuffer.
//  simState[i]: .xy position (pixels), .z hue seed, .w alive flag
//  A/C packing: .r frozen, .g freeze time (frozen) / last visit time (free),
//               .b hue, .a branch id
//  zoom_params: .x walker speed, .y attract, .z stickiness, .w branch angle

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
  for (var s = 0u; s < steps; s = s + 1u) {
    let ang = rand(&seed) * TAU;
    let toTarget = goal - pos;
    let pull = select(vec2<f32>(0.0), normalize(toTarget), dot(toTarget, toTarget) > 1.0);
    let dir = normalize(vec2<f32>(cos(ang), sin(ang)) + pull * attractStrength * 1.5 + vec2<f32>(1e-4));
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

    if (hueCount > 0.0 && rand(&seed) < stickiness) {
      // Freeze: this walker becomes crystal, then respawns elsewhere.
      let hue = fract(hueSum / hueCount + (rand(&seed) - 0.5) * 0.06 + treble * 0.05 + attractStrength * 0.08);
      textureStore(dataTextureA, p, vec4<f32>(1.0, time, hue, branchAngle * rand(&seed)));
      simState[i] = spawn(&seed, res);
      return;
    }
  }

  // Trail stamp: free pixel remembers when a walker last passed (render fades it).
  let here = vec2<i32>(pos);
  if (load(here, resI).r < 0.5) {
    textureStore(dataTextureA, here, vec4<f32>(0.0, time, w.z, 0.0));
  }
  simState[i] = vec4<f32>(pos, w.z, 1.0);
}
