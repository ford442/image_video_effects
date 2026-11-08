// ═══ SPH FLUID — DENSITY (sim ring + spatial hash, simState dispatch) ═════
//  Pass 1 of 3 of a weakly compressible SPH fluid (WCSPH, Becker & Teschner 2007). One invocation per
//  particle; CPU spec: scripts/sim_models/sph_fluid.py (`step`, density pass), constants mirrored there.
//
//  Stride-2 records (simRing.packing): particle p owns two simState elements
//      simState[2p]     = (pos.xy px, vel.xy px / frame)            hashed: a live agent
//      simState[2p + 1] = (-1, -1, density, vorticity)               parked: never hashed
//  The (-1, -1) sentinel is the hash's existing alive rule (xy outside [0, resolution)), so a hash
//  neighbour j is always an even element and its aux record is j + 1. This pass writes only aux
//  records, so no hashed position moves and the node is `keepsHash`: the planner reuses this hash for
//  the force pass instead of rebuilding it (4 counted passes: scatter, density, force, render).
//
//  rho_i   = sum_j W(r_ij)          W = 4/pi (1 - r^2)^3, kernel radius h = 0.98 * min(cell) (one 3x3 walk)
//  omega_i = sum_j V0 grad W_ij x v_ij,   grad W = -30/pi (1 - r)^2 r_hat,   V0 = 1 / rho0
//  Frame 0 seeds the droplets (and parks the particles past ACTIVE_MAX); see seedParticle.
//  zoom_params: .x viscosity (force pass), .y rest density, .z pointer force, .w obstacle strength

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

const PI: f32 = 3.14159265359;
const POLY6: f32 = 1.27323954474;      // 4 / pi
const SPIKY: f32 = -9.54929658551;     // -30 / pi
const VISIT_CAP: u32 = 16u;            // bind_group1.json spatialHash.visitCap[1]
const RHO_LO: f32 = 3.4;
const RHO_HI: f32 = 6.2;
const OCC_MAX: f32 = 8.0;              // rest particles per hash cell, at most
const ACTIVE_MAX: u32 = 24576u;        // COVERAGE 0.3 * OCC_SEED 5 * 16384 cells; the rest stay parked
const GOLDEN: f32 = 2.39996322972865332;

fn loadEl(j: u32) -> vec4<f32> {
  let b = j * 4u;
  return bitcast<vec4<f32>>(vec4<u32>(simIndex[b], simIndex[b + 1u], simIndex[b + 2u], simIndex[b + 3u]));
}

fn kernelH(res: vec2<f32>) -> f32 {
  let c = hashCellSize(res);
  return 0.98 * min(c.x, c.y);
}

/// Rest density (h^-2): the slider's neighbour-count target, capped so a cell holds <= OCC_MAX at rest.
fn restDensity(res: vec2<f32>, h: f32) -> f32 {
  let c = hashCellSize(res);
  return min(mix(RHO_LO, RHO_HI, u.zoom_params.y), OCC_MAX * h * h / (c.x * c.y));
}

fn activeCount() -> u32 {
  return min(simParams.stateCount / 2u, ACTIVE_MAX);
}

fn alive(p: vec2<f32>, res: vec2<f32>) -> bool {
  return p.x >= 0.0 && p.y >= 0.0 && p.x < res.x && p.y < res.y;
}

/// Frame-0 seed, mirroring sph_fluid.py seed_droplets: 3 x 1 droplets when wide, 1 x 3 when tall,
/// else 2 x 2; each a Vogel sunflower at the rest number density (rho_sum / n = 1.003 for it).
fn seedParticle(p: u32, res: vec2<f32>, h: f32, rho0: f32) -> vec2<f32> {
  let aspect = res.x / res.y;
  var cols = 2u;
  var rows = 2u;
  if (aspect >= 1.3) {
    cols = 3u;
    rows = 1u;
  } else if (aspect <= 0.77) {
    cols = 1u;
    rows = 3u;
  }
  let k = cols * rows;
  let n = activeCount();
  let m = (n + k - 1u) / k;
  let q = p / m;
  let idx = p % m;
  let centre = vec2<f32>((f32(q % cols) + 0.5) / f32(cols), (f32(q / cols) + 0.5) / f32(rows)) * res;
  let radius = sqrt(f32(m) / (PI * rho0 / (h * h)));
  let kk = f32(idx) + 0.5;
  let rr = radius * sqrt(kk / f32(m));
  let th = kk * GOLDEN + f32(q);
  return centre + rr * vec2<f32>(cos(th), sin(th));
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let p = gid.x;
  if (p >= simParams.stateCount / 2u) { return; }
  let res = u.config.zw;
  if (res.x < 16.0 || res.y < 16.0) { return; }
  let e = p * 2u;
  let h = kernelH(res);
  let rho0 = restDensity(res, h);
  let parked = vec4<f32>(-1.0, -1.0, 0.0, 0.0);

  if (simParams.frame == 0u) {
    if (p >= activeCount()) {
      simState[e] = parked;
    } else {
      simState[e] = vec4<f32>(clamp(seedParticle(p, res, h, rho0), vec2<f32>(0.5), res - vec2<f32>(0.5)), 0.0, 0.0);
    }
    simState[e + 1u] = vec4<f32>(-1.0, -1.0, rho0, 0.0);
    return;
  }
  if (p >= activeCount()) { return; }

  let me = loadEl(e);
  if (!alive(me.xy, res)) {
    // Not hashed this frame (resized away, or invalid): neutral aux; the force pass brings it back.
    simState[e + 1u] = vec4<f32>(-1.0, -1.0, rho0, 0.0);
    return;
  }

  let invH = 1.0 / h;
  let v0 = 1.0 / rho0;
  let vi = me.zw * invH;
  var rho = POLY6;
  var omega = 0.0;
  let cell = hashCell(me.xy, res);
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let c = cell + vec2<i32>(dx, dy);
      if (c.x < 0 || c.y < 0 || c.x >= i32(HASH_GRID) || c.y >= i32(HASH_GRID)) { continue; }
      var j = atomicLoad(&simHash[hashCellId(c)]);
      for (var k = 0u; k < VISIT_CAP && j != HASH_EMPTY; k = k + 1u) {
        if (j != e) {
          let q = loadEl(j);
          let d = (me.xy - q.xy) * invH;
          let r2 = dot(d, d);
          if (r2 < 1.0) {
            let s = 1.0 - r2;
            rho = rho + POLY6 * s * s * s;
            let r = sqrt(r2);
            if (r > 1e-5) {
              let g = SPIKY * (1.0 - r) * (1.0 - r) * d / r;
              let vij = q.zw * invH - vi;
              omega = omega + v0 * (g.x * vij.y - g.y * vij.x);
            }
          }
        }
        j = atomicLoad(&simHash[HASH_NEXT + j]);
      }
    }
  }
  simState[e + 1u] = vec4<f32>(-1.0, -1.0, rho, omega);
}
