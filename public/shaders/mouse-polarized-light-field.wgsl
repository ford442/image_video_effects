// ═══════════════════════════════════════════════════════════════════
//  mouse-polarized-light-field
//  Category: interactive-mouse
//  Features: mouse-driven, interference, polarization
//  Complexity: High
//  Chunks From: chunk-library.md (hash12, hueShift)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse controls polarization angle and birefringence across the
//  image. Creates interference patterns, color shifts, and moiré
//  effects as if viewing through polarizing filters. Click ripples
//  spawn transient polarization vortices.
//  Alpha channel stores polarization phase.
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

// ═══ CHUNK: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let polarizationAngle = mix(0.0, 3.14159, u.zoom_params.x);
  let birefringence = mix(0.0, 2.0, u.zoom_params.y);
  let fringeDensity = mix(5.0, 50.0, u.zoom_params.z);
  let colorMode = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Polarization angle varies with mouse position
  let mousePolar = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
  let baseAngle = polarizationAngle + mousePolar * 0.5;

  // Local polarization varies across screen
  let localAngle = baseAngle + uv.x * 2.0 + uv.y * 1.5;

  // Distance from mouse for localized effect
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.5, 0.0, mouseDist);

  // Malus's law: intensity varies with cos²(2θ)
  let malus = cos(localAngle * 2.0) * cos(localAngle * 2.0);

  // Birefringence phase retardation creates interference colors
  let retardation = birefringence * (1.0 + mouseInfluence * 2.0) * mouseDist * 3.14159;
  let phase = retardation + time * 0.5;

  // Interference fringe pattern
  let fringe = cos(phase * fringeDensity + mouseDist * 20.0);
  let fringeIntensity = fringe * fringe * 0.5 + 0.5;

  // Sample image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(baseColor);

  // Polarization-filtered colors: rotate RGB channels by different angles
  let rAngle = localAngle;
  let gAngle = localAngle + retardation * 0.3;
  let bAngle = localAngle + retardation * 0.6;

  let rFilter = cos(rAngle * 2.0) * cos(rAngle * 2.0);
  let gFilter = cos(gAngle * 2.0) * cos(gAngle * 2.0);
  let bFilter = cos(bAngle * 2.0) * cos(bAngle * 2.0);

  var filteredColor = vec3<f32>(
    baseColor.r * rFilter,
    baseColor.g * gFilter,
    baseColor.b * bFilter
  );

  // Interference color shift
  let interferenceHue = phase * 0.5 + mouseDist * 3.0;
  filteredColor = hueShift(filteredColor, interferenceHue * colorMode);

  // Moiré pattern from crossed polarizers
  let moireX = sin(uv.x * resolution.x * 0.1 + localAngle * 2.0);
  let moireY = sin(uv.y * resolution.y * 0.1 + localAngle * 2.0);
  let moire = (moireX * moireY) * 0.5 + 0.5;

  // Mix image with interference
  var finalColor = mix(filteredColor, baseColor * moire, 0.3);
  finalColor = finalColor + vec3<f32>(0.3, 0.5, 0.7) * fringeIntensity * birefringence * 0.2;

  // Ripple vortices: transient polarization spirals
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let vortexAngle = atan2(uv.y - rPos.y, uv.x - rPos.x) + elapsed * 3.0;
      let vortex = sin(vortexAngle * 3.0 + rDist * 30.0) * exp(-elapsed * 1.0) * smoothstep(0.3, 0.0, rDist);
      finalColor = finalColor + vec3<f32>(0.5, 0.7, 1.0) * vortex * 0.5;
    }
  }

  // Mouse down creates a bright analyzer flash
  let flash = mouseDown * exp(-mouseDist * mouseDist * 100.0) * 0.5;
  finalColor = finalColor + vec3<f32>(0.9, 0.95, 1.0) * flash;

  // Alpha = polarization phase
  let alpha = clamp(fract(phase * 0.159), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
