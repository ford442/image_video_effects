// ═══════════════════════════════════════════════════════════════════
//  Hybrid Spectral Sorting
//  Category: distortion
//  Features: hybrid, pixel-sorting, spectral-analysis, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-09
//  Ideas: band-length interval; honest three-band plasma audio
//  A packing: ACES display RGBA
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn rgb2luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let sortThreshold = mix(0.1, 0.5, u.zoom_params.x);
  let spectralBands = mix(4.0, 32.0, u.zoom_params.y);
  let displacement = mix(0.0, 0.2, u.zoom_params.z);
  let hueShiftAmount = u.zoom_params.w * 3.14159;

  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.3, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 30.0 - time * 6.0) * exp(-distToMouse * 4.0);

  let band = floor(uv.y * spectralBands);
  let bandPhase = band / max(spectralBands, 1.0);
  let bandTop = (band + 1.0) / max(spectralBands, 1.0);
  let spectralNoise = fbm2(vec2<f32>(bandPhase * 10.0, time * 0.5), 3);
  // Idea 2 — honest three-band audio (not zoom_config.x).
  let bandEnergy = spectralNoise * (0.5 + bass * 0.35 + mids * 0.25 + treble * 0.15);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let currentLuma = rgb2luma(current);

  // Idea 1 — band-length interval: walk Y inside this spectral band, keep brightest.
  var best = current;
  var bestL = currentLuma;
  var inBand = 0.0;
  let stepY = 1.0 / max(resolution.y, 1.0);
  for (var i = 1; i <= 8; i = i + 1) {
    let ny = uv.y + f32(i) * stepY * (2.0 + bandEnergy * 6.0);
    if (ny >= bandTop || ny > 1.0) { break; }
    let nCol = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, ny), 0.0).rgb;
    let nL = rgb2luma(nCol);
    if (abs(nL - currentLuma) < sortThreshold) { break; }
    inBand = 1.0;
    if (nL > bestL) {
      bestL = nL;
      best = nCol;
    }
  }

  let displacementVec = vec2<f32>(
    sin(bandPhase * 6.28318 + time) * bandEnergy,
    cos(bandPhase * 6.28318 + time * 0.7) * bandEnergy
  ) * displacement * (1.0 + mouseGravity * 2.0) + normalize(uv - mousePos + vec2<f32>(0.001)) * clickPulse * 0.05;
  let displacedUV = clamp(uv + displacementVec * (1.0 + bass * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  var color = select(displaced, mix(current, best, 0.7), inBand > 0.5 && bestL > currentLuma);
  let spectralColor = palette(bandPhase + time * 0.1,
    vec3<f32>(0.5),
    vec3<f32>(0.5),
    vec3<f32>(1.0, 1.0, 0.5),
    vec3<f32>(0.0, 0.33, 0.67)
  );
  color = mix(color, color * spectralColor, bandEnergy * 0.5);
  color = hueShift(color, hueShiftAmount * bandPhase + mids * 0.5);
  color += spectralColor * (bandEnergy * bass * 0.5 + mouseGravity * 0.3);

  let beat = step(0.7, bass);
  let glitchOffset = vec2<f32>(hash12(uv + time) - 0.5, 0.0) * 0.02 * beat;
  let glitchColor = textureSampleLevel(readTexture, u_sampler, clamp(uv + glitchOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  color = mix(color, glitchColor, 0.3 * beat);

  let luma = rgb2luma(color);
  let alpha = clamp(mix(0.7, 1.0, luma + bandEnergy * 0.3) + inBand * 0.1, 0.0, 1.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outCol = vec4<f32>(acesToneMap(color), alpha);
  textureStore(writeTexture, id, outCol);
  textureStore(dataTextureA, id, outCol);
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - bandEnergy * 0.2), 0.0, 0.0, 0.0));
}
