// ═══════════════════════════════════════════════════════════════════
//  viscous-drag-bilateral
//  Category: advanced-hybrid
//  Features: viscous-drag, bilateral-filter, mouse-driven, ripple-shockwaves
//  Complexity: High
//  Chunks From: viscous-drag.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Dragging through viscous liquid while applying bilateral filtering
//  that sharpens near the mouse and ripples, and dreamy-smoothes
//  elsewhere. Hue shift adds psychedelic liquid color flow.
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

// ═══ CHUNK: rgb2hsv + hsv2rgb (from conv-bilateral-dream.wgsl) ═══
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
  var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  var d = q.x - min(q.w, q.y);
  let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
  return vec3<f32>(h, d, q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - 3.0);
  return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;

  let viscosity = mix(0.1, 0.9, u.zoom_params.x);
  let colorSigma = mix(0.05, 1.0, u.zoom_params.y);
  let hueShiftAmt = u.zoom_params.z;
  let dragStrength = mix(0.1, 2.0, u.zoom_params.w);

  // === VISCOUS DRAG OFFSET FIELD (from viscous-drag) ===
  let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let prevOffset = prevData.xy;

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uv_aspect, mouse_aspect);
  let radius = 0.15;

  var force = vec2<f32>(0.0);
  if (dist < radius && dist > 0.001) {
    var dir = normalize(uv_aspect - mouse_aspect);
    let strength = (1.0 - dist / radius) * dragStrength;
    force = dir * strength * 0.01;
  }

  let texel = 1.0 / resolution;
  let up = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).xy;
  let down = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).xy;
  let left = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).xy;
  let right = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).xy;
  let avg = (up + down + left + right) * 0.25;

  let diffusedOffset = mix(prevOffset, avg, viscosity);
  var newOffset = diffusedOffset * mix(0.9, 0.995, viscosity) + force;
  newOffset = clamp(newOffset, vec2<f32>(-0.5), vec2<f32>(0.5));

  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newOffset, 0.0, 1.0));

  // === BILATERAL DREAM FILTER (from conv-bilateral-dream) ===
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseInfluence = u.zoom_params.w;

  // Mouse distance modulation
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
  let spatialSigmaBase = mix(0.1, 1.0, viscosity);
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

  // Ripple shockwaves
  var rippleSharpness = 0.0;
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rPos = ripple.xy;
    let rStart = ripple.z;
    let rElapsed = time - rStart;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length(uv - rPos);
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
      rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
    }
  }
  let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

  // Apply viscous offset to sample UV
  let scale = mix(0.01, 0.2, dragStrength);
  let sampleUV = uv - newOffset * scale;

  // Bilateral filter core
  let center = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let radius = i32(ceil(finalSigma * 2.5));
  let maxRadius = min(radius, 7);

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV + offset, 0.0);

      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));

      let colorDist = length(neighbor.rgb - center.rgb);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));

      let weight = spatialWeight * rangeWeight;
      accumColor += neighbor.rgb * weight;
      accumWeight += weight;
    }
  }

  var result = vec3<f32>(0.0);
  if (accumWeight > 0.001) {
    result = accumColor / accumWeight;
  } else {
    result = center.rgb;
  }

  // Psychedelic hue shift
  if (hueShiftAmt > 0.0) {
    let hsv = rgb2hsv(result);
    let newHue = fract(hsv.x + hueShiftAmt + mouseDist * 0.3 + time * 0.05);
    result = hsv2rgb(vec3<f32>(newHue, hsv.y, hsv.z));
  }

  // Specular highlight from viscous drag
  let normal = normalize(vec3<f32>(newOffset.x, newOffset.y, 0.01));
  let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
  let specular = pow(max(dot(normal, lightDir), 0.0), 20.0) * length(newOffset) * 2.0;
  let finalColor = result + vec3<f32>(specular);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, accumWeight));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
