// ═══════════════════════════════════════════════════════════════════
//  Crystal Lattice Growth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba, procedural
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Mineral dendrites crystallise from a nucleation seed, each
//  branch angle tuned to the golden ratio. Bass pulses growth.
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

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Segment SDF: distance from p to segment a→b
fn sdSeg(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Draw one recursive crystal branch, depth levels deep
fn crystalBranch(
  p: vec2<f32>,
  origin: vec2<f32>, direction: vec2<f32>,
  length_: f32, depth: u32,
  time: f32, bass: f32, thickness: f32
) -> f32 {
  var glow = 0.0;
  var o = origin;
  var d = direction;
  var l = length_;
  var thk = thickness;

  for (var i = 0u; i < 5u; i++) {
    if (i >= depth) { break; }
    let tip = o + d * l;
    let dist = sdSeg(p, o, tip);
    glow += exp(-dist * dist / (thk * thk * 2.0)) * (1.0 - f32(i) * 0.15);

    // Branch: two children at ±golden angle
    let goldenAngle = 2.399963;  // ~137.5 degrees in radians
    let leftAngle = goldenAngle * 0.5;
    let childLen = l * 0.65;
    let cos1 = cos(leftAngle);
    let sin1 = sin(leftAngle);
    let childDir = vec2<f32>(cos1 * d.x - sin1 * d.y, sin1 * d.x + cos1 * d.y);
    let tip2 = o + d * l;
    let subDist = sdSeg(p, tip2, tip2 + childDir * childLen);
    glow += exp(-subDist * subDist / (thk * thk * 4.0)) * 0.5 * (1.0 - f32(i) * 0.2);

    // Advance along current branch for next iteration
    o = tip;
    l = childLen;
    thk *= 0.7;
  }
  return glow;
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

  let symCount  = i32(mix(3.0, 12.0, u.zoom_params.x));
  let growRate  = mix(0.1, 1.0, u.zoom_params.y) * (1.0 + bass * 0.4);
  let hueBase   = fract(u.zoom_params.z + t * 0.04 + mids * 0.1);
  let thickness = mix(0.005, 0.025, u.zoom_params.w) * (1.0 + bass * 0.3);

  // Mouse attraction of nucleation seed
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.35 * u.zoom_config.w;

  var totalGlow = 0.0;
  let branchLen = (0.15 + 0.5 * growRate) * (0.8 + 0.2 * sin(t * 0.4));
  let depth = 4u;

  // Radial symmetry: spawn arms at equal angles
  for (var a = 0; a < symCount; a++) {
    let armAngle = f32(a) * 6.28318 / f32(symCount) + t * 0.05;
    let armDir = vec2<f32>(cos(armAngle), sin(armAngle));
    totalGlow += crystalBranch(p, vec2<f32>(0.0), armDir, branchLen, depth, t, bass, thickness);
  }

  // Colour: prismatic mapping along hue spectrum
  let hue = fract(hueBase + totalGlow * 0.15 + treble * 0.05);
  var col = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * hue),
    0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
    0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
  ) * min(totalGlow, 2.5);

  // Facets: small angular ripple adds crystalline refractive shimmer
  let facet = 0.5 + 0.5 * cos(atan2(p.y, p.x) * f32(symCount * 2));
  col *= 0.85 + 0.15 * facet;

  // Dark mineral background
  col = mix(vec3<f32>(0.02, 0.02, 0.04), col, min(totalGlow * 0.8, 1.0));

  col = aces(col);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.85 + totalGlow * 0.1, 0.0, 1.0);
  let depth2 = clamp(1.0 - length(p) * 0.5, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth2, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
