// ═══════════════════════════════════════════════════════════════════
//  cursor-aura-explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic-aberration, prism, glow
//  Complexity: Very High
//  Chunks From: cursor-aura.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  A glowing cursor aura that acts as a chromatic prism.
//  Inside the aura radius, R/G/B channels separate by pseudo-
//  wavelength. The aura edge glows with spectral colors, and
//  click ripples launch chromatic shockwaves.
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

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
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

  let radius = u.zoom_params.x * 0.5;
  let intensity = u.zoom_params.y;
  let prismStrength = mix(0.02, 0.12, u.zoom_params.z);
  let dispersion = mix(0.5, 3.0, u.zoom_params.w);

  var mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);

  let currentRadius = radius + sin(time * 3.0) * 0.02;
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + 0.05, dist);

  // Prism displacement from mouse
  let rUV = prismDisplace(uv, mousePos, -1.0 * dispersion, prismStrength);
  let gUV = prismDisplace(uv, mousePos, 0.0, prismStrength);
  let bUV = prismDisplace(uv, mousePos, 1.0 * dispersion, prismStrength);

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let effectIntensity = 1.0 + mouseDown * 1.5;

  // Base edge detection / high pass
  let offset = 1.0 / resolution.x;
  let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset, 0.0), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0);
  let top = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset), 0.0);
  let edges = abs(left - right) + abs(top - bottom);

  var baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Inside aura: chromatic sampling
  var insideColor: vec4<f32>;
  if (mask > 0.001) {
    let r = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * effectIntensity, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * effectIntensity, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * effectIntensity, 0.0).b;
    let chroma = vec3<f32>(r, g, b);
    let lum = dot(chroma, vec3<f32>(0.299, 0.587, 0.114));
    let saturated = mix(vec3<f32>(lum), chroma, 1.5);
    let effectColor = edges.rgb * 2.0 + vec3<f32>(0.0, 0.5, 1.0) * intensity;
    insideColor = vec4<f32>(mix(effectColor, saturated, 0.6), 1.0);
  } else {
    insideColor = baseColor;
  }

  // Combine
  var finalColor = mix(baseColor, insideColor, mask);

  // Glowing ring at aura edge with spectral colors
  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringHue = fract(dist * 5.0 + time * 0.5);
  let ringColor = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.67))
  );
  finalColor += vec4<f32>(ringColor, 0.0) * ring * intensity * 2.0;

  // Spectral glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor += vec4<f32>(0.5, 0.3, 0.8, 0.0) * glow;

  let totalDisp = length(rUV - gUV) + length(gUV - bUV);
  let alpha = clamp(totalDisp * 5.0, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
