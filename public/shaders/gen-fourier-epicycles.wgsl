// ═══════════════════════════════════════════════════════════════════
//  Fourier Epicycles - Harmonic rotating wheels tracing curves
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, temporal, mouse-driven, feedback-loop
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-06-07
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

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn wheelColor(n: f32, total: f32) -> vec3<f32> {
  let t = n / total;
  let red = vec3<f32>(1.0, 0.12, 0.05);
  let orange = vec3<f32>(1.0, 0.45, 0.0);
  let green = vec3<f32>(0.08, 0.85, 0.25);
  let blue = vec3<f32>(0.08, 0.25, 1.0);
  if (t < 0.33) { return mix(red, orange, t * 3.0); }
  if (t < 0.66) { return mix(orange, green, (t - 0.33) * 3.0); }
  return mix(green, blue, (t - 0.66) * 3.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  let prevState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bassEnv = bass_env(prevState.r, bass, 0.8, 0.15);

  let speed = (0.25 + bassEnv * 0.6) * (1.0 + u.zoom_params.x * 2.0);
  let nCycles = 3 + i32(u.zoom_params.y * 9.0);
  let rimIntensity = 0.3 + u.zoom_params.z * 0.7;
  let trailPersist = mix(0.5, 0.92, u.zoom_params.w);

  let aspect = resolution.x / max(resolution.y, 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Video chromatic distortion from readTexture
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(inputColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let chromaShift = (inputColor.rg - 0.5) * 0.04 * luma;
  p = p + chromaShift;

  // Mouse gravity well warps system center
  let mousePos = (mouseUV - 0.5) * 2.0;
  var mouseAspect = mousePos;
  mouseAspect.x = mouseAspect.x * aspect;
  let toMouse = mouseAspect - p;
  let mouseDist = length(toMouse);
  let gravity = toMouse * 0.04 / (mouseDist * mouseDist * mouseDist + 0.001);
  p = p - gravity * (1.0 + mouseDown);

  // Click shockwave ripple
  let clickDist = length(p - mouseAspect);
  let shockWave = mouseDown * exp(-clickDist * clickDist * 40.0) * sin(clickDist * 25.0 - time * 5.0);

  var center = vec2<f32>(0.0);
  var accum = vec3<f32>(0.0);

  for (var i: i32 = 1; i <= 12; i = i + 1) {
    if (i > nCycles) { break; }
    let fi = f32(i);
    let seed = hash12(vec2<f32>(fi * 17.31, fi * 43.17));
    let radius = (0.35 / fi) * (0.6 + seed * 0.8) * (1.0 + bassEnv * 0.3);
    let freq = fi * speed * (1.0 + mids * 0.15);
    let phase = seed * 6.28318 + time * freq + mouseAspect.x * fi * 1.5;
    let nextCenter = center + vec2<f32>(cos(phase), sin(phase)) * radius;

    let toPixel = p - center;
    let dist = length(toPixel);
    let rimDist = abs(dist - radius + shockWave * 0.02);
    let wCol = wheelColor(fi - 1.0, f32(nCycles));

    let rimGlow = rimIntensity * 0.015 / (rimDist * rimDist + 0.0003);
    accum = accum + wCol * rimGlow;

    let spokeDist = length(p - nextCenter);
    accum = accum + wCol * 0.004 / (spokeDist * spokeDist + 0.00015);

    let centerDist = length(p - center);
    accum = accum + vec3<f32>(0.9, 0.85, 0.8) * 0.003 / (centerDist * centerDist + 0.0001);

    center = nextCenter;
  }
  let penPos = center;

  let penDist = length(p - penPos);
  let penGlow = 0.012 / (penDist * penDist + 0.00025);
  let penBloom = 0.003 / (penDist * penDist + 0.001);
  var chroma = vec3<f32>(1.0, 0.92, 0.78) * penGlow;
  chroma = chroma + vec3<f32>(0.7, 0.8, 1.0) * penBloom;

  // Treble sparkle
  let sparkle = hash12(uv * resolution + fract(time * 18.0) * 250.0);
  let trebleSpark = step(0.96 - treble * 0.1, sparkle) * treble;

  var generatedColor = vec3<f32>(0.008, 0.008, 0.015);
  generatedColor = generatedColor + accum;
  generatedColor = generatedColor + chroma;
  let caStr = 0.003 * (1.0 + bassEnv);
  generatedColor = vec3<f32>(generatedColor.r + caStr, generatedColor.g, generatedColor.b - caStr * 0.5);
  generatedColor = generatedColor + vec3<f32>(0.9, 0.95, 1.0) * trebleSpark;

  // Temporal feedback with motion-blur decay
  let decayed = vec3<f32>(prevState.g, prevState.b, prevState.g * 0.5 + prevState.b * 0.5) * trailPersist * (1.0 - mids * 0.05);
  let newTrail = max(decayed, generatedColor * 0.85);
  generatedColor = max(generatedColor, decayed * 0.6);

  generatedColor = acesToneMapping(generatedColor * (1.2 + bassEnv * 0.3));

  let vignette = 1.0 - length(uv - 0.5) * 0.6;
  generatedColor = generatedColor * vignette;

  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.4, 1.0, inputDepth);

  let lumaOut = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
  let presence = smoothstep(0.03, 0.25, lumaOut);
  let interaction = presence + mouseDown * 0.3 + trebleSpark * 2.0;
  let alpha = presence * depth * (0.7 + bassEnv * 0.35 + treble * 0.2);

  let finalColor = mix(inputColor.rgb, generatedColor, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(lumaOut * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(bassEnv, newTrail.r, newTrail.g, alpha));
}
