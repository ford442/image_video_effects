// ═══════════════════════════════════════════════════════════════════
//  Crystal Lattice Growth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba, procedural,
//            hdr-ready, lod-aware, depth-aware, bloom
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
//  Bloom threshold (HDR): 0.85
//  Mineral dendrites crystallise from a nucleation seed, each
//  branch angle tuned to the golden ratio. Bass pulses growth.
//  LOD reduces branch iterations and symmetry in peripheral pixels;
//  sparse hex-bokeh approximates glow without full per-pixel recursion.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Symmetry, y=GrowthRate, z=Hue, w=Thickness
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════
//  Named physical / artistic constants
// ═══════════════════════════════════════════════════════════════════
const TAU: f32 = 6.28318530718;
const GOLDEN_ANGLE: f32 = 2.39996322973;
const CHILD_ANGLE: f32 = 1.19998161486; // GOLDEN_ANGLE * 0.5
const CHILD_SCALE: f32 = 0.65;
const THICKNESS_DECAY: f32 = 0.7;
const WEIGHT_DECAY: f32 = 0.85;
const MAX_BRANCH_DEPTH: u32 = 5u;
const EARLY_EXIT_RADIUS: f32 = 1.25;
const BOKEH_TAPS: u32 = 6u;
const MIN_SYMMETRY: f32 = 3.0;
const MAX_SYMMETRY: f32 = 12.0;
const MIN_DEPTH: f32 = 2.0;
const MAX_DEPTH: f32 = 5.0;
const BLOOM_THRESHOLD: f32 = 0.85;

// Segment SDF: distance from p to segment a→b
fn sdSeg(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Rotate a 2D vector by angle r
fn rotate2D(v: vec2<f32>, r: f32) -> vec2<f32> {
  let c = cos(r);
  let s = sin(r);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Energy of one dendritic branch; loop bound is LOD-driven, so the
// branch is branchless inside (no early-break or conditional stores).
fn branchEnergy(
  p: vec2<f32>,
  origin: vec2<f32>, direction: vec2<f32>,
  length_: f32, depth: u32,
  thickness: f32
) -> f32 {
  var glow = 0.0;
  var o = origin;
  var d = direction;
  var l = length_;
  var thk = thickness;
  var weight = 1.0;

  for (var i = 0u; i < depth; i++) {
    let tip = o + d * l;
    let dist = sdSeg(p, o, tip);
    glow += exp(-dist * dist / (thk * thk * 2.0)) * weight;

    // Single golden-ratio child branch
    let childDir = rotate2D(d, CHILD_ANGLE);
    let childLen = l * CHILD_SCALE;
    let childTip = tip + childDir * childLen;
    let childDist = sdSeg(p, tip, childTip);
    glow += exp(-childDist * childDist / (thk * thk * 4.0)) * weight * 0.5;

    o = tip;
    l = childLen;
    thk *= THICKNESS_DECAY;
    weight *= WEIGHT_DECAY;
  }
  return glow;
}

// Accumulate radial crystal energy with dynamic symmetry count
fn crystalEnergy(
  p: vec2<f32>, branchLen: f32, depth: u32,
  thickness: f32, symCount: i32, time: f32
) -> f32 {
  var energy = 0.0;
  let invSym = 1.0 / f32(symCount);
  for (var a = 0; a < symCount; a++) {
    let armAngle = f32(a) * TAU * invSym + time * 0.05;
    let armDir = vec2<f32>(cos(armAngle), sin(armAngle));
    energy += branchEnergy(p, vec2<f32>(0.0), armDir, branchLen, depth, thickness);
  }
  return energy;
}

// Sparse hexagonal bokeh glow sampled from the previous frame to
// approximate wide glow at a fraction of the per-pixel recursion cost.
fn hexBokehGlow(uv: vec2<f32>, radius: f32, time: f32) -> f32 {
  var accum = 0.0;
  let rot = time * 0.1;
  let invTaps = 1.0 / f32(BOKEH_TAPS);
  for (var i = 0u; i < BOKEH_TAPS; i++) {
    let ang = rot + TAU * f32(i) * invTaps;
    let tapUV = uv + vec2<f32>(cos(ang), sin(ang)) * radius;
    let tap = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0);
    accum += dot(tap.rgb, vec3<f32>(0.299, 0.587, 0.114));
  }
  return accum * invTaps;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Map energy to prismatic crystal colour
fn prismaticColor(energy: f32, hueBase: f32, treble: f32) -> vec3<f32> {
  let hue = fract(hueBase + energy * 0.15 + treble * 0.05);
  return vec3<f32>(
    0.5 + 0.5 * cos(TAU * hue),
    0.5 + 0.5 * cos(TAU * (hue + 0.33)),
    0.5 + 0.5 * cos(TAU * (hue + 0.67))
  );
}

// Composite crystal depth against incoming scene depth
fn smartDepth(crystalDepth: f32, sceneDepth: f32, alpha: f32) -> f32 {
  let depthMask = (alpha > 0.02) || (crystalDepth < sceneDepth);
  return select(sceneDepth, crystalDepth, depthMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

  // Mouse attraction of nucleation seed
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  p -= mouse * 0.35 * u.zoom_config.w;

  let r = length(p);

  // Early-exit: pixels beyond crystal influence pass scene depth through unchanged
  if (r > EARLY_EXIT_RADIUS) {
    let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let bg = vec4<f32>(0.02, 0.02, 0.04, 0.0);
    textureStore(writeTexture,      coord, bg);
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA,      coord, bg);
    return;
  }

  // LOD quality scaling: reduce work for peripheral pixels and when mouse is held
  let lodFactor = clamp(r / EARLY_EXIT_RADIUS, 0.0, 1.0);
  let zoomBoost = 1.0 + 0.2 * u.zoom_config.w;
  let depth = u32(mix(MAX_DEPTH, MIN_DEPTH, lodFactor));
  let symCount = i32(mix(MAX_SYMMETRY, MIN_SYMMETRY, lodFactor));

  let growRate  = mix(0.1, 1.0, u.zoom_params.y) * (1.0 + bass * 0.4) * zoomBoost;
  let hueBase   = fract(u.zoom_params.z + t * 0.04 + mids * 0.1);
  let thickness = mix(0.005, 0.025, u.zoom_params.w) * (1.0 + bass * 0.3);

  let branchLen = (0.15 + 0.5 * growRate) * (0.8 + 0.2 * sin(t * 0.4));

  // Primary crystal energy with dynamic LOD
  var totalGlow = crystalEnergy(p, branchLen, depth, thickness, symCount, t);

  // Sparse hex-bokeh glow approximation on previous frame for cheap bloom
  let bokehRadius = mix(0.003, 0.012, u.zoom_params.w) * (1.0 + bass * 0.5);
  totalGlow += hexBokehGlow(uv, bokehRadius, t) * 0.35;

  // Colour and compositing
  var col = prismaticColor(totalGlow, hueBase, treble) * min(totalGlow, 2.5);

  // Facets: small angular ripple adds crystalline refractive shimmer
  let facet = 0.5 + 0.5 * cos(atan2(p.y, p.x) * f32(symCount * 2));
  col *= 0.85 + 0.15 * facet;

  // Dark mineral background
  col = mix(vec3<f32>(0.02, 0.02, 0.04), col, min(totalGlow * 0.8, 1.0));

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  col = acesToneMap(col);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.85 + totalGlow * 0.1, 0.0, 1.0);
  let crystalDepth = clamp(1.0 - r * 0.5, 0.0, 1.0);

  let finalColor = vec4<f32>(acesToneMap(col * 1.1), alpha);

  // Smart depth pass-through: respect existing scene depth outside crystal foreground
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalDepth = smartDepth(crystalDepth, sceneDepth, alpha);

  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
