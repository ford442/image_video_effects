// ═══════════════════════════════════════════════════════════════════
//  Neon Echo
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, depth-aware, phosphor-halation, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn luminance(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn sampleColor(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleHistory(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;

  if (t <= 6600.0) {
    r = 1.0;
    g = 0.39008157 * log(tt) - 0.63184144;
    if (t < 2000.0) {
      b = 0.0;
    } else {
      b = 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408;
    }
  } else {
    r = 1.29293618 * pow(tt - 60.0, -0.1332047592);
    g = 1.12989086 * pow(tt - 60.0, -0.0755148492);
    b = 1.0;
  }

  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let dt = 1.0 / 60.0;

  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let current = sampleColor(uv);
  let lumL = luminance(sampleColor(uv - vec2<f32>(texel.x, 0.0)).rgb);
  let lumR = luminance(sampleColor(uv + vec2<f32>(texel.x, 0.0)).rgb);
  let lumT = luminance(sampleColor(uv - vec2<f32>(0.0, texel.y)).rgb);
  let lumB = luminance(sampleColor(uv + vec2<f32>(0.0, texel.y)).rgb);
  let depthL = sampleDepth(uv - vec2<f32>(texel.x, 0.0));
  let depthR = sampleDepth(uv + vec2<f32>(texel.x, 0.0));
  let depthT = sampleDepth(uv - vec2<f32>(0.0, texel.y));
  let depthB = sampleDepth(uv + vec2<f32>(0.0, texel.y));

  let colorEdge = length(vec2<f32>(lumR - lumL, lumB - lumT));
  let depthEdge = length(vec2<f32>(depthR - depthL, depthB - depthT));
  let edgeSignal = colorEdge * 1.2 + depthEdge * 1.6;

  let drift = (mouse - uv) * u.zoom_params.y * 0.015 * (0.35 + 0.65 * mouseDown);
  let prevUV = clamp(uv + drift, vec2<f32>(0.0), vec2<f32>(1.0));
  let prevPersistence = sampleHistory(prevUV).rgb;

  let halationOffset = texel * mix(1.0, 6.0, u.zoom_params.w);
  let halation = (
    sampleHistory(prevUV + vec2<f32>(halationOffset.x, 0.0)).rgb +
    sampleHistory(prevUV - vec2<f32>(halationOffset.x, 0.0)).rgb +
    sampleHistory(prevUV + vec2<f32>(0.0, halationOffset.y)).rgb +
    sampleHistory(prevUV - vec2<f32>(0.0, halationOffset.y)).rgb
  ) * 0.25;

  let heatedTauScale = mix(1.0, 0.55, bass);
  let tauR = 0.016 * heatedTauScale;
  let tauG = 0.060 * heatedTauScale;
  let tauB = 0.026 * heatedTauScale;
  let decay = vec3<f32>(exp(-dt / tauR), exp(-dt / tauG), exp(-dt / tauB));

  let decayed = max(prevPersistence, halation * 0.35) * decay;
  let threshold = mix(0.02, 0.45, u.zoom_params.z);
  let gain = mix(0.5, 2.6, u.zoom_params.x);
  let injectionStrength = max(luminance(current.rgb) + edgeSignal * 1.4 - threshold, 0.0) * gain;
  let freshInput = mix(current.rgb, vec3<f32>(1.0), 0.45 + 0.2 * bass) * injectionStrength * (1.0 + bass * 0.5);

  let updatedPersistence = min(decayed + freshInput, vec3<f32>(1.35));
  let persistenceLuma = luminance(updatedPersistence);
  let temperature = mix(1200.0, 9500.0 + 2500.0 * bass, clamp(persistenceLuma * 1.15 + injectionStrength * 0.6, 0.0, 1.0));
  let spectralTint = blackbodyRGB(temperature);

  var displayColor = updatedPersistence * spectralTint;
  displayColor.g = displayColor.g + updatedPersistence.b * 0.12 * (0.6 + 0.4 * treble);

  let bloom = halation * spectralTint * (0.15 + 0.65 * u.zoom_params.w) * smoothstep(0.08, 0.9, persistenceLuma);
  let scanFlicker = 0.96 + 0.04 * sin((uv.y * resolution.y + time * 240.0) * (1.0 + treble * 6.0));
  displayColor = displayColor * scanFlicker + bloom;

  let finalAlpha = mix(current.a, 1.0, injectionStrength * 0.7);
  let depth = sampleDepth(uv);

  textureStore(dataTextureA, coord, vec4<f32>(updatedPersistence, finalAlpha));
  textureStore(writeTexture, coord, vec4<f32>(displayColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 0.0));
}
