// ═══════════════════════════════════════════════════════════════════
//  mouse-time-crystal
//  Category: interactive-mouse
//  Features: mouse-driven, temporal, crystal-growth
//  Complexity: Very High
//  Chunks From: chunk-library.md (hash12, palette)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse clicks seed crystal growth points. Crystals grow over time
//  using diffusion-limited aggregation modulated by image luminance.
//  Crystal branches follow the image's natural gradients. Uses
//  dataTextureC for persistent crystal state.
//  Alpha = crystal color temperature (age gradient).
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let growthRate = mix(0.3, 1.5, u.zoom_params.x);
  let crystalDensity = mix(0.5, 3.0, u.zoom_params.y);
  let ageColorSpeed = mix(0.1, 1.0, u.zoom_params.z);
  let glowIntensity = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;

  // Read previous crystal state (R=age, G=branchID, B=density, A=temperature)
  let prevState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var crystalAge = prevState.r;
  var branchID = prevState.g;
  var density = prevState.b;
  var temperature = prevState.a;

  // Sample image for growth modulation
  let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(imageColor);

  // Growth probability based on image edges (luminance variation)
  let px = 1.0 / resolution;
  let right = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb);
  let up = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb);
  let gradient = abs(luma - right) + abs(luma - up);

  // Seed new crystals from ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 5.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let seedRadius = 0.03 * smoothstep(0.0, 0.5, elapsed);
      if (rDist < seedRadius && crystalAge < 0.01) {
        crystalAge = elapsed;
        branchID = f32(i) + 1.0;
        density = 1.0;
        temperature = 1.0;
      }
    }
  }

  // Crystal growth: DLA-like expansion from existing crystals
  if (crystalAge > 0.0) {
    crystalAge = crystalAge + 0.016 * growthRate;
    temperature = temperature * 0.995;

    // Diffuse density to neighbors (simulate aggregation)
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0);
    let s = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0);
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0);
    let w = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0);

    // If neighbor is crystallized and we're not, chance to crystallize
    let neighborAge = max(max(n.r, s.r), max(e.r, w.r));
    let neighborBranch = select(n.g, s.g, s.r > n.r);
    let neighborDensity = max(max(n.b, s.b), max(e.b, w.b));

    if (crystalAge < 0.1 && neighborAge > 0.1) {
      let growthProb = gradient * crystalDensity * 0.5 + hash12(uv * 100.0 + time) * 0.3;
      if (growthProb > 0.4) {
        crystalAge = neighborAge;
        branchID = neighborBranch;
        density = neighborDensity * 0.95 + gradient;
        temperature = 1.0;
      }
    }

    density = min(density * 1.001, 3.0);
  }

  // Color based on crystal age and branch
  let ageColor = palette(
    fract(branchID * 0.1 + crystalAge * ageColorSpeed * 0.1),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 0.8),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  // Mix with base image
  let crystalMask = smoothstep(0.0, 0.05, crystalAge);
  var finalColor = mix(imageColor, ageColor * (0.5 + luma), crystalMask * 0.8);

  // Temperature glow
  let tempGlow = temperature * glowIntensity * crystalMask;
  finalColor = finalColor + vec3<f32>(0.8, 0.6, 0.4) * tempGlow;

  // Mouse proximity accelerates nearby crystal growth visually
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseHeat = exp(-mouseDist * mouseDist * 200.0) * 0.2;
  finalColor = finalColor + vec3<f32>(1.0, 0.9, 0.7) * mouseHeat * crystalMask;

  // Store crystal state
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(crystalAge, branchID, density, temperature));

  // Alpha = crystal color temperature (maps to warm/cool)
  let alpha = clamp(temperature * 0.5 + crystalMask * 0.5, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
