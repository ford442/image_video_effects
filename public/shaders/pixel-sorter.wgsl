// ═══════════════════════════════════════════════════════════════════
//  Pixel Sorter
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: Asendorf interval close; span-seam accent
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

const PHI: f32 = 1.61803398874989484820;

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3<f32>(r, g, b) * intensity, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn get_luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn get_hue(c: vec3<f32>) -> f32 {
  let mx = max(c.r, max(c.g, c.b));
  let mn = min(c.r, min(c.g, c.b));
  let d = mx - mn + 1e-5;
  var h: f32 = 0.0;
  if (mx == c.r) { h = (c.g - c.b) / d; }
  else if (mx == c.g) { h = 2.0 + (c.b - c.r) / d; }
  else { h = 4.0 + (c.r - c.g) / d; }
  return fract(h / 6.0);
}

fn goldNoise(uv: vec2<f32>, seed: f32) -> f32 {
  let d = distance(uv * PHI, uv) * (seed + 1e-3);
  return fract(sin(d) * uv.x * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let direction = u.zoom_params.x;
  let reverse = u.zoom_params.y;
  let intensityScale = u.zoom_params.z;
  let threshold = clamp(u.zoom_params.w, 0.0, 1.0);

  // Prev-mouse is a 1-frame delay in extraBuffer[133..134], not a spring.
  var prevMouse = mouse;
  let hasState = arrayLength(&extraBuffer) > 138u;
  if (hasState && extraBuffer[138] > 0.5) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (coord.x == 0 && coord.y == 0 && hasState) {
    extraBuffer[133] = mouse.x;
    extraBuffer[134] = mouse.y;
    extraBuffer[138] = 1.0;
  }
  let mouseVel = (mouse - prevMouse) * 60.0;
  let mouseSpeed = clamp(length(mouseVel), 0.0, 2.0);

  var sortAxis = vec2<f32>(0.0, 1.0);
  if (direction > 0.7) {
    sortAxis = vec2<f32>(1.0, 0.0);
  } else if (direction > 0.3) {
    let v = mouseVel + vec2<f32>(1e-4);
    sortAxis = normalize(v);
  }

  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = get_luma(c.rgb);
  let hue = get_hue(c.rgb);
  let hueShift = (hue - 0.5);

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dMouse = length(distVec);
  let cursorMask = exp(-dMouse * dMouse * 8.0);
  let mouseGate = mix(1.0, mouseDown * 1.5 + cursorMask, smoothstep(0.0, 0.3, dMouse));
  let intensity = intensityScale * (1.0 + bass * 0.5 + mouseSpeed * 0.4);
  let signMul = mix(-1.0, 1.0, reverse) + hueShift * 0.3;
  let walkDir = sortAxis * signMul;
  let stride = (0.004 + intensity * 0.012) * mouseGate;

  // Idea 1 — Asendorf interval close: walk until luma drops below threshold.
  var bestColor = c.rgb;
  var bestLuma = luma;
  var inRun = luma > threshold;
  var steps = 0.0;
  var closed = 0.0;
  if (inRun) {
    for (var i = 1; i <= 10; i = i + 1) {
      let fi = f32(i);
      let sUV = clamp(uv + walkDir * (fi * stride), vec2<f32>(0.0), vec2<f32>(1.0));
      let sCol = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
      let sLum = get_luma(sCol);
      if (sLum < threshold) {
        closed = 1.0;
        break;
      }
      steps = fi;
      if (sLum > bestLuma) {
        bestLuma = sLum;
        bestColor = sCol;
      }
    }
  }

  // Idea 2 — span-seam: this sample is in-interval, the next along the axis is not.
  let nextUV = clamp(uv + walkDir * stride, vec2<f32>(0.0), vec2<f32>(1.0));
  let nextLum = get_luma(textureSampleLevel(readTexture, u_sampler, nextUV, 0.0).rgb);
  let seam = f32(inRun) * f32(nextLum < threshold);

  let nx = goldNoise(uv * 7.0 + vec2<f32>(time * 0.3, 0.0), 1.0) - 0.5;
  let ny = goldNoise(uv * 7.0 + vec2<f32>(0.0, time * 0.3), 2.0) - 0.5;
  let curl = vec2<f32>(ny, -nx) * 0.015 * mouseGate;
  let sampleUV = clamp(uv + walkDir * steps * stride + curl, vec2<f32>(0.0), vec2<f32>(1.0));
  let walked = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let sampled = mix(c.rgb, mix(walked, bestColor, 0.65), f32(inRun) * mouseGate);

  let histDims = vec2<i32>(textureDimensions(dataTextureC));
  let prevPixel = textureLoad(dataTextureC, historyCoord(uv, histDims), 0).rgb;
  let blend = clamp(0.55 + mouseSpeed * 0.3, 0.5, 0.95);
  let tempColor = mix(prevPixel, sampled, blend);

  let sortLength = steps * stride;
  let wavelength = mix(420.0, 700.0, clamp(sortLength * 8.0 + hue, 0.0, 1.0));
  let spectralTint = wavelengthToRGB(wavelength);
  let tintedColor = mix(tempColor, tempColor * spectralTint, sortLength * 2.0);
  let shimmerBoost = 1.0 + bass * 0.3 * sin(uv.y * 20.0 + time * 4.0);
  let shimmerColor = tintedColor * shimmerBoost;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.5, 1.0, 1.0 - depth * 0.6);
  var finalColor = mix(tempColor, shimmerColor, depthFactor);
  finalColor = finalColor + vec3<f32>(0.12, 0.11, 0.09) * seam * (0.55 + treble * 0.45);
  finalColor = finalColor * (1.0 + closed * mids * 0.04);

  let dispMag = sortLength;
  let alpha = clamp(get_luma(finalColor) * 0.4 + dispMag * 6.0 + cursorMask * 0.3 + tentAlpha(dispMag * 4.0) * 0.2 + seam * 0.2, 0.0, 1.0);
  let softMask = gaussianMask(dMouse, 0.35);
  let maskedAlpha = alpha * mix(0.6, 1.0, softMask);
  let vignette = 1.0 - smoothstep(0.3, 1.0, length(uv - vec2<f32>(0.5)) * 1.1);
  let acesRGB = acesToneMap(finalColor * mix(0.92, 1.0, vignette));
  let outCol = vec4<f32>(acesRGB, maskedAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
