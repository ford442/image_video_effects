// ═══ SPH FLUID — FORCE + INTEGRATE (sim ring + spatial hash, simState dispatch) ═
//  Pass 2 of 3 (WCSPH). One invocation per particle, reading the density pass's aux records through
//  the simIndex snapshot (the planner re-snapshots after the density write) and the same hash (the
//  density node is keepsHash). CPU spec: scripts/sim_models/sph_fluid.py (`step`, force pass).
//      p   = B ((rho / rho0)^7 - 1), >= 0         Tait, clamped for the free surface; B = rho0 c^2 / 7
//      a   = -sum_j (p_i/rho_i^2 + p_j/rho_j^2) grad W_ij                pressure (symmetric)
//          + nu sum_j v_ij / rho_j lap W_ij                               viscosity, lap W = 40/pi (1 - r)
//          - gamma sum_j 2 rho0 / (rho_i + rho_j) C(r) r_hat              cohesion (Akinci 2013 spline)
//          + eps_v N x omega, N = grad|omega| / |grad|omega||             vorticity confinement
//          + walls + drive                                                drive: GPU only, see below
//      v  += a + eps_x sum_j 2 / (rho_i + rho_j) v_ij W_ij               XSPH;  |v| <= VMAX;  x += v
//  One explicit step per frame in kernel units (h = 1, dt = 1): no dt uniform, frame-rate dependent
//  but unconditionally bounded (VMAX, the EOS clamp).
//  Drive (zoom_params): .z pointer force (bass lane): held pointer parts the fluid, a click splashes;
//  .w obstacle strength: bright image regions (luma) push fluid out and drag it; a slow orbiting tide
//  gathers droplets; a bass kick (plasmaBuffer[0].x) bursts them outward from the tide.
//  Each particle also stamps a small patch into dataA for the render pass (last writer wins on shared
//  texels: neighbouring particles carry near-equal values, and the render blurs the field anyway).
//  dataA stamp: .r speed / VMAX, .g vorticity tint (0.5 = still), .b rho / rho0, .a coverage 1

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

const POLY6: f32 = 1.27323954474;      // 4 / pi
const SPIKY: f32 = -9.54929658551;     // -30 / pi
const VISC_LAP: f32 = 12.7323954474;   // 40 / pi
const COH: f32 = 10.1859163579;        // 32 / pi
const VISIT_CAP: u32 = 16u;
const C_SOUND: f32 = 0.6;              // h / frame
const VMAX: f32 = 0.5;                 // h / frame
const GAMMA: f32 = 0.01;
const EPS_V: f32 = 0.002;
const RHO_CLAMP: f32 = 1.4;
const RHO_LO: f32 = 3.4;
const RHO_HI: f32 = 6.2;
const OCC_MAX: f32 = 8.0;
const ACTIVE_MAX: u32 = 24576u;
const WALL_K: f32 = 0.2;
const WALL_R: f32 = 1.5;
const WALL_BOUNCE: f32 = 0.3;
const OBST_PUSH: f32 = 0.25;
const OBST_DRAG: f32 = 0.1;
const OBST_PROBE: f32 = 2.0;
const TIDE_K: f32 = 4e-6;              // frame^-2: a slow spring toward the orbiting tide centre
const KICK: f32 = 0.05;                // h / frame^2 per unit of bass above 0.55

fn loadEl(j: u32) -> vec4<f32> {
  let b = j * 4u;
  return bitcast<vec4<f32>>(vec4<u32>(simIndex[b], simIndex[b + 1u], simIndex[b + 2u], simIndex[b + 3u]));
}

fn kernelH(res: vec2<f32>) -> f32 {
  let c = hashCellSize(res);
  return 0.98 * min(c.x, c.y);
}

fn restDensity(res: vec2<f32>, h: f32) -> f32 {
  let c = hashCellSize(res);
  return min(mix(RHO_LO, RHO_HI, u.zoom_params.y), OCC_MAX * h * h / (c.x * c.y));
}

/// p / rho^2 for the Tait EOS (gamma 7), clamped at the free surface and against pile-ups.
fn pressureTerm(rho: f32, rho0: f32) -> f32 {
  let x = min(rho / rho0, RHO_CLAMP);
  let x2 = x * x;
  let x7 = x2 * x2 * x2 * x;
  let b = rho0 * C_SOUND * C_SOUND / 7.0;
  return max(b * (x7 - 1.0), 0.0) / (rho * rho);
}

/// Akinci cohesion spline on h = 1: repulsive below r = 0.5, attractive out to the kernel edge.
fn cohesion(r: f32) -> f32 {
  let a = (1.0 - r) * (1.0 - r) * (1.0 - r) * r * r * r;
  return COH * select(2.0 * a - 1.0 / 64.0, a, r > 0.5);
}

fn luma(px: vec2<f32>, res: vec2<f32>) -> f32 {
  let t = clamp(vec2<i32>(floor(px)), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
  return dot(textureLoad(readTexture, t, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn obstacle(px: vec2<f32>, res: vec2<f32>, strength: f32) -> f32 {
  return strength * smoothstep(0.55, 0.85, luma(px, res));
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let p = gid.x;
  if (p >= min(simParams.stateCount / 2u, ACTIVE_MAX)) { return; }
  // Frame 0: the density pass seeded positions after this frame's scatter, so the hash is stale.
  if (simParams.frame == 0u) { return; }
  let res = u.config.zw;
  if (res.x < 16.0 || res.y < 16.0) { return; }
  let e = p * 2u;
  let me = loadEl(e);
  let finite = me.x == me.x && me.y == me.y && me.z == me.z && me.w == me.w;
  if (!finite || !(me.x >= 0.0 && me.y >= 0.0 && me.x < res.x && me.y < res.y)) {
    // Resized away or invalid: bring it back inside, at rest. It rejoins the hash next frame.
    let back = select(res * 0.5, me.xy, finite);
    simState[e] = vec4<f32>(clamp(back, vec2<f32>(0.5), res - vec2<f32>(0.5)), 0.0, 0.0);
    return;
  }

  let h = kernelH(res);
  let invH = 1.0 / h;
  let rho0 = restDensity(res, h);
  let nu = mix(0.002, 0.03, u.zoom_params.x);
  let epsX = mix(0.03, 0.15, u.zoom_params.x);
  let aux = loadEl(e + 1u);
  let rhoI = max(aux.z, 1e-3);
  let omI = aux.w;
  let prI = pressureTerm(rhoI, rho0);
  let vi = me.zw * invH;

  var aP = vec2<f32>(0.0);
  var aV = vec2<f32>(0.0);
  var aC = vec2<f32>(0.0);
  var eta = vec2<f32>(0.0);
  var xs = vec2<f32>(0.0);
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
            let qa = loadEl(j + 1u);
            let rhoJ = max(qa.z, 1e-3);
            let r = sqrt(max(r2, 1e-12));
            let rhat = d / r;
            let s = 1.0 - r2;
            let w = POLY6 * s * s * s;
            let g = select(vec2<f32>(0.0), SPIKY * (1.0 - r) * (1.0 - r) * rhat, r > 1e-5);
            let vij = q.zw * invH - vi;
            aP = aP - (prI + pressureTerm(rhoJ, rho0)) * g;
            aV = aV + vij * (VISC_LAP * (1.0 - r) / rhoJ);
            aC = aC - (2.0 * rho0 / (rhoI + rhoJ)) * cohesion(r) * rhat;
            eta = eta + ((abs(qa.w) - abs(omI)) / rhoJ) * g;
            xs = xs + vij * (2.0 / (rhoI + rhoJ) * w);
          }
        }
        j = atomicLoad(&simHash[HASH_NEXT + j]);
      }
    }
  }

  // Vorticity confinement: push along N x omega, N toward stronger swirl.
  let en = length(eta);
  let nrm = select(vec2<f32>(0.0), eta / max(en, 1e-6), en > 1e-6);
  let aW = EPS_V * vec2<f32>(nrm.y * omI, -nrm.x * omI);

  // Walls: a penalty inside WALL_R h of each edge.
  let ph = me.xy * invH;
  let resh = res * invH;
  let lo = max(vec2<f32>(1.0) - ph / WALL_R, vec2<f32>(0.0));
  let hi = max(vec2<f32>(1.0) - (resh - ph) / WALL_R, vec2<f32>(0.0));
  let aWall = WALL_K * (lo * lo - hi * hi);

  var a = aP + nu * aV + GAMMA * aC + aW + aWall;

  // ── drive (GPU only; the numpy model runs the solver without it, plus an obstacle case) ──
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let tide = res * 0.5 + 0.15 * min(res.x, res.y) * vec2<f32>(cos(time * 0.05), sin(time * 0.07));
  let toTide = (me.xy - tide) * invH;
  a = a - TIDE_K * toTide;
  let dT = length(toTide);
  let kick = max(bass - 0.55, 0.0) * KICK * exp(-dT * h / (0.25 * res.y));
  a = a + select(vec2<f32>(0.0), toTide / max(dT, 1e-3) * kick, dT > 1e-3);

  let mouse = u.zoom_config.yz;
  let inCanvas = all(mouse >= vec2<f32>(0.0)) && all(mouse <= vec2<f32>(1.0));
  let force = mix(0.0, 0.08, u.zoom_params.z) * (1.0 + bass);
  if (inCanvas) {
    let rm = 0.12 * res.y;
    let dm = me.xy - mouse * res;
    let dist = length(dm);
    if (dist < rm && dist > 1e-3) {
      let f = (1.0 - dist / rm) * (1.0 - dist / rm);
      a = a + dm / dist * f * force * select(0.3, 1.0, u.zoom_config.w > 0.5);
    }
  }
  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 0.35) {
      let dr = me.xy - rp.xy * res;
      let dist = length(dr);
      let rr = 0.1 * res.y;
      if (dist < rr && dist > 1e-3) {
        let f = (1.0 - dist / rr) * (1.0 - dist / rr);
        a = a + dr / dist * f * 0.1 * (1.0 - age / 0.35) * (0.5 + force * 6.0);
      }
    }
  }

  let strength = u.zoom_params.w;
  if (strength > 0.0) {
    let ep = OBST_PROBE * h;
    let grad = vec2<f32>(
      obstacle(me.xy + vec2<f32>(ep, 0.0), res, strength) - obstacle(me.xy - vec2<f32>(ep, 0.0), res, strength),
      obstacle(me.xy + vec2<f32>(0.0, ep), res, strength) - obstacle(me.xy - vec2<f32>(0.0, ep), res, strength),
    ) / (2.0 * OBST_PROBE);
    a = a - OBST_PUSH * grad - OBST_DRAG * obstacle(me.xy, res, strength) * vi;
  }

  // ── integrate ──
  var v = vi + a + epsX * xs;
  let sp = length(v);
  if (sp > VMAX) { v = v / sp * VMAX; }
  var pos = me.xy + v * h;
  let lo2 = vec2<f32>(0.5);
  let hi2 = res - vec2<f32>(0.5);
  let hitWall = (pos < lo2) | (pos > hi2);
  v = select(v, -WALL_BOUNCE * v, hitWall);
  pos = clamp(pos, lo2, hi2);
  simState[e] = vec4<f32>(pos, v * h);

  // Stamp for the render pass.
  let ri = vec2<i32>(res);
  let ip = vec2<i32>(floor(pos));
  let reach = clamp(i32(floor(0.25 * h)), 1, 2);
  let stamp = vec4<f32>(clamp(length(v) / VMAX, 0.0, 1.0), clamp(0.5 + omI * 2.0, 0.0, 1.0), rhoI / rho0, 1.0);
  for (var oy = -reach; oy <= reach; oy = oy + 1) {
    for (var ox = -reach; ox <= reach; ox = ox + 1) {
      textureStore(dataTextureA, clamp(ip + vec2<i32>(ox, oy), vec2<i32>(0), ri - vec2<i32>(1)), stamp);
    }
  }
}
