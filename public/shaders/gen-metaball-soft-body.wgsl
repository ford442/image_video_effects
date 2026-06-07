// ═══════════════════════════════════════════════════════════════════
//  Metaball Soft Body - Organic liquid-metal implicit surfaces
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

fn fieldAt(p: vec2<f32>, time: f32, bassEnv: f32, mouseUV: vec2<f32>, mouseDown: f32, nBalls: i32) -> f32 {
  var f = 0.0;
  let mousePos = (mouseUV - 0.5) * 2.0;
  for (var i: i32 = 0; i < 6; i = i + 1) {
    if (i >= nBalls) { break; }
    let fi = f32(i);
    let seed = fi * 17.31;
    let orbitR = 0.2 + hash12(vec2<f32>(seed, 0.0)) * 0.25;
    let spd = 0.25 + hash12(vec2<f32>(seed, 1.0)) * 0.4 + bassEnv * 0.2;
    let phase = seed * 0.7 + time * spd;
    let cx = cos(phase) * orbitR + cos(time * 0.13 + fi) * 0.08;
    let cy = sin(phase * 0.83 + 1.3) * orbitR + sin(time * 0.11 + fi) * 0.08;
    let pos = vec2<f32>(cx, cy);
    let toMouse = mousePos - pos;
    let dist2 = dot(toMouse, toMouse) + 0.001;
    let grav = normalize(toMouse) * 0.06 / dist2;
    let mPos = pos + grav * (1.0 + mouseDown * 3.0);
    let r = 0.1 + hash12(vec2<f32>(seed, 2.0)) * 0.06 + bassEnv * 0.04;
    let d2 = dot(p - mPos, p - mPos);
    f = f + (r * r) / (d2 + 0.00005);
  }
  return f;
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

  let nBalls = 3 + i32(u.zoom_params.x * 3.0);
  let roughness = u.zoom_params.y;
  let metalShift = u.zoom_params.z;
  let causticStr = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Video luma-keyed optical-flow distortion
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(inputColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let flow = (inputColor.rg - 0.5) * 0.05 * luma;
  p = p + flow;

  // Mouse click shockwave
  let mousePos = (mouseUV - 0.5) * 2.0;
  var mouseAspect = mousePos;
  mouseAspect.x = mouseAspect.x * aspect;
  let clickDist = length(p - mouseAspect);
  let shockWave = mouseDown * exp(-clickDist * clickDist * 60.0) * sin(clickDist * 30.0 - time * 6.0);

  let dx = 0.003;
  let f = fieldAt(p, time, bassEnv, mouseUV, mouseDown, nBalls);
  let fx = fieldAt(p + vec2<f32>(dx, 0.0), time, bassEnv, mouseUV, mouseDown, nBalls);
  let fy = fieldAt(p + vec2<f32>(0.0, dx), time, bassEnv, mouseUV, mouseDown, nBalls);

  let grad = vec2<f32>(fx - f, fy - f) / dx;
  let gradLen = length(grad);
  let normal = grad / max(gradLen, 0.001);
  let view = normalize(vec2<f32>(0.0, 0.0) - p);
  let fresnel = pow(1.0 - max(dot(normal, view), 0.0), 3.0);

  let surfaceDist = abs(f - 1.0);
  let surfaceMask = 1.0 - smoothstep(0.0, 0.15 + shockWave * 0.08, surfaceDist);
  let insideMask = step(1.0, f);

  let lightDir = normalize(vec2<f32>(0.5, 0.8));
  let spec = pow(max(dot(normal, normalize(lightDir + view)), 0.0), mix(32.0, 8.0, roughness));

  let baseMetal = mix(vec3<f32>(0.75, 0.78, 0.82), vec3<f32>(0.9, 0.7, 0.4), metalShift);
  let subSurf = vec3<f32>(0.9, 0.4, 0.2) * insideMask * 0.4;

  let caustic = vec3<f32>(0.2, 0.6, 1.0) * gradLen * causticStr * 0.15;
  let mergeGlow = vec3<f32>(1.0, 0.8, 0.5) * max(f - 1.5, 0.0) * 0.3;

  // Treble sparkle on surface
  let sparkle = hash12(uv * resolution + fract(time * 12.0) * 200.0);
  let trebleSpark = step(0.96 - treble * 0.1, sparkle) * treble * surfaceMask;

  var generatedColor = vec3<f32>(0.01, 0.01, 0.015);
  generatedColor = generatedColor + baseMetal * surfaceMask * 0.6;
  generatedColor = generatedColor + vec3<f32>(1.0, 0.95, 0.9) * spec * surfaceMask;
  generatedColor = generatedColor + baseMetal * fresnel * surfaceMask * 0.5;
  generatedColor = generatedColor + subSurf;
  generatedColor = generatedColor + caustic;
  generatedColor = generatedColor + mergeGlow;
  generatedColor = generatedColor + vec3<f32>(0.9, 0.95, 1.0) * trebleSpark;

  generatedColor = acesToneMapping(generatedColor * (1.4 + bassEnv * 0.5));

  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  // Temporal feedback trail
  let trailCol = vec3<f32>(prevState.g, prevState.b, prevState.g * 0.5 + prevState.b * 0.5);
  let trail = mix(trailCol * 0.88, generatedColor, 0.12 + mouseDown * 0.1);
  generatedColor = max(generatedColor, trail * 0.55);

  let fieldAlpha = clamp(f * surfaceMask * 0.5 + surfaceMask * 0.3 + trebleSpark, 0.0, 0.95) * depth;
  let interaction = surfaceMask + mouseDown * 0.4 + trebleSpark * 2.0;
  let alpha = fieldAlpha * (1.0 + fresnel * 0.3) * (0.8 + interaction * 0.25);

  let finalColor = mix(inputColor.rgb, generatedColor, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(surfaceMask * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(bassEnv, generatedColor.r, generatedColor.g, alpha));
}
