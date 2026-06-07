// ═══════════════════════════════════════════════════════════════════
//  Neon Fern Garden
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal,
//            chromatic-dispersion, organic-growth, depth-aware
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
// ═══════════════════════════════════════════════════════════════════
//  Procedurally generated fern fronds unfurling in neon colors against
//  dark soil. Bass drives growth animation, mids control frond density,
//  treble creates dewdrop sparkles. Mouse attracts or repels frond tips.
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

// Barnsley fern approximator for organic frond shape
fn fernFrond(p: vec2<f32>, base: vec2<f32>, angle: f32, scale: f32,
             time: f32, bass: f32, mouse: vec2<f32>, attract: f32) -> vec4<f32> {
  let tip = base + vec2<f32>(cos(angle), sin(angle)) * scale;

  // Mouse attraction/repulsion on tip
  let tipToMouse = mouse - tip;
  let tipDist = length(tipToMouse);
  let tipInfluence = smoothstepf32(0.5, 0.0, tipDist);
  let tipOffset = normalize(tipToMouse) * tipInfluence * attract * 0.15;
  let bentTip = tip + tipOffset;

  // Bend the frond with growth (bass-driven)
  let growth = 0.6 + bass * 0.4;
  let bend = sin(time * 0.5) * 0.08 * growth;
  let mid = mix(base, bentTip, 0.5) + vec2<f32>(cos(angle + 1.57), sin(angle + 1.57)) * bend;

  // Quadratic bezier approximation distance
  var d = 999.0;
  let segs = 8u;
  var prevPt = base;
  for (var i = 1u; i <= segs; i = i + 1u) {
    let t = f32(i) / f32(segs);
    let oneMinusT = 1.0 - t;
    let pt = base * (oneMinusT * oneMinusT) +
             mid * (2.0 * oneMinusT * t) +
             bentTip * (t * t);
    d = min(d, sdSegment(p, prevPt, pt));
    prevPt = pt;
  }

  let frondWidth = 0.012 * scale * (1.0 + growth * 0.3);
  let frondStr = smoothstepf32(frondWidth, 0.0, d);

  if (frondStr < 0.001) {
    return vec4<f32>(0.0);
  }

  // Leaflets along the frond
  var leafletStr = 0.0;
  let leafletCount = u32(mix(6.0, 18.0, growth));
  for (var i = 0u; i < leafletCount; i = i + 1u) {
    let lt = (f32(i) + 0.5) / f32(leafletCount);
    let lOneMinusT = 1.0 - lt;
    let lPos = base * (lOneMinusT * lOneMinusT) +
               mid * (2.0 * lOneMinusT * lt) +
               bentTip * (lt * lt);
    let lDir = normalize(bentTip - base);
    let lPerp = vec2<f32>(-lDir.y, lDir.x);
    let lSize = 0.04 * scale * sin(lt * 3.14159) * growth;
    let lTip = lPos + lPerp * lSize * select(-1.0, 1.0, (i % 2u) == 0u);
    let ld = sdSegment(p, lPos, lTip);
    leafletStr = max(leafletStr, smoothstepf32(lSize * 0.15, 0.0, ld));
  }

  // Chromatic: neon magenta core, green mid, cyan edge
  let core = smoothstepf32(frondWidth * 0.4, 0.0, d);
  let edge = smoothstepf32(frondWidth, frondWidth * 0.5, d);
  let r = core * 0.9 + edge * 0.3 + leafletStr * 0.5;
  let g = core * 0.2 + edge * 0.8 + leafletStr * 0.9;
  let b = core * 0.5 + edge * 1.0 + leafletStr * 0.7;

  return vec4<f32>(r, g, b, max(frondStr, leafletStr * 0.7));
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
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let growthSpeed = mix(0.2, 1.5, u.zoom_params.x);
  let frondDensity = mix(3.0, 12.0, u.zoom_params.y);
  let dewAmount = mix(0.0, 1.0, u.zoom_params.z);
  let mouseInfluence = mix(-1.0, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Dark soil background with subtle grain
  let soilNoise = noise2(p * 8.0 + vec2<f32>(time * 0.02, 0.0));
  var color = vec3<f32>(0.03, 0.04, 0.02) + vec3<f32>(0.01, 0.008, 0.005) * soilNoise;

  // ═══ Fern Fronds (driven by bass growth, mids density) ═══
  var frondColor = vec4<f32>(0.0);
  let fernCount = u32(frondDensity);
  let growthPhase = fract(time * growthSpeed * 0.1);

  for (var i = 0u; i < fernCount; i = i + 1u) {
    let fi = f32(i);
    let fernAngle = fi * 2.5 + sin(time * 0.1 + fi) * 0.2;
    let fernBase = vec2<f32>(
      sin(fi * 1.3) * 0.4,
      -0.85 + sin(fi * 0.7) * 0.05
    );
    let fernScale = 0.5 + sin(fi * 2.1 + time * 0.15) * 0.15 +
                    bass * 0.1 * sin(time * 2.0 + fi);
    let fern = fernFrond(p, fernBase, fernAngle, fernScale,
                         time, bass, mouse, mouseInfluence);
    frondColor = max(frondColor, fern);
  }

  // ═══ Chromatic Dispersion: offset R/G/B samples for glow ═══
  let glowSpread = 0.012 + bass * 0.005;
  let rOff = vec2<f32>(glowSpread, glowSpread * 0.3);
  let gOff = vec2<f32>(-glowSpread * 0.5, glowSpread);
  let bOff = vec2<f32>(glowSpread * 0.3, -glowSpread * 0.7);

  var glowR = 0.0;
  var glowG = 0.0;
  var glowB = 0.0;

  for (var i = 0u; i < fernCount; i = i + 1u) {
    let fi = f32(i);
    let fernAngle = fi * 2.5 + sin(time * 0.1 + fi) * 0.2;
    let fernBase = vec2<f32>(
      sin(fi * 1.3) * 0.4,
      -0.85 + sin(fi * 0.7) * 0.05
    );
    let fernScale = 0.5 + sin(fi * 2.1 + time * 0.15) * 0.15 +
                    bass * 0.1 * sin(time * 2.0 + fi);
    let frR = fernFrond(p + rOff, fernBase, fernAngle, fernScale,
                        time, bass, mouse, mouseInfluence);
    let frG = fernFrond(p + gOff, fernBase, fernAngle, fernScale,
                        time, bass, mouse, mouseInfluence);
    let frB = fernFrond(p + bOff, fernBase, fernAngle, fernScale,
                        time, bass, mouse, mouseInfluence);
    glowR = max(glowR, frR.r * frR.a);
    glowG = max(glowG, frG.g * frG.a);
    glowB = max(glowB, frB.b * frB.a);
  }

  color += vec3<f32>(glowR, glowG, glowB) * 0.4;
  color += frondColor.rgb * frondColor.a;

  // ═══ Dewdrop Sparkles (driven by treble) ═══
  var dew = 0.0;
  let dewCount = u32(mix(0.0, 25.0, dewAmount + treble * 0.5));
  for (var i = 0u; i < dewCount; i = i + 1u) {
    let fi = f32(i);
    let dewBase = vec2<f32>(
      sin(fi * 3.1 + time * 0.05) * 0.45,
      -0.3 + sin(fi * 1.9) * 0.5
    );
    // Dew follows nearest frond tip approximately
    let dewDist = length(p - dewBase);
    let dewSize = 0.006 + treble * 0.003;
    let dewTwinkle = sin(time * 4.0 + fi * 3.7) * 0.5 + 0.5;
    dew = max(dew, smoothstepf32(dewSize, 0.0, dewDist) * dewTwinkle);
  }

  // Dew with chromatic highlight: cyan center, white hot
  color += vec3<f32>(0.4, 0.9, 1.0) * dew * (0.6 + treble * 0.6);

  // ═══ Temporal Feedback ═══
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let feedbackAmount = 0.025 + bass * 0.008;
  color = mix(color, prev.rgb * 0.93, feedbackAmount);

  // ═══ Semantic Alpha ═══
  let presence = frondColor.a + dew * 0.6;
  let alpha = clamp(0.06 + presence * 0.94, 0.0, 1.0);

  // Depth: fronds near bottom are closer (foreground)
  let depthY = smoothstepf32(-1.0, 1.0, p.y);
  let depth = clamp(0.2 + depthY * 0.5 + frondColor.a * 0.3, 0.0, 1.0);

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
