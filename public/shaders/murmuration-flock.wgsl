// ═══ MURMURATION — FLOCK (sim ring + spatial hash, simState dispatch) ═════
//  One invocation per bird. Birds live in the @group(1) sim ring
//  (src/contracts/bind_group1.json) and find their neighbours through the
//  spatial hash (binding 3, _sim_hash.wgsl) instead of scanning the buffer:
//  five-by-five cells, at most MAX_VISITS birds per cell.
//  simState[i]: .xy position (px, torus), .zw velocity (px / frame)
//  zoom_params: .x cohesion (bass tightens it), .y alignment (mids),
//               .z perception radius, .w trail length (read by the render pass)
//  Mouse is the predator: birds peel away from it, a held click is a stoop.
//  Each bird paints a small heading-tinted patch into dataA: .a is how crowded the bird is (neighbour
//  count against what a uniform scatter would see), so clumps read dense and voids stay empty. The patch
//  grows with sparseness so coverage stays complete at any resolution. The render pass blurs, fades and
//  composites that field.

#include "_prelude.wgsl"
#include "_sim_hash.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;
@group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>;

const TAU: f32 = 6.28318530718;
const MAX_VISITS: u32 = 8u;
const WINDOW: i32 = 2;

fn pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

fn rnd(seed: ptr<function, u32>) -> f32 {
  *seed = pcg(*seed);
  return f32(*seed) / 4294967295.0;
}

fn loadBird(j: u32) -> vec4<f32> {
  let b = j * 4u;
  return bitcast<vec4<f32>>(vec4<u32>(simIndex[b], simIndex[b + 1u], simIndex[b + 2u], simIndex[b + 3u]));
}

/// Shortest vector on the torus.
fn minImage(d: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  return d - res * round(d / res);
}

/// Heading of the slow wind at a normalised position: the whole flock undulates along it.
fn windAngle(q: vec2<f32>, time: f32) -> f32 {
  return (sin(q.x * 6.0 + time * 0.17) + cos(q.y * 5.0 - time * 0.13) + sin((q.x + q.y) * 3.5 + time * 0.07)) * 1.7;
}

fn hsv(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
  return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= simParams.stateCount) { return; }
  let res = u.config.zw;
  if (res.x < 8.0 || res.y < 8.0) { return; }

  let s = res.y / 1080.0;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let cohesion = mix(0.004, 0.034, u.zoom_params.x) * (1.0 + bass * 1.4);
  let alignment = mix(0.03, 0.28, u.zoom_params.y) * (1.0 + mids * 0.5);
  let cellPx = hashCellSize(res);
  // Five cells reach 2 * min(cell) on both axes, so the radius must stay under that.
  let radius = mix(1.0, 2.0, u.zoom_params.z) * min(cellPx.x, cellPx.y);
  let r2 = radius * radius;
  let sepR2 = r2 * 0.2;

  var seed = pcg(i ^ pcg(simParams.frame + 0x9e3779b9u));
  let st = simState[i];
  var pos = st.xy;
  var vel = st.zw;

  let valid = all(pos >= vec2<f32>(0.0)) && all(pos < res) && all(abs(vel) < vec2<f32>(64.0));
  if (simParams.frame == 0u || !valid) {
    // Seeded already streaming with the wind, so the first frames are coherent ribbons, not static.
    let p0 = vec2<f32>(rnd(&seed), rnd(&seed)) * res;
    let ang = windAngle(p0 / res, time) + (rnd(&seed) - 0.5) * 0.7;
    simState[i] = vec4<f32>(p0, vec2<f32>(cos(ang), sin(ang)) * (1.6 + rnd(&seed)) * s);
    return;
  }

  // Separation / alignment / cohesion over the hashed neighbourhood.
  let cell = hashCell(pos, res);
  var sep = vec2<f32>(0.0);
  var ali = vec2<f32>(0.0);
  var coh = vec2<f32>(0.0);
  var count = 0.0;
  for (var dy = -WINDOW; dy <= WINDOW; dy = dy + 1) {
    for (var dx = -WINDOW; dx <= WINDOW; dx = dx + 1) {
      let c = hashWrap(cell + vec2<i32>(dx, dy));
      var j = atomicLoad(&simHash[hashCellId(c)]);
      for (var k = 0u; k < MAX_VISITS && j != HASH_EMPTY; k = k + 1u) {
        if (j != i) {
          let q = loadBird(j);
          let d = minImage(q.xy - pos, res);
          let d2 = dot(d, d);
          if (d2 < r2 && d2 > 1e-4) {
            count = count + 1.0;
            ali = ali + q.zw;
            coh = coh + d;
            if (d2 < sepR2) { sep = sep - d / d2; }
          }
        }
        j = atomicLoad(&simHash[HASH_NEXT + j]);
      }
    }
  }

  var acc = vec2<f32>(0.0);
  if (count > 0.0) {
    let inv = 1.0 / count;
    acc = acc + (ali * inv - vel) * alignment;
    acc = acc + coh * inv * cohesion;
    acc = acc + sep * 2.6 * s;
  }

  // A slow wind keeps the whole flock undulating instead of settling.
  let wind = windAngle(pos / res, time);
  acc = acc + vec2<f32>(cos(wind), sin(wind)) * 0.05 * s;

  // Predator.
  let mouseUv = u.zoom_config.yz;
  let mouseIn = all(mouseUv >= vec2<f32>(0.0)) && all(mouseUv <= vec2<f32>(1.0));
  let down = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var panic = 0.0;
  if (mouseIn) {
    let dm = minImage(pos - mouseUv * res, res);
    let rp = res.y * (0.11 + 0.10 * down);
    let dist = length(dm);
    if (dist < rp) {
      let f = 1.0 - dist / rp;
      acc = acc + dm / max(dist, 1.0) * f * f * (1.1 + 2.6 * down) * s;
      panic = f;
    }
  }

  acc = acc + (vec2<f32>(rnd(&seed), rnd(&seed)) - vec2<f32>(0.5)) * 0.02 * s;
  vel = vel + acc;
  let spd = length(vel);
  let vmax = (3.4 + treble * 0.8) * s * (1.0 + 0.9 * panic);
  let vmin = 1.3 * s;
  vel = select(vec2<f32>(vmin, 0.0), vel / spd * clamp(spd, vmin, vmax), spd > 1e-5);

  pos = pos + vel;
  pos = pos - res * floor(pos / res);
  simState[i] = vec4<f32>(pos, vel);

  // Patch: .a is this bird's crowding against the count a uniform scatter would see (the hash caps each
  // cell at MAX_VISITS, so the ratio saturates near 2). .rgb is the heading hue, brighter for fast or
  // panicked birds; the render pass uses it for the ink tint and the rim light.
  let expected = f32(simParams.stateCount) / (res.x * res.y) * 3.14159265 * r2;
  let crowd = clamp((count / max(expected, 1.0) - 0.7) / 1.3, 0.0, 1.0);
  let heading = atan2(vel.y, vel.x) / TAU + 0.5;
  let hue = fract(heading + crowd * 0.22 + time * 0.02 + panic * 0.15);
  let bright = (0.75 + 0.5 * clamp(length(vel) / vmax, 0.0, 1.0)) + treble * 0.4 + panic * 1.0;
  let ip = vec2<i32>(floor(pos));
  let hi = vec2<i32>(res) - vec2<i32>(1);
  // Patch radius: half the spacing of a uniform scatter, so neighbouring birds' patches just meet.
  let reach = i32(clamp(ceil(0.5 * sqrt(res.x * res.y / f32(simParams.stateCount))), 1.0, 3.0));
  let swatch = vec4<f32>(hsv(hue, 0.9 - 0.25 * crowd, 1.0) * bright, crowd);
  for (var oy = -reach; oy <= reach; oy = oy + 1) {
    for (var ox = -reach; ox <= reach; ox = ox + 1) {
      // Concurrent birds on a texel race and keep the last write: fine for a density field.
      textureStore(dataTextureA, clamp(ip + vec2<i32>(ox, oy), vec2<i32>(0), hi), swatch);
    }
  }
}
