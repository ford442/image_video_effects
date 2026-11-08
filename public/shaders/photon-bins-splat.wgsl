// ═══ PHOTON BINS — SPLAT (spatial hash gather, pixels) ════════════════════
//  Each pixel gathers the photons binned around it: its own cell plus the
//  three neighbours on the near side, at most MAX_VISITS photons per cell,
//  within a splat radius of half a cell. Colour comes from the wavelength bin,
//  weight from the photon's energy. Rays that converge pile up into caustics.
//  The accumulator is carried in dataA: .rgb spectral energy, .a photon count.
//  zoom_params: .w persistence

#include "_prelude.wgsl"
#include "_sim_hash.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;
@group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>;

const TAU: f32 = 6.28318530718;
const MAX_VISITS: u32 = 16u;
const GAIN: f32 = 0.14;

fn loadPhoton(j: u32) -> vec4<f32> {
  let b = j * 4u;
  return bitcast<vec4<f32>>(vec4<u32>(simIndex[b], simIndex[b + 1u], simIndex[b + 2u], simIndex[b + 3u]));
}

/// Rainbow from wavelength bin 0..1 (red → violet), saturated.
fn spectrum(wl: f32) -> vec3<f32> {
  return vec3<f32>(0.55) + vec3<f32>(0.45) * cos(TAU * (vec3<f32>(wl * 0.8) + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let p = vec2<i32>(gid.xy);
  let res = vec2<f32>(ri);
  let pf = vec2<f32>(gid.xy) + vec2<f32>(0.5);

  let cellPx = hashCellSize(res);
  let radius = clamp(0.5 * min(cellPx.x, cellPx.y), 1.5, 5.0);
  let r2 = radius * radius;
  let base = hashCell(pf, res);
  // The pixel can only reach the cells on the side of its own cell it is nearest to.
  let fr = fract(pf / cellPx);
  let sx = select(-1, 1, fr.x > 0.5);
  let sy = select(-1, 1, fr.y > 0.5);

  var acc = vec3<f32>(0.0);
  var cnt = 0.0;
  for (var oy = 0; oy < 2; oy = oy + 1) {
    for (var ox = 0; ox < 2; ox = ox + 1) {
      let c = base + vec2<i32>(ox * sx, oy * sy);
      if (c.x < 0 || c.y < 0 || c.x >= i32(HASH_GRID) || c.y >= i32(HASH_GRID)) { continue; }
      var j = atomicLoad(&simHash[hashCellId(c)]);
      for (var k = 0u; k < MAX_VISITS && j != HASH_EMPTY; k = k + 1u) {
        let q = loadPhoton(j);
        let d = q.xy - pf;
        let d2 = dot(d, d);
        if (d2 < r2) {
          let bin = floor(q.w);
          let energy = q.w - bin;
          let kern = (1.0 - d2 / r2) * (1.0 - d2 / r2);
          acc = acc + spectrum(bin / 64.0) * (energy * kern);
          cnt = cnt + energy * kern;
        }
        j = atomicLoad(&simHash[HASH_NEXT + j]);
      }
    }
  }

  let prev = textureLoad(dataTextureC, p, 0);
  let keep = mix(0.78, 0.96, u.zoom_params.w);
  let fresh = select(vec4<f32>(0.0), vec4<f32>(acc, cnt) * GAIN, simParams.frame > 0u);
  textureStore(dataTextureA, p, min(prev * keep + fresh, vec4<f32>(8.0)));
}
