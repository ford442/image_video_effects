// ═══════════════════════════════════════════════════════════════════
//  Phosphor Decay (Batch D Upgrade)
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgrades: per-channel phosphor decay, CRT shadow mask, scan-line
//            blanking, color bloom, luminance-key alpha
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  // Parameters
  let decayRateParam = u.zoom_params.x;
  let bloomSpread = u.zoom_params.y;
  let shadowMaskStrength = u.zoom_params.z;
  let scanBlanking = u.zoom_params.w;

  // Per-channel phosphor decay rates (R fastest, B slowest)
  let decayR = 0.95 - decayRateParam * 0.1;
  let decayG = 0.96 - decayRateParam * 0.1;
  let decayB = 0.98 - decayRateParam * 0.05;

  // Audio reactivity: bass drives bloom burst, mids modulates shadow mask, treble adds scan flicker
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bloomBurst = 1.0 + bass * 2.0;
  let shadowMaskMod = shadowMaskStrength * (1.0 + mids * 0.6);
  let scanBlankMod = scanBlanking * (1.0 + treble * 0.4);

  // Sample history in linear
  let histSample = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var history = to_linear(histSample.rgb);

  // Apply per-channel decay
  history.r = history.r * decayR;
  history.g = history.g * decayG;
  history.b = history.b * decayB;

  // Current input with chromatic aberration
  let inputRGB = chromatic_aberration(uv, 0.003);
  let inputColor = to_linear(inputRGB);

  // Bloom: sample neighbors and blur
  let spread = bloomSpread * 0.02 * bloomBurst;
  var bloom = vec3(0.0);
  bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv + vec2(spread, 0.0), 0.0).rgb) * 0.25;
  bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv - vec2(spread, 0.0), 0.0).rgb) * 0.25;
  bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, spread), 0.0).rgb) * 0.25;
  bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, spread), 0.0).rgb) * 0.25;

  // Extract high-luma pixels for bloom addition
  let inputLuma = dot(inputColor, vec3(0.299, 0.587, 0.114));
  let bloomAdd = bloom * smoothstep(0.5, 1.0, inputLuma) * bloomSpread * bloomBurst;

  // Merge input + bloom with decayed history
  var merged = max(inputColor + bloomAdd, history);

  // CRT shadow mask (RGB dot pattern)
  let px = vec2<f32>(global_id.xy);
  let maskX = i32(px.x) % 3;
  var mask = vec3(1.0);
  if (maskX == 0) { mask = vec3(1.0, 0.6, 0.6); }
  else if (maskX == 1) { mask = vec3(0.6, 1.0, 0.6); }
  else { mask = vec3(0.6, 0.6, 1.0); }
  merged = mix(merged, merged * mask, shadowMaskMod * 0.5);

  // Scan-line blanking
  let scanLine = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
  let blanking = mix(1.0, scanLine, scanBlankMod * 0.4);
  merged = merged * blanking;

  // Depth-based atmospheric haze
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let hazeColor = vec3(0.08, 0.06, 0.04) * 1.5;
  merged = mix(merged, hazeColor, depth * 0.25);

  // Vignette for CRT tube atmosphere
  let vig = vignette(uv, 1.2);
  merged = merged * vig;

  // ACES tone mapping + gamma encode
  var finalRGB = aces_tone_map(merged);
  finalRGB = to_srgb(finalRGB);

  // Luminance-key alpha
  let alpha = dot(finalRGB, vec3(0.299, 0.587, 0.114));
  let finalColor = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
