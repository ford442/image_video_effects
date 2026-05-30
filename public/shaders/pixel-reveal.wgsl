// ═══════════════════════════════════════════════════════════════════
//  Pixel Reveal v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: pixel-reveal
//  Created: 2026-05-10
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / resolution;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let pixelSizeParam = u.zoom_params.x;
  let radius = u.zoom_params.y * 0.5;
  let softness = max(u.zoom_params.z * 0.2, 0.001);
  let decayRate = u.zoom_params.w;

  // Depth-driven pixel size perspective
  let depthBlock = mix(0.5, 1.5, depth);
  let stepBase = max(0.002, pixelSizeParam * 0.08 * depthBlock);
  let stepX = stepBase;
  let stepY = stepBase * (resolution.x / resolution.y);

  // Bass-driven threshold oscillation
  let threshold = 0.3 + bass * 0.25 + sin(time * 3.0) * 0.1;

  // Pixelate UV with glitch jitter
  let jitter = vec2<f32>(
    (treble * 0.015) * sin(uv.y * 60.0 + time * 12.0),
    (treble * 0.015) * cos(uv.x * 60.0 + time * 12.0)
  );
  let pixelatedUV = clamp(vec2<f32>(
    floor(uv.x / stepX) * stepX + stepX * 0.5 + jitter.x,
    floor(uv.y / stepY) * stepY + stepY * 0.5 + jitter.y
  ), vec2<f32>(0.001), vec2<f32>(0.999));

  // Mouse reveal mask (painted radius)
  let aspect = resolution.x / max(resolution.y, 1.0);
  let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let revealMask = smoothstep(radius, radius + softness, dist);
  let paintedMask = select(revealMask, 1.0 - revealMask, mouseDown);

  // Temporal noise accumulation for decay
  let noise = hash3(vec3<f32>(uv * 30.0, fract(time * 0.5))).x;
  let temporalDecay = fract(noise + time * decayRate * 0.5) * (1.0 - paintedMask);

  // Pixel sorting threshold: only reveal pixels above luminance threshold
  let pxColor = textureSampleLevel(readTexture, u_sampler, pixelatedUV, 0.0);
  let pxLuma = dot(pxColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let sortReveal = smoothstep(threshold - 0.1, threshold + 0.1, pxLuma);

  // Combined reveal: mouse-painted area OR sorted bright pixels, minus decay
  let combinedReveal = clamp((1.0 - paintedMask) + sortReveal * 0.6 - temporalDecay * 0.5, 0.0, 1.0);

  // Chromatic separation on reveal edges
  let edgeWidth = 0.02 + softness * 0.5;
  let edgeGradient = abs(combinedReveal - 0.5) * 2.0;
  let edgeMask = 1.0 - smoothstep(0.0, edgeWidth, abs(edgeGradient - 1.0));
  let chromaShift = 0.004 * (1.0 + mids * 0.8) * edgeMask;

  let r = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV + vec2<f32>(chromaShift, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV - vec2<f32>(chromaShift, 0.0), 0.0).b;
  let chromaColor = vec3<f32>(r, g, b);

  let clearColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Scanline bands on hidden regions
  let scanline = sin(uv.y * resolution.y * 0.7) * 0.5 + 0.5;
  let scanDark = mix(vec3<f32>(0.02, 0.02, 0.03), vec3<f32>(0.08, 0.08, 0.10), scanline);
  let hiddenColor = mix(scanDark, chromaColor * 0.3, temporalDecay * 0.4);

  var finalColor = mix(hiddenColor, chromaColor, combinedReveal);
  finalColor = mix(finalColor, clearColor, (1.0 - paintedMask) * 0.3);

  // Film grain
  let grain = hash3(vec3<f32>(uv * 500.0, time)).x;
  finalColor += (grain - 0.5) * 0.03;

  // ACES tone mapping
  finalColor = aces_tone_map(finalColor);

  // Alpha: Reveal_mask * (1.0 - temporal_decay) * depth
  let alpha = clamp((1.0 - paintedMask) * (1.0 - temporalDecay * 0.7) * depth + combinedReveal * 0.2, 0.05, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
