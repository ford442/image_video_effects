// ═══════════════════════════════════════════════════════════════════
//  Ethereal Silk Veil
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Description: Multi-layered translucent silk ribbons flowing in an
//  ethereal wind. Audio drives undulation amplitude; mouse gathers and
//  disturbs the fabric like a hand through cloth. Gold-cream palette
//  with depth-layered parallax and fabric sheen.
//  Created: 2026-06-06
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Parameters
  let flowSpeed = mix(0.3, 1.2, u.zoom_params.x);
  let waveIntensity = mix(0.02, 0.08, u.zoom_params.y) * (1.0 + bass * 0.4);
  let layerDensity = mix(4.0, 10.0, u.zoom_params.z);
  let sheenAmount = u.zoom_params.w;

  // Temporal smoothness
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Mouse gather effect: fabric pulls toward mouse with Gaussian falloff
  let toMouse = mouseUV - uv;
  let mouseDist = length(toMouse);
  let gatherStrength = exp(-mouseDist * mouseDist * 8.0) * (mouseDown * 3.0 + 0.5);

  // Silk palette (gold-cream-ivory)
  let silkBase = vec3<f32>(0.98, 0.94, 0.82);
  let silkShadow = vec3<f32>(0.75, 0.60, 0.35);
  let silkHighlight = vec3<f32>(1.0, 0.97, 0.90);
  let goldSheen = vec3<f32>(1.0, 0.85, 0.45);

  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedAlpha = 0.0;

  let numLayers = i32(layerDensity);

  for (var li: i32 = 0; li < numLayers; li = li + 1) {
    let layerDepth = f32(li) / f32(numLayers - 1); // 0=back, 1=front

    // Each ribbon has a base x-position
    let ribbonPhase = f32(li) * 1.618 + hash12(vec2<f32>(f32(li), 7.0)) * 2.0;
    let baseX = (sin(ribbonPhase) * 0.3 + 0.5);

    // Wind-driven sine undulation
    let freq = 3.0 + f32(li) * 0.7 + mids * 2.0;
    let speed = flowSpeed * (1.0 + f32(li) * 0.15);
    let wave = sin(uv.y * freq + time * speed + ribbonPhase) * waveIntensity;

    // Secondary higher-frequency ripple
    let ripple = sin(uv.y * freq * 2.5 + time * speed * 1.3 + ribbonPhase * 2.0) * waveIntensity * 0.3;

    // Mouse gather shifts ribbon toward mouse
    let gatherX = baseX + wave + ripple - toMouse.x * gatherStrength * (0.5 + layerDepth * 0.5);

    // Ribbon width varies with layer (front layers wider)
    let ribbonWidth = mix(0.04, 0.12, layerDepth) * (1.0 + bass * 0.1);

    // Distance from this pixel to the ribbon center
    let distToRibbon = abs(uv.x - gatherX);

    // Soft ribbon edge with audio-driven flutter
    let flutter = noise2(vec2<f32>(uv.y * 10.0 + time * 2.0, f32(li))) * 0.02 * (1.0 + treble);
    let ribbonMask = smoothstep(ribbonWidth + flutter, 0.0, distToRibbon);

    // Fabric fold darkness (derivative of wave gives fold depth)
    let foldDepth = cos(uv.y * freq + time * speed + ribbonPhase) * 0.5 + 0.5;
    let foldShadow = mix(silkShadow, silkBase, foldDepth);

    // Depth darkening: back layers are darker and more blue-shifted
    let depthDarken = mix(0.35, 1.0, layerDepth);
    var layerColor = foldShadow * depthDarken;

    // Sheen on fold peaks (where derivative crosses zero going up)
    let sheenMask = pow(smoothstep(0.4, 0.6, foldDepth), 3.0) * sheenAmount;
    layerColor = mix(layerColor, goldSheen, sheenMask * (0.5 + bass * 0.3));

    // Layer alpha: front layers more opaque
    let layerAlpha = ribbonMask * mix(0.25, 0.75, layerDepth) * (0.8 + mids * 0.2);

    // Front-to-back compositing
    accumulatedColor = mix(accumulatedColor, layerColor, layerAlpha * (1.0 - accumulatedAlpha));
    accumulatedAlpha = accumulatedAlpha + layerAlpha * (1.0 - accumulatedAlpha);
  }

  // Background: deep dark void with subtle warmth
  let bgColor = vec3<f32>(0.04, 0.03, 0.02);
  var color = mix(bgColor, accumulatedColor, accumulatedAlpha);

  // Subtle vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.4;
  color = color * vignette;

  // Depth pass-through for compositing
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  // Chromatic aberration
  let caStr = 0.002 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // ACES tone mapping
  color = acesToneMap(color * 1.15);

  // Temporal smoothness blend
  let smoothColor = mix(prev.rgb, color, 0.25 + bass * 0.05);

  // Semantic alpha
  let presence = clamp(length(smoothColor) * 1.5, 0.0, 1.0);
  let alpha = clamp(presence * (0.7 + depth * 0.2), 0.2, 0.9);

  let finalColor = mix(
    textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb,
    smoothColor,
    alpha
  );
  let finalAlpha = max(
    textureSampleLevel(readTexture, u_sampler, uv, 0.0).a,
    alpha
  );

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth * (0.5 + accumulatedAlpha * 0.5), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(smoothColor, alpha));
}
