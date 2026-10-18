// ═══════════════════════════════════════════════════════════════════
//  Morphogenic Resonance
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, chromatic, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: travelling morph front (morphogen wave from pointer); crystalline facet spokes; veins conduct the discharge
//  A packing: ACES display RGBA (rgb = toned colour incl. CA, a = edge/interior coverage); C read as colour history
// ═══════════════════════════════════════════════════════════════════
//  Organic shapes morph between geometric and biological forms via
//  sinusoidal interpolation. Bass drives morph speed, mids add surface
//  ripple resonance, treble creates edge discharge. Mouse warps the
//  morph field and is the source of the morphogen wave.

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

const PI = 3.14159265;
const TAU = 6.2831853;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v += a * noise2(p * f);
    a *= 0.5;
    f *= 2.03;
  }
  return v;
}

// SDF for a polygon (geometric form)
fn sdPolygon(p: vec2<f32>, n: f32, r: f32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = TAU / n;
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let d = length(p);
  let polyDist = cos(a) * d - r;
  return polyDist;
}

// SDF for organic blob (biological form)
fn sdOrganic(p: vec2<f32>, time: f32, seed: f32) -> f32 {
  let n1 = noise2(p * 3.0 + vec2<f32>(time * 0.3 + seed, seed));
  let n2 = noise2(p * 5.0 - vec2<f32>(seed, time * 0.2));
  let d = length(p) - 0.25 - n1 * 0.08 - n2 * 0.04;
  return d;
}

// Idea 2 — crystalline facet spokes: same sector math as sdPolygon.
// x = centre-to-vertex bevel line (1 on the spoke), y = facet shade 0..1
// (each triangular facet lit by its own normal angle, like a cut stone).
fn polyFacet(p: vec2<f32>, n: f32, pxW: f32) -> vec2<f32> {
  let angle = atan2(p.y, p.x);
  let sector = TAU / n;
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let d = length(p);
  // perpendicular distance to the nearest vertex ray (vertices sit at a = sector/2)
  let spokeD = d * sin(sector * 0.5 - a);
  let spoke = (1.0 - smoothstep(0.0, pxW, spokeD)) * smoothstep(0.0, 0.03, d);
  let k = floor(angle / sector + 0.5);
  let shade = 0.5 + 0.5 * cos(k * sector - 0.785398);
  return vec2<f32>(spoke, shade);
}

struct MorphSample {
  dist: f32,
  phase: f32,   // per-cell (wave-lagged) morph phase 0..1
  interp: f32,  // per-cell geo->bio blend 0..1
  spoke: f32,   // facet spoke line, already faded by organic-ness
  facet: f32,   // facet shade, already faded by organic-ness (signed, 0 = neutral)
  vein: f32,    // vein band 0..1, weighted by organic-ness
};

// Morph field value
fn morphField(uv: vec2<f32>, time: f32, morphSpeed: f32, geoBias: f32, waveOrigin: vec2<f32>, pxW: f32) -> MorphSample {
  let t = time * morphSpeed;

  // Grid of shapes
  let gridScale = 3.0 + geoBias * 2.0;
  let gp = uv * gridScale;
  let cell = floor(gp);
  let local = fract(gp) - 0.5;

  // Idea 1 — travelling morph front: each cell's morph clock lags by the
  // distance of its centre from the pointer, so the geo->bio change sweeps
  // outward as a morphogen wave (HEAD: every cell in lockstep off sin(t)).
  let cellCentre = (cell + vec2<f32>(0.5)) / gridScale;
  let waveLag = length(cellCentre - waveOrigin) * 5.0;
  let morphPhase = sin(t - waveLag) * 0.5 + 0.5;
  let phase = mix(morphPhase, smoothstep(0.0, 1.0, morphPhase), geoBias);

  let seed = hash21(cell);
  let nSides = 3.0 + floor(seed * 5.0);
  let rotAngle = seed * TAU + t * 0.2;
  let c = cos(rotAngle);
  let s = sin(rotAngle);
  let rotLocal = vec2<f32>(c * local.x - s * local.y, s * local.x + c * local.y);

  let geoDist = sdPolygon(rotLocal, nSides, 0.22 + seed * 0.08);
  let bioDist = sdOrganic(local, t, seed);

  // Sinusoidal interpolation between forms
  let interp = phase + geoBias * 0.3;
  let smoothInterp = interp * interp * (3.0 - 2.0 * interp);
  var dist = mix(geoDist, bioDist, smoothInterp);

  // Idea 2 — facets are bright while geometric, dissolve as the cell turns organic.
  let geoAmt = clamp(1.0 - smoothInterp, 0.0, 1.0);
  let fac = polyFacet(rotLocal, nSides, pxW);

  // Add internal vein structure when biological
  var veinBand = 0.0;
  if (smoothInterp > 0.4) {
    let veinNoise = fbm2(local * 8.0 + vec2<f32>(t * 0.1), 3);
    let vein = smoothstep(0.35, 0.45, veinNoise) * smoothstep(0.65, 0.55, veinNoise);
    dist = dist - vein * 0.03 * smoothInterp;
    veinBand = vein * clamp(smoothInterp, 0.0, 1.0);
  }

  return MorphSample(dist, morphPhase, clamp(smoothInterp, 0.0, 1.0),
                     fac.x * geoAmt, (fac.y - 0.5) * geoAmt, veinBand);
}

fn hueShiftRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv01 = vec2<f32>(gid.xy) / res;
  let aspect = res.x / res.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let morphSpeed = u.zoom_params.x * 2.0 + 0.2;
  let geoBias = u.zoom_params.y;
  let rippleIntensity = u.zoom_params.z * 2.0;
  let colorShift = u.zoom_params.w;

  // Closed-form morph-field conveyor and mouse warp.
  let warpT = time + 0.35 * sin(time * 0.43);
  var warpedUV = uv;
  warpedUV.x += warpT * morphSpeed * 0.22;
  warpedUV.y += sin(warpT * 0.7 + uv.x * 2.0) * morphSpeed * 0.08;
  let mouseDist = length(uv - mouse);
  let mouseWarp = exp(-mouseDist * mouseDist * 8.0) * 0.15;
  warpedUV += normalize(uv - mouse + vec2<f32>(0.001)) * mouseWarp;

  // Traveling resonance rings along the morph surface.
  let ringPhase = sin(length(warpedUV) * 18.0 - warpT * (4.0 + mids * 3.0));
  let ringFront = smoothstep(0.55, 1.0, ringPhase) * rippleIntensity * 0.035;

  // Calculate morph field
  // Idea 1 — wave origin: the pointer carried into morph-field space by the
  // same conveyor that moves the cells, so the front stays centred on it.
  let waveOrigin = mouse + vec2<f32>(warpT * morphSpeed * 0.22,
                                     sin(warpT * 0.7 + mouse.x * 2.0) * morphSpeed * 0.08);
  let gridScale = 3.0 + geoBias * 2.0;
  let pxW = 1.5 * gridScale / res.y + 0.004; // ~1.5 px spoke half-width in cell units
  let ms = morphField(warpedUV, warpT, morphSpeed * 1.35, geoBias, waveOrigin, pxW);
  var dist = ms.dist;
  dist -= ringFront;

  // Bass-driven morph acceleration (temporal warp)
  let bassWarp = sin(uv.x * 10.0 + time * morphSpeed * (1.0 + bass * 2.0)) * bass * 0.03;
  dist += bassWarp;

  // Mids add surface ripple resonance
  let ripple = sin(length(warpedUV) * 30.0 - time * 3.0 * (1.0 + mids)) * mids * rippleIntensity * 0.02;
  dist += ripple;

  // Shape edge glow
  let edge = 1.0 - smoothstep(-0.02, 0.04, dist);
  let interior = 1.0 - smoothstep(0.0, 0.06, dist);

  // Treble edge discharge — smooth noise, no per-frame hash strobing.
  let dischargeNoise = noise2(warpedUV * 24.0 + vec2<f32>(warpT * 2.5, 0.0));
  // Idea 3 — veins conduct the discharge: in organic cells the treble arc runs
  // along the vein fbm band inside the body; geometric cells keep HEAD's edge arc.
  let edgeArc = dischargeNoise * edge;
  let veinArc = ms.vein * interior * (0.55 + 0.45 * dischargeNoise) + edgeArc * 0.3;
  let discharge = treble * mix(edgeArc, veinArc, ms.interp) * 2.2;

  // Color based on morph phase and audio
  let hue = colorShift + bass * 0.1 + interior * 0.15 + time * 0.02;
  var col = hueShiftRGB(hue);

  // Geometric forms lean toward cyan/blue, biological toward warm organic
  let geoColor = vec3<f32>(0.3, 0.7, 0.9);
  let bioColor = vec3<f32>(0.9, 0.5, 0.3);
  // Idea 1 — tint follows the per-cell (wave-lagged) phase, so colour and
  // shape change together as the front passes.
  let formColor = mix(geoColor, bioColor, ms.phase);
  col = mix(col, formColor, 0.4);

  // Idea 2 — crystalline facet spokes: faceted bevel shading plus bright
  // centre-to-vertex ridge lines while the cell is geometric.
  col += geoColor * ms.facet * 0.35 * interior;
  col += vec3<f32>(0.8, 0.95, 1.0) * ms.spoke * interior * (0.55 + treble * 0.4);

  // Interior fill with organic texture
  let interiorTex = fbm2(warpedUV * 6.0 + time * 0.1, 4) * interior;
  col += vec3<f32>(0.1, 0.2, 0.15) * interiorTex;

  // Edge glow and discharge
  col += vec3<f32>(0.6, 0.8, 1.0) * edge * (0.5 + treble);
  col += vec3<f32>(1.0, 0.9, 0.7) * discharge;

  // Velocity-advected HDR trails (textureLoad only, bounded).
  let flowDir = normalize(vec2<f32>(morphSpeed * 0.4, sin(warpT * 0.5) * 0.25) + vec2<f32>(0.001));
  let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
  let histCoord = clamp(vec2<i32>(gid.xy) - vec2<i32>(flowDir * (3.0 + morphSpeed * 4.0)), vec2<i32>(0), maxCoord);
  let prev = textureLoad(dataTextureC, histCoord, 0).rgb;
  let decay = 0.84 + morphSpeed * 0.04 + bass * 0.02;
  var fbCol = clamp(col + prev * decay, vec3<f32>(0.0), vec3<f32>(5.5));

  // Semantic alpha: based on edge presence and interior density
  let alpha = clamp(edge * 0.9 + interior * 0.6 + discharge * 0.3, 0.0, 1.0);

  // Depth based on morph field distance
  let depth = clamp(0.5 + dist * 2.0 + interiorTex * 0.2, 0.0, 1.0);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  fbCol = vec3<f32>(fbCol.r + caStr, fbCol.g, fbCol.b - caStr * 0.5);

  fbCol = acesToneMap(fbCol * 1.1);
  textureStore(writeTexture, gid.xy, vec4<f32>(fbCol, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));
}
