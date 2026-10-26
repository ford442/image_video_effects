// ═══════════════════════════════════════════════════════════════════
//  _sim_hash.wgsl — helpers for the sim ring's spatial hash
//
//  Contract: src/contracts/bind_group1.json `spatialHash` (verify:device-policy
//  keeps the constants below equal to it). Hand-written, not generated.
//
//  Use it with:
//      #include "_prelude.wgsl"
//      #include "_sim_hash.wgsl"
//      @group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
//      @group(1) @binding(1) var<storage, read> simIndex: array<u32>;
//      @group(1) @binding(2) var<uniform> simParams: SimParams;
//      @group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>;
//
//  simHash is one buffer: HASH_CELLS cell heads, then one `next` link per agent
//  (index HASH_NEXT + i). The frame planner rebuilds it before the first graph
//  node that reads the `simHash` role. An agent is hashed iff its simState.xy is
//  inside [0, resolution); park dead agents at xy < 0.
//
//  Walk a cell's agents with a HARD visit cap, never `while (i != HASH_EMPTY)`:
//
//      var j = atomicLoad(&simHash[hashCellId(cell)]);
//      for (var k = 0u; k < 8u && j != HASH_EMPTY; k = k + 1u) {
//        let q = bitcast<vec4<f32>>(vec4<u32>(
//          simIndex[j * 4u], simIndex[j * 4u + 1u], simIndex[j * 4u + 2u], simIndex[j * 4u + 3u]));
//        // ... use q ...
//        j = atomicLoad(&simHash[HASH_NEXT + j]);
//      }
// ═══════════════════════════════════════════════════════════════════

const HASH_GRID: u32 = 128u;       // cells per row and column over the working-size domain
const HASH_CELLS: u32 = 16384u;    // HASH_GRID * HASH_GRID
const HASH_NEXT: u32 = 16384u;     // u32 index of agent 0's `next` link
const HASH_EMPTY: u32 = 0xFFFFFFFFu;

/// Cell column / row of a pixel-space position (clamped into the grid).
fn hashCell(p: vec2<f32>, res: vec2<f32>) -> vec2<i32> {
  let g = f32(HASH_GRID);
  return vec2<i32>(clamp(floor(p / res * g), vec2<f32>(0.0), vec2<f32>(g - 1.0)));
}

/// Head slot of a cell. `c` must be inside the grid (see hashWrap).
fn hashCellId(c: vec2<i32>) -> u32 {
  return u32(c.y) * HASH_GRID + u32(c.x);
}

/// Wrap a cell coordinate around the grid (for toroidal domains).
fn hashWrap(c: vec2<i32>) -> vec2<i32> {
  let g = i32(HASH_GRID);
  return vec2<i32>(((c.x % g) + g) % g, ((c.y % g) + g) % g);
}

/// Cell size in pixels.
fn hashCellSize(res: vec2<f32>) -> vec2<f32> {
  return res / f32(HASH_GRID);
}
