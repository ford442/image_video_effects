// ═══ PHOTON BINS — MARCH (sim ring, simState dispatch) ════════════════════
//  One invocation per photon. Photons live in the @group(1) sim ring.
//  simState[i]: .xy position (px), .z heading (rad),
//               .w = wavelength bin (integer part, 0..63) + energy (fraction)
//  The source image is the height field. Light bends toward bright (high
//  index) ground, bends more at short wavelengths (dispersion), and bounces
//  off any wall steep enough to climb (a luma jump over one step).
//  zoom_params: .x index contrast (bass kicks it), .y dispersion,
//               .z light size, .w persistence (read by the splat pass)
//  Lights: the pointer when it is on the canvas, plus a slow orbiting one.
//  The planner builds the spatial hash from these positions afterwards.

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
const SUBSTEPS: u32 = 3u;

fn pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

fn rnd(seed: ptr<function, u32>) -> f32 {
  *seed = pcg(*seed);
  return f32(*seed) / 4294967295.0;
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn texLuma(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  return luma(textureLoad(readTexture, clamp(p, vec2<i32>(0), hi), 0).rgb);
}

/// Height at a pixel position: centre-weighted cross so single noisy texels do not scatter rays.
fn height(p: vec2<f32>, hi: vec2<i32>) -> f32 {
  let q = vec2<i32>(floor(p));
  return 0.5 * texLuma(q, hi)
    + 0.125 * (texLuma(q + vec2<i32>(1, 0), hi) + texLuma(q - vec2<i32>(1, 0), hi)
             + texLuma(q + vec2<i32>(0, 1), hi) + texLuma(q - vec2<i32>(0, 1), hi));
}

fn spawn(i: u32, seed: ptr<function, u32>, res: vec2<f32>, time: f32, fresh: bool) -> vec4<f32> {
  let orbit = vec2<f32>(0.5 + 0.33 * sin(time * 0.21), 0.5 + 0.27 * sin(time * 0.17 + 1.3)) * res;
  let mouse = u.zoom_config.yz;
  let mouseIn = all(mouse >= vec2<f32>(0.0)) && all(mouse <= vec2<f32>(1.0));
  let lightPos = select(orbit, mouse * res, mouseIn && (i & 1u) == 1u);
  let lightR = mix(2.0, 0.06 * res.y, u.zoom_params.z) * sqrt(rnd(seed));
  let ang = rnd(seed) * TAU;
  let pos = lightPos + vec2<f32>(cos(ang), sin(ang)) * lightR * rnd(seed);
  let heading = rnd(seed) * TAU;
  let bin = floor(rnd(seed) * 63.999);
  // First frame staggers the energies so the whole swarm does not die in one pulse.
  let energy = select(0.6 + 0.4 * rnd(seed), 0.1 + 0.89 * rnd(seed), fresh);
  return vec4<f32>(pos, heading, bin + min(energy, 0.999));
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= simParams.stateCount) { return; }
  let res = u.config.zw;
  let ri = vec2<i32>(res);
  if (ri.x < 8 || ri.y < 8) { return; }
  let hi = ri - vec2<i32>(1);

  let s = res.y / 1080.0;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

  var seed = pcg(i ^ pcg(simParams.frame + 0x9e3779b9u));
  let st = simState[i];
  var pos = st.xy;
  var heading = st.z;
  let bin = floor(st.w);
  var energy = st.w - bin;
  let wl = bin / 64.0;

  let alive = all(pos >= vec2<f32>(0.0)) && all(pos < res) && energy > 0.03;
  if (simParams.frame == 0u || !alive) {
    simState[i] = spawn(i, &seed, res, time, simParams.frame == 0u);
    return;
  }

  // Index of refraction grows with brightness; blue (wl → 1) bends harder than red.
  let contrast = mix(0.6, 5.0, u.zoom_params.x) * (1.0 + bass * 1.2);
  let dispersion = u.zoom_params.y;
  let bend = contrast * (1.0 + dispersion * (wl * 2.0 - 1.0) * 0.8);
  let wallStep = mix(0.30, 0.10, u.zoom_params.x);
  let ds = 2.2 * s;

  for (var n = 0u; n < SUBSTEPS; n = n + 1u) {
    let dir = vec2<f32>(cos(heading), sin(heading));
    let g = vec2<f32>(
      height(pos + vec2<f32>(3.0, 0.0), hi) - height(pos - vec2<f32>(3.0, 0.0), hi),
      height(pos + vec2<f32>(0.0, 3.0), hi) - height(pos - vec2<f32>(0.0, 3.0), hi),
    ) / 6.0;
    // Ray equation in a graded-index medium: d(dir)/ds = grad(n) - (grad(n) . dir) dir.
    let perp = g - dot(g, dir) * dir;
    let turn = perp * bend * ds * 4.0;
    let turnLen = length(turn);
    var nd = dir + select(turn, turn * (0.5 / turnLen), turnLen > 0.5);
    nd = normalize(nd);

    let next = pos + nd * ds;
    let climb = height(next, hi) - height(pos, hi);
    if (climb > wallStep && length(g) > 1e-5) {
      // Wall: reflect about the local surface normal and lose some energy; stay put this step.
      nd = reflect(nd, normalize(g));
      energy = energy * 0.8;
      heading = atan2(nd.y, nd.x);
    } else {
      pos = next;
      heading = atan2(nd.y, nd.x);
    }
  }
  energy = min(energy * 0.9925, 0.999);

  simState[i] = vec4<f32>(pos, heading, bin + energy);
}
