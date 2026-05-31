// ═══════════════════════════════════════════════════════════════════
//  Crystalline Veins
//  Category: generative
//  Features: audio-reactive, temporal-feedback, chromatic-dispersion,
//            fbm-veins, mineral-growth, mouse-attraction
//  Complexity: High
//  Created: 2026-05-30
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
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
  var pos = p;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * noise2(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a = a * 0.5;
  }
  return v;
}

fn fbmDomainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm2(p + vec2<f32>(0.0, 0.0), 3),
    fbm2(p + vec2<f32>(5.2, 1.3), 3)
  );
  let r = vec2<f32>(
    fbm2(p + 3.0 * q + vec2<f32>(1.7 + time * 0.05, 9.2), 3),
    fbm2(p + 3.0 * q + vec2<f32>(8.3, 2.8 + time * 0.03), 3)
  );
  return p + 1.5 * r;
}

// Crack/vein generation using FBM ridges
fn veinNoise(p: vec2<f32>, time: f32, density: f32) -> f32 {
  let warped = fbmDomainWarp(p * density, time);
  let n1 = fbm2(warped + vec2<f32>(time * 0.02, 0.0), 5);
  let n2 = fbm2(warped * 1.5 + vec2<f32>(0.0, time * 0.015), 4);
  let ridge1 = 1.0 - abs(n1 - 0.5) * 2.0;
  let ridge2 = 1.0 - abs(n2 - 0.5) * 2.0;
  let combined = max(ridge1 * 0.7, ridge2 * 0.5);
  return pow(combined, 2.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  let veinDensity = mix(1.5, 5.0, u.zoom_params.x);
  let glowIntensity = u.zoom_params.y;
  let growthSpeed = u.zoom_params.z;
  let mineralShift = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0);

  // Mouse attracts vein growth
  let mouseUV = mouse * 0.5 + 0.5;
  let mouseUVAspect = mouseUV * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseUVAspect);
  let mouseAttraction = exp(-mouseDist * mouseDist * 4.0) * 0.6;

  // Growth phase evolves over time, modulated by growthSpeed
  let growthPhase = fract(time * 0.03 * (0.5 + growthSpeed * 1.5));
  let growthMask = smoothstep(0.0, 0.4, growthPhase);

  // Base vein pattern
  let veins = veinNoise(p, time, veinDensity);
  let attractedVeins = veinNoise(p + normalize(p - mouseUVAspect + vec2<f32>(0.001)) * mouseAttraction, time, veinDensity);
  let mixedVeins = mix(veins, attractedVeins, mouseAttraction * 2.0);

  // Growth threshold: veins "grow" over time
  let growthThreshold = 0.3 + growthMask * 0.5;
  let veinMask = smoothstep(growthThreshold, growthThreshold - 0.15, mixedVeins);
  let thinVeins = smoothstep(growthThreshold + 0.1, growthThreshold, mixedVeins) * (1.0 - veinMask);

  // Bass drives vein pulse
  let pulse = 1.0 + bass * sin(time * 4.0 + mixedVeins * 20.0) * 0.4;

  // Mids control growth density via secondary pattern
  let densityPattern = fbm2(p * 3.0 + vec2<f32>(time * 0.01), 4);
  let densityMod = 1.0 + mids * densityPattern;

  // Mineral types: gold, copper, silver based on cell hash
  let cellHash = hash22(floor(p * veinDensity * 2.0));
  let mineralType = fract(cellHash.x + mineralShift * 0.5);

  // Gold veins
  let goldColor = vec3<f32>(1.0, 0.84, 0.0);
  // Copper veins
  let copperColor = vec3<f32>(0.72, 0.45, 0.2);
  // Silver veins
  let silverColor = vec3<f32>(0.75, 0.75, 0.8);

  let mineralColor = mix(
    mix(goldColor, copperColor, smoothstep(0.33, 0.66, mineralType)),
    silverColor,
    smoothstep(0.66, 1.0, mineralType)
  );

  // Chromatic dispersion: R/G/B offsets for each mineral type
  let caStrength = 0.012 * (1.0 + treble);
  let rOffset = vec2<f32>(caStrength * sin(mineralType * 6.28), caStrength * cos(mineralType * 6.28));
  let gOffset = vec2<f32>(-caStrength * 0.7, caStrength * 0.5);
  let bOffset = vec2<f32>(caStrength * 0.3, -caStrength * 0.8);

  let veinR = veinNoise(p + rOffset, time, veinDensity);
  let veinG = veinNoise(p + gOffset, time, veinDensity);
  let veinB = veinNoise(p + bOffset, time, veinDensity);

  let maskR = smoothstep(growthThreshold, growthThreshold - 0.15, veinR) * densityMod;
  let maskG = smoothstep(growthThreshold, growthThreshold - 0.15, veinG) * densityMod;
  let maskB = smoothstep(growthThreshold, growthThreshold - 0.15, veinB) * densityMod;

  let chromaVein = vec3<f32>(maskR, maskG, maskB) * mineralColor * pulse;

  // Dark stone background
  let stoneNoise = fbm2(p * 6.0, 5);
  let stoneColor = vec3<f32>(0.06, 0.055, 0.05) * (0.8 + stoneNoise * 0.4);

  // Vein glow halo
  let glow = smoothstep(growthThreshold + 0.08, growthThreshold - 0.05, mixedVeins) * glowIntensity * (0.3 + bass * 0.4);
  let glowColor = mineralColor * glow;

  // Treble adds crystalline sparkles
  let sparkleNoise = hash31(vec3<f32>(floor(p * veinDensity * 4.0), fract(time * 12.0)));
  let sparkle = step(1.0 - 0.08 * treble, sparkleNoise) * veinMask * treble * 2.5;
  let sparkleColor = vec3<f32>(1.0, 0.98, 0.95) * sparkle;

  // Thin vein filaments
  let filamentColor = mineralColor * thinVeins * 0.4 * pulse;

  var color = stoneColor + chromaVein + glowColor + sparkleColor + filamentColor;

  // Temporal feedback: trailing glow from previous frame
  let feedbackColor = prev.rgb * 0.85;
  let feedbackMask = smoothstep(0.1, 0.5, prev.a) * 0.3;
  color = mix(color, feedbackColor + glowColor * 0.5, feedbackMask);

  // Semantic alpha: based on vein presence + glow + sparkles
  let alpha = clamp(veinMask * 0.9 + glow * 0.5 + sparkle * 0.4 + thinVeins * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(veinMask * 0.6 + glow * 0.3 + sparkle * 0.2, 0.0, 0.0, 0.0));
}
