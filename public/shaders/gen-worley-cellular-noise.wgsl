// ═══════════════════════════════════════════════════════════════════
//  Worley Cellular Noise
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba, depth-aware, temporal-feedback
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: real membrane aberration (R/B resampled along the F2−F1 wall gradient); bass turgor pulse (swollen bright domes, thinned walls); triple-junction vertices (F3≈F2≈F1 nodes)
//  A packing: (f1 + drift, F2−F1 boundary + drift, wall scatter, alpha) fields; C read back with exact textureLoad, .g feeds the organic drift
// ═══════════════════════════════════════════════════════════════════

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

// Stable per-cell seed: feature points are hashed from the integer cell id only.
const CELL_SEED = vec2<f32>(41.3, 17.9);

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)),
                     dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
             u2.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0u; i < 4u; i = i + 1u) {
    v = v + a * noise2(q);
    q = q * 2.03 + vec2<f32>(3.1, 1.7);
    a = a * 0.5;
  }
  return v;
}

struct CellField {
  f1: f32,
  f2: f32,
  f3: f32,          // third-nearest distance (triple-junction vertices)
  cellId: f32,      // hash of the nearest feature's cell (tissue tint)
  grad: vec2<f32>,  // analytic ∇(F2−F1) (membrane aberration direction)
};

// F1/F2 Worley over the 3×3 neighbourhood (HEAD structure), now also tracking F3,
// the winning cell id and the analytic gradient of the wall field F2−F1.
fn worleyField(p: vec2<f32>, time: f32, speed: f32, bass: f32, mids: f32, clickBurst: f32) -> CellField {
  let cell = floor(p);
  var f1 = 1e9;
  var f2 = 1e9;
  var f3 = 1e9;
  var pt1 = p;
  var pt2 = p;
  var id = 0.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = cell + vec2<f32>(f32(x), f32(y));
      // HEAD fix: time no longer enters the hash (it re-randomised every point each frame).
      let rnd = hash22(neighbor + CELL_SEED);
      let feature = neighbor + rnd + vec2<f32>(
        sin(time * speed + rnd.x * 6.28 + bass * 2.0) * 0.15 * (1.0 + bass + clickBurst),
        cos(time * speed + rnd.y * 6.28 + mids * 2.0) * 0.15 * (1.0 + bass)
      );
      let d = distance(p, feature);
      if d < f1 {
        f3 = f2;
        f2 = f1;
        pt2 = pt1;
        f1 = d;
        pt1 = feature;
        id = hash21(neighbor);
      } else if d < f2 {
        f3 = f2;
        f2 = d;
        pt2 = feature;
      } else if d < f3 {
        f3 = d;
      }
    }
  }
  var out: CellField;
  out.f1 = f1;
  out.f2 = f2;
  out.f3 = f3;
  out.cellId = id;
  out.grad = (p - pt2) / max(f2, 1e-4) - (p - pt1) / max(f1, 1e-4);
  return out;
}

struct TissueShade {
  hdr: vec3<f32>,
  scatter: f32,
  node: f32,
};

// HEAD tissue shading (palette, SSS scatter, fBm, boundary glow, audio tint) as a function
// of the cell fields, so the membrane aberration can re-evaluate it at displaced taps.
fn shadeTissue(w: CellField, drift: f32, org: f32, organic: f32,
               bass: f32, mids: f32, treble: f32, clickBurst: f32) -> TissueShade {
  let f1 = w.f1 + drift;
  let boundary = (w.f2 - w.f1) + drift * 0.5;

  // Idea 2 — turgor pulse: bass pressurises every cell. The wall field is steepened so
  // membranes thin, and a dome over each cell (1 at the seed, 0 at the wall) swells/brightens.
  let turgor = clamp(bass, 0.0, 1.5);
  let rWall = clamp(2.0 * w.f1 / max(w.f1 + w.f2, 1e-4), 0.0, 1.0);
  let dome = sqrt(max(1.0 - rWall * rWall, 0.0));
  let wallB = boundary * (1.0 + 1.6 * turgor);

  // Organic tissue palette
  let tissue = mix(
    vec3<f32>(0.85, 0.55, 0.50),   // pink
    vec3<f32>(0.95, 0.72, 0.55),   // coral
    w.cellId
  );
  let ivory = vec3<f32>(0.96, 0.94, 0.88);
  let taupe = vec3<f32>(0.55, 0.48, 0.42);

  // Subsurface scattering on cell boundaries
  let scatter = exp(-wallB * 8.0) * (0.6 + mids * 0.4 + clickBurst * 0.5);
  var color = mix(taupe, mix(tissue, ivory, smoothstep(0.0, 0.4, f1)), smoothstep(0.0, 0.6, f1));
  color = color + vec3<f32>(1.0, 0.7, 0.5) * scatter * 0.5;

  // fBm for organic variation
  color = mix(color, color * (0.8 + org * 0.4), organic);

  // Idea 2 — turgor: inflated interiors brighten, with a taut pressure sheen on the dome crown.
  let dome2 = dome * dome;
  color = color * (1.0 + turgor * 0.45 * dome);
  color = color + mix(tissue, ivory, 0.5) * (dome2 * dome2) * turgor * 0.22;

  // HDR boundary glow
  let glow = exp(-wallB * 15.0) * (0.3 + treble * 0.5 + clickBurst);
  color = color + vec3<f32>(0.9, 0.75, 0.55) * glow;

  // Audio-driven color shift on cell interiors
  let audioTint = vec3<f32>(bass * 0.2, mids * 0.1, treble * 0.25);
  color = color + audioTint * smoothstep(0.3, 0.0, f1);

  // Idea 3 — triple-junction vertices: F3−F1 → 0 only where three cells meet
  // (F1 ≤ F2 ≤ F3), so a Gaussian on that gap lights a node at every wall vertex.
  let gap3 = (w.f3 - w.f1) / (0.075 / (1.0 + 0.5 * turgor));
  let node = exp(-gap3 * gap3);
  color = color + vec3<f32>(1.0, 0.86, 0.72) * node * (1.1 + treble * 0.8 + mids * 0.3);

  var s: TissueShade;
  s.hdr = color;
  s.scatter = scatter;
  s.node = node;
  return s;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  // HEAD fix: audio read directly (the extraBuffer spring never persisted).
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseClick = u.zoom_config.w;

  let scale = mix(3.0, 12.0, u.zoom_params.x) * (1.0 + bass * 0.3);
  let speed = mix(0.05, 0.4, u.zoom_params.y);
  let caAmt = u.zoom_params.z;
  let organic = u.zoom_params.w;

  // HEAD fix: click state is the live held flag (prevMouse/clickCount in extraBuffer never persisted).
  let clickBurst = step(0.5, mouseClick);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * vec2<f32>(aspect, 1.0) * scale;

  // Mouse attracts feature points, click bursts repel them
  let mPos = mouse * vec2<f32>(aspect, 1.0) * scale;
  let attraction = 0.15 + clickBurst * 0.2;
  p = p - mPos * attraction + (p - mPos) * clickBurst * 0.1;

  // Depth controls cell size perspective
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  p = p * (0.5 + depthSample);

  // Temporal feedback for organic drift (exact load of last frame's boundary field)
  let prev = textureLoad(dataTextureC, coord, 0);
  let drift = mix(0.0, clamp(prev.g, 0.0, 2.0) * 0.08, organic);

  let org = fbm(p * 2.0 + vec2<f32>(time * 0.1, 0.0));

  let wc = worleyField(p, time, speed, bass, mids, clickBurst);
  let centre = shadeTissue(wc, drift, org, organic, bass, mids, treble, clickBurst);
  var hdr = centre.hdr;

  // Idea 1 — real membrane aberration: the wall acts as a thin lens. R and B re-run the
  // Worley field and tissue shading at ±offset along ∇(F2−F1), so walls split into a
  // red-cored / blue-fringed membrane (and junction nodes fringe too). Offset is largest
  // at the wall and scaled by the Chromatic Aberration slider (and treble, as at HEAD).
  if (caAmt > 0.001) {
    let wallBand = 1.0 - smoothstep(0.0, 0.3, wc.f2 - wc.f1);
    let gLen = length(wc.grad);
    let dir = select(vec2<f32>(0.0), wc.grad / gLen, gLen > 1e-4);
    let offs = dir * caAmt * 0.07 * (1.0 + treble) * wallBand;
    let wr = worleyField(p + offs, time, speed, bass, mids, clickBurst);
    let wb = worleyField(p - offs, time, speed, bass, mids, clickBurst);
    hdr.r = shadeTissue(wr, drift, org, organic, bass, mids, treble, clickBurst).hdr.r;
    hdr.b = shadeTissue(wb, drift, org, organic, bass, mids, treble, clickBurst).hdr.b;
  }

  let color = acesToneMap(hdr * 1.2);

  // Alpha: membrane opacity × tissue density × depth × interaction, floored so a flat or
  // empty depth map keeps the tissue visible; junction nodes are fully opaque.
  let f1d = wc.f1 + drift;
  let boundaryD = (wc.f2 - wc.f1) + drift * 0.5;
  let tissueDensity = clamp(1.0 - f1d * 0.5, 0.0, 1.0);
  let interaction = 1.0 + bass * 0.3 + clickBurst * 0.5;
  let depthW = mix(0.7, 1.0, clamp(depthSample, 0.0, 1.0));
  let alpha = clamp(mix(0.45, 1.0, clamp(centre.scatter, 0.0, 1.0)) * tissueDensity * depthW * interaction
                    + centre.node * 0.5, 0.0, 1.0);
  let depthOut = clamp(0.2 + tissueDensity * 0.8 + bass * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(f1d, boundaryD, centre.scatter, alpha));
}
