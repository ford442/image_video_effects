// Graphic Novel — adaptive ink contours, rotated print screens, and paper grain.
// Public id "graphic-novel" intentionally aliases this underscore filename.
// A/C stores ACES display RGBA. B is unused.

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

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.73, 289.11))) * 43758.5453);
}

fn screenDot(pixel: vec2<f32>, angle: f32, frequency: f32, coverage: f32) -> f32 {
  let c = cos(angle);
  let s = sin(angle);
  let rotated = mat2x2<f32>(c, -s, s, c) * pixel / frequency;
  let local = fract(rotated) - 0.5;
  let radius = sqrt(clamp(coverage, 0.0, 1.0)) * 0.55;
  return 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(local));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = vec2<f32>(1.0) / resolution;
  let pixel = vec2<f32>(gid.xy);
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let dotScale = 2.0 + u.zoom_params.x * 13.0;
  let edgeStrength = 0.45 + u.zoom_params.y * 2.8;
  let levels = 3.0 + floor(u.zoom_params.z * 9.0);
  let paperAmount = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lumL = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumR = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumT = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumB = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let gradient = vec2<f32>(lumR - lumL, lumB - lumT);
  let gradientMagnitude = length(gradient);
  let localContrast = abs(lumR - lumL) + abs(lumB - lumT);
  let adaptiveThreshold = (0.018 + (1.0 - u.zoom_params.y) * 0.14) * (1.0 + luma(source.rgb) * 0.4);
  let contour = smoothstep(adaptiveThreshold, adaptiveThreshold * 2.4 + 0.002, gradientMagnitude + localContrast * 0.35);

  let mouseDelta = (uv - mouse) * aspectVec;
  let mouseDistance = length(mouseDelta);
  let focus = exp(-mouseDistance * mouseDistance * 18.0);
  let heldInk = select(0.0, exp(-mouseDistance * mouseDistance * 95.0), held);
  var ringInk = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.25 + audio.y * 0.035);
      ringInk += exp(-abs(rd - front) * 55.0) * exp(-age * 1.25);
    }
  }

  let registration = gradient / max(gradientMagnitude, 0.0001) * (0.0006 + audio.z * 0.0016);
  let cyan = textureSampleLevel(readTexture, u_sampler, clamp(uv + registration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).gb;
  let magenta = textureSampleLevel(readTexture, u_sampler, clamp(uv - registration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rb;
  var poster = floor(clamp(vec3<f32>(magenta.x, cyan.x, cyan.y), vec3<f32>(0.0), vec3<f32>(1.0)) * levels + 0.5) / levels;
  let tone = 1.0 - luma(poster);
  let dotC = screenDot(pixel, 0.2618, dotScale, clamp(1.0 - poster.r, 0.0, 1.0));
  let dotM = screenDot(pixel, 1.309, dotScale, clamp(1.0 - poster.g, 0.0, 1.0));
  let dotK = screenDot(pixel, 0.7854, dotScale * 0.86, tone);
  let printMask = clamp(dotC * 0.3 + dotM * 0.3 + dotK * 0.65, 0.0, 1.0);

  let fiberA = hash21(floor(pixel * vec2<f32>(0.5, 0.12)));
  let fiberB = hash21(floor(pixel.yx * vec2<f32>(0.23, 0.72)) + 17.0);
  let fibers = (fiberA - 0.5) * 0.07 + (fiberB - 0.5) * 0.045;
  let paper = vec3<f32>(0.93, 0.89, 0.78) * (1.0 + fibers * paperAmount);
  let inkColor = vec3<f32>(0.018, 0.022, 0.035) + vec3<f32>(0.02, 0.008, 0.0) * audio.x;
  let emphasis = clamp(contour * edgeStrength + heldInk * 0.9 + ringInk * 0.7, 0.0, 1.0);
  var hdr = mix(paper, poster * (0.72 + 0.28 * (1.0 - paperAmount)), 0.62 + 0.18 * (1.0 - tone));
  hdr = mix(hdr, inkColor, clamp(printMask * (0.42 + paperAmount * 0.28) + emphasis, 0.0, 1.0));
  hdr += vec3<f32>(0.12, 0.035, 0.015) * (dotM - dotC) * (0.15 + audio.z * 0.12);

  let history = historyAt(uv - gradient * (0.2 + heldInk) * texel, resolution);
  let historyMix = clamp(0.025 + paperAmount * 0.035 + ringInk * 0.025, 0.0, 0.1);
  let display = mix(aces(max(hdr, vec3<f32>(0.0))), history.rgb, historyMix);
  let alpha = clamp(0.12 + printMask * 0.48 + contour * 0.38 + heldInk * 0.22 + ringInk * 0.18, 0.0, 1.0);
  let result = vec4<f32>(display, alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(alpha, 0.0, 0.0, 0.0));
}
