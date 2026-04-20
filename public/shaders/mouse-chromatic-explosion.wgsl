// ═══════════════════════════════════════════════════════════════════
//  mouse-chromatic-explosion
//  Category: interactive-mouse
//  Features: mouse-driven, chromatic, prism
//  Complexity: Medium
//  Chunks From: chunk-library.md (none)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The mouse is a prism. R, G, B channels separate and displace
//  based on pseudo-wavelength. Creates rainbow halos, spectral
//  fans, and chromatic aberration art. Click ripples launch
//  chromatic shockwaves.
//  Alpha channel stores total chromatic displacement magnitude.
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

  // Snell's law approximation: deflection proportional to wavelength
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

  let prismStrength = mix(0.02, 0.12, u.zoom_params.x);
  let dispersion = mix(0.5, 3.0, u.zoom_params.y);
  let rippleStrength = u.zoom_params.z;
  let saturationBoost = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Base prism displacement from mouse
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

      // Chromatic ripple: different phases per channel
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);

      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * rippleStrength * 0.03;
      gOffset = gOffset + dir * wave * rippleStrength * 0.03;
      bOffset = bOffset + dir * bWave * rippleStrength * 0.03;
    }
  }

  // Mouse down intensifies effect
  let intensity = 1.0 + mouseDown * 1.5;

  let r = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * intensity, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * intensity, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * intensity, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Saturation boost for psychedelic effect
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.0 + saturationBoost);

  // Add spectral glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  color = color + vec3<f32>(0.5, 0.3, 0.8) * glow;

  // Alpha = total chromatic displacement magnitude
  let totalDisp = length(rUV - gUV) + length(gUV - bUV) + length(rOffset) + length(gOffset) + length(bOffset);
  let alpha = clamp(totalDisp * 5.0, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
