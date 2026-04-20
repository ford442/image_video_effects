// ═══════════════════════════════════════════════════════════════════
//  cyber-lattice-bilateral
//  Category: advanced-hybrid
//  Features: mouse-driven, bilateral-filter, grid-distortion, dreamy
//  Complexity: Very High
//  Chunks From: cyber-lattice.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  A cyber lattice grid where each cell is smoothed by bilateral
//  filtering. The grid distorts around the mouse; inside each cell,
//  edge-preserving dream smoothing creates a painterly effect.
//  Grid lines remain sharp while cell interiors become ethereal.
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

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;

  let gridScale = 10.0 + u.zoom_params.x * 50.0;
  let distortStrength = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z * 2.0;
  let radius = u.zoom_params.w * 0.5;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let aspect = res.x / res.y;
  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);

  // Lattice distortion
  let distortion = smoothstep(radius, 0.0, dist) * distortStrength * sin(time * 5.0);
  let gridUV = uv + (uv - mousePos) * distortion;

  let gridX = abs(fract(gridUV.x * gridScale) - 0.5);
  let gridY = abs(fract(gridUV.y * gridScale) - 0.5);
  let gridLine = min(gridX, gridY);

  let thickness = 0.05;
  let mouseInfluence = smoothstep(radius, 0.0, dist);
  let currentThickness = thickness + mouseInfluence * 0.1;
  let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, gridLine);

  // Bilateral filter inside grid cell
  let spatialSigmaBase = mix(0.1, 1.0, 0.5);
  let colorSigma = mix(0.05, 1.0, 0.3);
  let hueShiftAmt = 0.2;

  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * 0.5;
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

  // Ripple shockwaves modulate sharpness
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

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let bRadius = i32(ceil(finalSigma * 2.5));
  let maxRadius = min(bRadius, 7);

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
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

  // Grid glow color
  var glowColor = vec3<f32>(0.0, 1.0, 1.0);
  if (mouseDown > 0.5) {
    glowColor = vec3<f32>(1.0, 0.0, 1.0);
  }

  let totalGlow = glowIntensity * (0.5 + 0.5 * mouseInfluence);

  // Apply grid lines over dreamy result
  var finalColor = mix(result, glowColor, gridMask * totalGlow);

  // Boost grid lines
  if (gridMask > 0.5) {
    finalColor = glowColor * totalGlow * 1.5;
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
