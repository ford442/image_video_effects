// ═══════════════════════════════════════════════════════════════════
//  Fractal Ember Lattice
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: Very High
//  Description: Hexagonal crystal lattice glowing like hot embers.
//  Mouse click shatters the lattice into rigid shards that fly outward;
//  release to watch them drift back and reform over ~1.5s.
//  Audio drives glow pulse, lattice breathing, and spark frequency.
//  Created: 2026-06-06
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// Triangular lattice distance (3 directions at 60°)
fn triLatticeDist(p: vec2<f32>) -> f32 {
  let d1 = abs(fract(p.x) - 0.5);
  let d2 = abs(fract(p.x * 0.5 + p.y * 0.866025) - 0.5);
  let d3 = abs(fract(p.x * 0.5 - p.y * 0.866025) - 0.5);
  return min(d1, min(d2, d3));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Parameters
  let glowIntensity = mix(0.8, 2.5, u.zoom_params.x);
  let shardSize = mix(24.0, 64.0, u.zoom_params.y);
  let latticeScale = mix(5.0, 12.0, u.zoom_params.z) + mids * 2.0;
  let sparkDensity = u.zoom_params.w;

  // ── Read previous shatter state ──
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var disp = prev.rg;
  var seed = prev.b;
  var reform = prev.a;

  // ── Shard assignment (rigid grid) ──
  let cellPx = shardSize;
  let cellId = floor(vec2<f32>(gid.xy) / cellPx);
  let cellCenter = (cellId * cellPx + cellPx * 0.5) / resolution;

  // Deterministic shard seed (branchless write-once)
  let h = fract(sin(dot(cellId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  seed = select(seed, h, reform > 0.99);

  // ── State machine ──
  let wasSolid = reform > 0.9;
  let newShatter = mouseDown > 0.5 && wasSolid;

  // Explosion vector from mouse
  let toCell = cellCenter - mouseUV;
  let distMouse = length(toCell);
  let dir = toCell / max(distMouse, 1e-4);
  let falloff = exp(-distMouse * 4.0) * (1.0 + bass * 0.6);
  let force = falloff * (0.08 + seed * 0.06);

  // Per-shard rotation of explosion
  let angle = seed * 6.283185;
  let ca = cos(angle); let sa = sin(angle);
  let rotDir = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);
  let explodeVec = rotDir * force;

  // Apply impulse only on transition
  disp = select(disp, explodeVec, vec2<bool>(newShatter, newShatter));

  // Reform: exponential decay with per-shard stagger
  let doReform = mouseDown < 0.5 && reform < 1.0;
  let decay = select(1.0, 0.987 + seed * 0.005, doReform);
  disp = disp * decay;

  // Reform tracker
  reform = select(reform, 0.0, newShatter);
  let reformRate = 0.012 + seed * 0.005;
  reform = select(reform, min(1.0, reform + reformRate), doReform);

  let shatterAmt = 1.0 - reform;

  // ── Backward-mapped UV for crystal sampling ──
  var sampleUV = uv - disp;

  // Per-shard rotation during shatter
  let rotAngle = seed * shatterAmt * 0.4;
  let ca2 = cos(rotAngle); let sa2 = sin(rotAngle);
  let toSample = sampleUV - cellCenter;
  let rotSample = vec2<f32>(toSample.x * ca2 - toSample.y * sa2, toSample.x * sa2 + toSample.y * ca2);
  sampleUV = cellCenter + rotSample;

  // ── Ember color palette ──
  let EMBER_CORE = vec3<f32>(1.00, 0.98, 0.90);
  let EMBER_HOT = vec3<f32>(1.00, 0.55, 0.08);
  let EMBER_DEEP = vec3<f32>(0.85, 0.18, 0.03);
  let EMBER_DARK = vec3<f32>(0.25, 0.04, 0.01);
  let EMBER_CHARCOAL = vec3<f32>(0.02, 0.01, 0.01);

  // ── Crystal lattice rendering ──
  let scale = latticeScale * (1.0 + sin(time * 0.3) * 0.1);
  let p = sampleUV * scale;

  // Triangular lattice distance
  let dist = triLatticeDist(p);

  // Edge glow (hot edges, cool centers)
  let edgeRaw = 1.0 - smoothstep(0.0, 0.06, dist);
  let edge = edgeRaw * edgeRaw;

  // Cell hash for face variation
  let cellHash = hash21(floor(p));
  let faceBright = 0.2 + cellHash * 0.3 + sin(time * 0.4 + cellHash * 8.0) * 0.08;

  // Ember coloring
  let hot = edge * glowIntensity * (1.0 + bass * 1.5);
  var col = mix(EMBER_CHARCOAL, EMBER_DARK, faceBright);
  col = mix(col, EMBER_DEEP, hot * 0.7);
  col = mix(col, EMBER_HOT, hot * hot * 0.8);
  col = mix(col, EMBER_CORE, pow(hot, 4.0) * 2.5);

  // ── Shatter visual flair ──
  // Shard boundary glow
  let localCoord = fract(vec2<f32>(gid.xy) / cellPx) - 0.5;
  let nearEdgeX = 1.0 - smoothstep(0.42, 0.5, abs(localCoord.x));
  let nearEdgeY = 1.0 - smoothstep(0.42, 0.5, abs(localCoord.y));
  let boundaryGlow = max(nearEdgeX, nearEdgeY) * shatterAmt * 0.5;
  col = col + vec3<f32>(0.95, 0.9, 1.0) * boundaryGlow;

  // Chromatic separation during shatter
  let sep = shatterAmt * 0.006;
  let cr = mix(EMBER_CHARCOAL, EMBER_DEEP, faceBright);
  let crR = mix(cr, EMBER_HOT, (1.0 - smoothstep(0.0, 0.06, triLatticeDist((sampleUV + vec2<f32>(sep, 0.0)) * scale))) * glowIntensity * (1.0 + bass * 1.5) * 0.7);
  let crB = mix(cr, EMBER_HOT, (1.0 - smoothstep(0.0, 0.06, triLatticeDist((sampleUV - vec2<f32>(sep, 0.0)) * scale))) * glowIntensity * (1.0 + bass * 1.5) * 0.7);
  col.r = mix(col.r, crR.r, shatterAmt * 0.5);
  col.b = mix(col.b, crB.b, shatterAmt * 0.5);

  // Motion streak based on displacement
  let speed = length(disp) * 30.0;
  col = col * (1.0 + speed * shatterAmt * 0.3);

  // ── Treble sparks at shard edges ──
  let sparkNoise = hash12(cellId * 137.0 + fract(time * 20.0));
  let sparkThreshold = treble * sparkDensity * 0.4;
  let spark = f32(sparkNoise < sparkThreshold) * boundaryGlow;
  col = col + EMBER_CORE * spark * 3.0;

  // ── Temporal ember persistence ──
  let prevGlow = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let persist = mix(col, prevGlow, 0.92);
  col = col + persist * 0.25;

  // ── Depth + compositing ──
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  // Semantic alpha
  let presence = clamp(length(col) * 1.2, 0.0, 1.0);
  let alpha = clamp(presence * (0.6 + depth * 0.25) + edge * 0.2, 0.15, 0.9);

  // Chromatic aberration
  let caStr = 0.0025 * (1.0 + bass) + depth * 0.001 + shatterAmt * 0.002;
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ACES tone mapping
  col = acesToneMap(col * 1.1);

  // Composite with input
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let finalColor = mix(inputColor.rgb, col, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  // ── Output ──
  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth * (0.4 + edge * 0.6), 0.0, 0.0, 0.0));
  // State: RG=displacement, B=seed, A=reform
  textureStore(dataTextureA, coord, vec4<f32>(disp, seed, reform));
}
