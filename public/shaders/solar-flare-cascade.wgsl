// ═══════════════════════════════════════════════════════════════════
//  Solar Flare Cascade
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal,
//            chromatic-dispersion, depth-aware, stellar-simulation
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
// ═══════════════════════════════════════════════════════════════════
//  Solar prominence and flare cascades erupting from a stellar limb.
//  Bass drives flare intensity, mids create magnetic loop structures,
//  treble adds coronal mass ejection particles. Mouse shifts the limb.
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

fn noise3(p: vec3<f32>) -> f32 {
  var i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
        mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), f.x), f.y),
    mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
        mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), f.x), f.y),
    f.z
  );
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i++) {
    value += amplitude * noise3(p * freq);
    amplitude *= 0.5;
    freq *= 2.0;
  }
  return value;
}

fn smoothstepf32(edge0: f32, edge1: f32, x: f32) -> f32 {
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
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

  let flareIntensity = mix(0.3, 2.5, u.zoom_params.x);
  let loopComplexity = mix(1.0, 6.0, u.zoom_params.y);
  let particleDensity = mix(0.0, 1.0, u.zoom_params.z);
  let coronaSpread = mix(0.5, 3.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Stellar limb position shifted by mouse
  let limbX = mouse.x * 0.6;
  let limbY = mouse.y * 0.3;
  let limbCenter = vec2<f32>(limbX, limbY);

  // Distance from stellar surface
  let distFromLimb = length(p - limbCenter);
  let surfaceRadius = 0.35;
  let aboveSurface = distFromLimb - surfaceRadius;

  // ═══ Magnetic Loop Structures (driven by mids) ═══
  var loopField = 0.0;
  let loopCount = u32(loopComplexity);
  for (var i = 0u; i < loopCount; i = i + 1u) {
    let fi = f32(i);
    let loopAngle = fi * 2.39996 + time * 0.1 * (1.0 + mids * 0.5);
    let loopBase = limbCenter + vec2<f32>(
      cos(loopAngle) * surfaceRadius,
      sin(loopAngle) * surfaceRadius
    );
    let loopHeight = 0.2 + mids * 0.4 + sin(time * 0.3 + fi) * 0.1;
    let loopArc = p - loopBase;
    let loopDist = abs(length(loopArc) - loopHeight * 0.5);
    let loopWidth = 0.015 + mids * 0.01;
    let loopStr = smoothstepf32(loopWidth, 0.0, loopDist);
    loopField = max(loopField, loopStr * (0.6 + mids * 0.4));
  }

  // ═══ Flare Cascades (driven by bass) ═══
  var flareField = 0.0;
  let flareCount = 5u;
  for (var i = 0u; i < flareCount; i = i + 1u) {
    let fi = f32(i);
    let flareAngle = fi * 1.2566 + sin(time * 0.2 + fi * 3.0) * 0.3;
    let flareDir = vec2<f32>(cos(flareAngle), sin(flareAngle));
    let flareOrigin = limbCenter + flareDir * surfaceRadius * 0.98;
    let toP = p - flareOrigin;
    let alongFlare = dot(toP, flareDir);
    let acrossFlare = length(toP - flareDir * alongFlare);
    let flareLength = 0.3 + bass * 0.5 + sin(time * 2.0 + fi) * 0.1;
    let flareProfile = smoothstepf32(flareLength, 0.0, alongFlare) *
                       smoothstepf32(0.0, flareLength * 0.3, alongFlare);
    let flareWidth = 0.02 + bass * 0.02;
    let flareShape = flareProfile * smoothstepf32(flareWidth, 0.0, acrossFlare);
    let flarePulse = 1.0 + bass * sin(time * 4.0 + fi * 2.0) * 0.5;
    flareField = max(flareField, flareShape * flarePulse);
  }

  // ═══ Coronal Mass Ejection Particles (driven by treble) ═══
  var particleField = 0.0;
  let particleCount = u32(mix(0.0, 30.0, particleDensity + treble * 0.5));
  for (var i = 0u; i < particleCount; i = i + 1u) {
    let fi = f32(i);
    let pAngle = fi * 2.7 + time * 0.15;
    let pDist = surfaceRadius + fi * 0.015 + treble * 0.2 +
                sin(time * 1.5 + fi * 0.7) * 0.05;
    let pPos = limbCenter + vec2<f32>(cos(pAngle), sin(pAngle)) * pDist;
    let pDistToPixel = length(p - pPos);
    let pSize = 0.008 + treble * 0.005;
    let pStr = smoothstepf32(pSize, 0.0, pDistToPixel);
    particleField = max(particleField, pStr * (0.5 + treble * 0.5));
  }

  // ═══ Corona Glow ═══
  let coronaNoise = fbm3(vec3<f32>(p * 3.0, time * 0.15), 3);
  let coronaBase = smoothstepf32(coronaSpread * 0.3, -0.1, aboveSurface);
  let corona = coronaBase * (0.3 + coronaNoise * 0.4) * (1.0 + bass * 0.3);

  // ═══ Chromatic Dispersion per Element ═══
  // Red channel offset for corona, green for loops, blue for particles
  let coronaR = smoothstepf32(coronaSpread * 0.35, -0.05, aboveSurface + 0.02) *
                (0.4 + coronaNoise * 0.5) * (1.0 + bass * 0.3);
  let coronaG = corona * 0.85;
  let coronaB = smoothstepf32(coronaSpread * 0.25, -0.15, aboveSurface - 0.02) *
                (0.2 + coronaNoise * 0.3);

  let loopR = loopField * 0.7;
  let loopG = loopField * 0.9;
  let loopB = loopField * 1.1;

  let flareR = flareField * 1.2;
  let flareG = flareField * 0.85;
  let flareB = flareField * 0.6;

  let particleR = particleField * 0.9;
  let particleG = particleField * 0.95;
  let particleB = particleField * 1.15;

  // Combine with chromatic offsets
  var color = vec3<f32>(0.0);
  color += vec3<f32>(coronaR, coronaG, coronaB) * flareIntensity * 0.6;
  color += vec3<f32>(loopR, loopG, loopB) * flareIntensity * 0.9;
  color += vec3<f32>(flareR, flareG, flareB) * flareIntensity * 1.2;
  color += vec3<f32>(particleR, particleG, particleB) * flareIntensity * 0.8;

  // Solar core glow
  let coreGlow = smoothstepf32(surfaceRadius + 0.05, surfaceRadius - 0.1, distFromLimb);
  color += vec3<f32>(1.0, 0.9, 0.7) * coreGlow * (0.8 + bass * 0.4);

  // ═══ Temporal Feedback ═══
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let feedbackAmount = 0.04 + bass * 0.015;
  color = mix(color, prev.rgb * 0.92, feedbackAmount);

  // ═══ Semantic Alpha ═══
  let presence = max(max(loopField, flareField), max(coronaBase, particleField));
  let alpha = clamp(0.05 + presence * flareIntensity * 0.95, 0.0, 1.0);

  // Depth: surface is near, distant corona is far
  let depth = clamp(0.95 - presence * 0.6 - coreGlow * 0.3, 0.0, 1.0);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
