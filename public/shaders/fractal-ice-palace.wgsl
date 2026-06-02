// ═══════════════════════════════════════════════════════════════════
//  Fractal Ice Palace
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal,
//            chromatic-dispersion, fractal-branching, depth-aware
//  Complexity: Very High
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  Recursive ice crystal palace with fractal branching architecture.
//  Chromatic ice refractions: blue core, cyan edges, white sparkle.
//  Bass shakes the palace, mids control recursion depth, treble adds
//  frost glitter. Mouse melts local ice.
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

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0;
  return mix(
    mix(hash2(vec2<f32>(n)), hash2(vec2<f32>(n + 1.0)), u.x),
    mix(hash2(vec2<f32>(n + 57.0)), hash2(vec2<f32>(n + 58.0)), u.x),
    u.y
  );
}

fn rot2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn smoothstepf32(edge0: f32, edge1: f32, x: f32) -> f32 {
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// Recursive ice branch distance field
struct IceBranchNode {
  origin: vec2<f32>,
  angle: f32,
  len: f32,
  width: f32,
  depth: i32,
};

// Iterative (stack-based) binary-tree traversal — WGSL forbids recursion.
// max() over every node is equivalent to the original recursive max().
fn iceBranch(p: vec2<f32>, origin: vec2<f32>, angle: f32, len: f32,
             width: f32, startDepth: i32, maxDepth: i32, time: f32,
             bass: f32, mids: f32) -> vec4<f32> {
  var result = vec4<f32>(0.0);
  var stack: array<IceBranchNode, 32>;
  var sp = 0;
  stack[0] = IceBranchNode(origin, angle, len, width, startDepth);
  sp = 1;

  loop {
    if (sp <= 0) { break; }
    sp = sp - 1;
    let node = stack[sp];
    let depth = node.depth;
    if (depth >= maxDepth) { continue; }

    let end = node.origin + vec2<f32>(cos(node.angle), sin(node.angle)) * node.len;
    let d = sdSegment(p, node.origin, end);
    let branchStr = smoothstepf32(node.width, 0.0, d);

    // Shake from bass
    let shake = sin(time * 3.0 + f32(depth) * 1.7) * bass * 0.02 * f32(depth + 1);

    if (branchStr > 0.001) {
      // Chromatic: blue core, cyan edge, white tip
      let core = smoothstepf32(node.width * 0.6, 0.0, d);
      let edge = smoothstepf32(node.width, node.width * 0.5, d);
      let tip = smoothstepf32(node.len * 0.7, node.len, length(p - node.origin));
      let r = edge * 0.4 + tip * 0.8;
      let g = core * 0.6 + edge * 0.9 + tip * 0.95;
      let b = core * 1.0 + edge * 0.8 + tip * 0.9;
      let nodeColor = vec4<f32>(r, g, b, branchStr) * (0.7 + f32(maxDepth - depth) * 0.1);
      result = max(result, nodeColor);
    }

    // Push child branches
    if (depth < maxDepth - 1 && node.len > 0.02) {
      let branchAngle1 = node.angle + 0.55 + sin(time * 0.5 + f32(depth)) * 0.1 + shake;
      let branchAngle2 = node.angle - 0.55 + cos(time * 0.4 + f32(depth)) * 0.1 - shake;
      let newLen = node.len * (0.62 + mids * 0.05);
      let newWidth = node.width * 0.65;
      if (sp < 31) {
        stack[sp] = IceBranchNode(end, branchAngle1, newLen, newWidth, depth + 1);
        sp = sp + 1;
      }
      if (sp < 31) {
        stack[sp] = IceBranchNode(end, branchAngle2, newLen, newWidth, depth + 1);
        sp = sp + 1;
      }
    }
  }

  return result;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let palaceScale = mix(0.4, 1.2, u.zoom_params.x);
  let recursionDepth = mix(2.0, 7.0, u.zoom_params.y);
  let frostAmount = mix(0.0, 1.0, u.zoom_params.z);
  let refraction = mix(0.3, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Mouse melting: local distortion around mouse
  let mouseDist = length(p - mouse);
  let meltRadius = 0.15 + bass * 0.05;
  let meltStrength = smoothstepf32(meltRadius, 0.0, mouseDist);
  let meltAngle = atan2(p.y - mouse.y, p.x - mouse.x);
  p = p + vec2<f32>(cos(meltAngle + time), sin(meltAngle + time)) *
          meltStrength * 0.03;

  // Central palace structure
  let maxDepth = i32(recursionDepth);
  var palaceColor = vec4<f32>(0.0);

  // Main spire
  let spire = iceBranch(p, vec2<f32>(0.0, -0.7), 1.5708,
                        0.35 * palaceScale, 0.025 * palaceScale,
                        0, maxDepth, time, bass, mids);
  palaceColor = max(palaceColor, spire);

  // Left tower
  let towerL = iceBranch(p, vec2<f32>(-0.35 * palaceScale, -0.6),
                         1.3 + sin(time * 0.2) * 0.05,
                         0.25 * palaceScale, 0.02 * palaceScale,
                         0, maxDepth - 1, time, bass, mids);
  palaceColor = max(palaceColor, towerL);

  // Right tower
  let towerR = iceBranch(p, vec2<f32>(0.35 * palaceScale, -0.6),
                         1.84 - sin(time * 0.25) * 0.05,
                         0.25 * palaceScale, 0.02 * palaceScale,
                         0, maxDepth - 1, time, bass, mids);
  palaceColor = max(palaceColor, towerR);

  // Arching bridges
  let bridgeL = iceBranch(p,
    vec2<f32>(-0.15 * palaceScale, 0.0),
    0.4 + sin(time * 0.3) * 0.05 + bass * 0.02,
    0.2 * palaceScale, 0.015 * palaceScale,
    0, maxDepth - 2, time, bass, mids);
  palaceColor = max(palaceColor, bridgeL);

  let bridgeR = iceBranch(p,
    vec2<f32>(0.15 * palaceScale, 0.0),
    2.74 - sin(time * 0.35) * 0.05 - bass * 0.02,
    0.2 * palaceScale, 0.015 * palaceScale,
    0, maxDepth - 2, time, bass, mids);
  palaceColor = max(palaceColor, bridgeR);

  // ═══ Frost Glitter (driven by treble) ═══
  var glitter = 0.0;
  let glitterCount = u32(mix(0.0, 40.0, frostAmount + treble * 0.6));
  for (var i = 0u; i < glitterCount; i = i + 1u) {
    let fi = f32(i);
    let gPos = vec2<f32>(
      sin(fi * 3.7 + time * 0.1) * 0.5 * palaceScale,
      cos(fi * 2.3 + time * 0.15) * 0.4 * palaceScale - 0.2
    );
    let gDist = length(p - gPos);
    let gSize = 0.008 + treble * 0.004;
    let gTwinkle = sin(time * 5.0 + fi * 2.1) * 0.5 + 0.5;
    glitter = max(glitter, smoothstepf32(gSize, 0.0, gDist) * gTwinkle);
  }

  // ═══ Chromatic Refraction Enhancement ═══
  // Apply wavelength-dependent offsets based on refraction param
  let refractOffset = refraction * 0.015;
  let rOff = vec2<f32>(refractOffset, 0.0);
  let gOff = vec2<f32>(0.0, refractOffset * 0.5);
  let bOff = vec2<f32>(-refractOffset, refractOffset);

  let palaceR = iceBranch(p + rOff, vec2<f32>(0.0, -0.7), 1.5708,
                          0.35 * palaceScale, 0.025 * palaceScale,
                          0, max(1, maxDepth - 1), time, bass, mids);
  let palaceG = iceBranch(p + gOff, vec2<f32>(0.0, -0.7), 1.5708,
                          0.35 * palaceScale, 0.025 * palaceScale,
                          0, max(1, maxDepth - 1), time, bass, mids);
  let palaceB = iceBranch(p + bOff, vec2<f32>(0.0, -0.7), 1.5708,
                          0.35 * palaceScale, 0.025 * palaceScale,
                          0, max(1, maxDepth - 1), time, bass, mids);

  var color = vec3<f32>(0.0);
  color.r = palaceColor.r * 0.5 + palaceR.r * 0.5;
  color.g = palaceColor.g * 0.5 + palaceG.g * 0.5;
  color.b = palaceColor.b * 0.5 + palaceB.b * 0.5;

  // Add glitter with slight chromatic bias
  color += vec3<f32>(0.85, 0.92, 1.0) * glitter * (0.5 + treble * 0.8);

  // Melt glow around mouse
  color += vec3<f32>(0.6, 0.8, 1.0) * meltStrength * 0.3 * (1.0 + bass);

  // Background atmospheric ice fog
  let fogNoise = noise2(p * 4.0 + time * 0.05);
  let fog = fogNoise * 0.04 * (1.0 + bass * 0.3);
  color += vec3<f32>(0.5, 0.7, 0.9) * fog;

  // ═══ Temporal Feedback ═══
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let feedbackAmount = 0.03 + mids * 0.01;
  color = mix(color, prev.rgb * 0.94, feedbackAmount);

  // ═══ Semantic Alpha ═══
  let presence = palaceColor.a + glitter * 0.5 + meltStrength * 0.3;
  let alpha = clamp(0.08 + presence * 0.92, 0.0, 1.0);

  // Depth: branches near center are closer
  let centerDist = length(p);
  let depth = clamp(0.3 + centerDist * 0.5 + palaceColor.a * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
