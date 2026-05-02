// ═══════════════════════════════════════════════════════════════════
//  Phosphor Decay (HDR Upgrade)
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgrades: ACES tone mapping, split-tone grading, atmospheric
//            depth haze, chromatic aberration, audio-reactive beam
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

fn to_linear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3(2.2));
}

fn to_srgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3(1.0 / 2.2));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn color_temp(t: f32) -> vec3<f32> {
  return mix(vec3(1.0, 0.72, 0.52), vec3(0.52, 0.72, 1.0), t);
}

fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
  let d = length(uv - 0.5);
  return pow(max(0.0, 1.0 - d * 2.0), strength);
}

fn chromatic_aberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
  let offset = (uv - 0.5) * amount;
  let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0).b;
  return vec3(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  // Parameters
  let decayRate = mix(0.75, 0.995, u.zoom_params.x);
  let baseIntensity = mix(0.0, 4.0, u.zoom_params.y);
  let mouseRadius = mix(0.005, 0.25, u.zoom_params.z);
  let colorTemp = u.zoom_params.w;

  // Audio reactivity from plasmaBuffer
  var audioBoost = 0.0;
  if (arrayLength(&plasmaBuffer) > 0u) {
    audioBoost = plasmaBuffer[0].x * 2.5;
  }
  let beamIntensity = baseIntensity * (1.0 + audioBoost);

  // Sample history in linear
  let histSample = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var history = to_linear(histSample.rgb);

  // Current input with chromatic aberration for CRT soul
  let inputRGB = chromatic_aberration(uv, 0.003 * colorTemp);
  let inputColor = to_linear(inputRGB);

  // Mouse-driven electron beam
  let mouse = u.zoom_config.yz;
  let mouseDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
  let beamFalloff = smoothstep(mouseRadius, 0.0, mouseDist);
  let beamHue = color_temp(colorTemp);
  let beam = beamHue * beamFalloff * beamIntensity;

  // Decay history with split-tone color grading
  var decayed = history * decayRate;
  let lum = dot(decayed, vec3(0.299, 0.587, 0.114));
  let shadowTint = mix(vec3(1.0, 0.82, 0.65), vec3(0.65, 0.82, 1.0), colorTemp);
  let highlightTint = mix(vec3(1.0, 0.92, 0.78), vec3(0.78, 0.92, 1.0), 1.0 - colorTemp);
  decayed = decayed * mix(shadowTint, highlightTint, lum);

  // HDR phosphor persistence: max composition in linear space
  var merged = max(inputColor + beam, decayed);

  // Atmospheric depth haze using depth texture
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let hazeColor = color_temp(colorTemp * 0.5 + 0.25) * 0.12;
  merged = mix(merged, hazeColor, depth * colorTemp * 0.35);

  // Subtle animated caustics for living atmosphere
  let caustic = sin(uv.x * 20.0 + time) * cos(uv.y * 20.0 - time * 0.7) * 0.5 + 0.5;
  merged = merged + hazeColor * caustic * 0.02 * colorTemp;

  // Vignette for CRT tube atmosphere
  let vig = vignette(uv, 1.2 + colorTemp * 0.5);
  merged = merged * vig;

  // ACES tone mapping + gamma encode
  var finalRGB = aces_tone_map(merged);
  finalRGB = to_srgb(finalRGB);

  let finalColor = vec4<f32>(finalRGB, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
