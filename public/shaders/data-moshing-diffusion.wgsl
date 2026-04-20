// ═══════════════════════════════════════════════════════════════════
//  data-moshing-diffusion
//  Category: advanced-hybrid
//  Features: mouse-driven, data-moshing, anisotropic-diffusion, temporal
//  Complexity: High
//  Chunks From: data-moshing.wgsl, conv-anisotropic-diffusion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Data moshing smear offsets are diffused anisotropically, creating
//  oil-paint drips that follow image edges. The mouse injects both
//  swirl force and diffusion heat. Quantization adds glitch artifacts
//  to the diffused result. Alpha stores average diffusion coefficient.
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

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  let smearStrength = u.zoom_params.x;
  let kappa = mix(0.01, 0.2, u.zoom_params.y);
  let dt = mix(0.05, 0.25, u.zoom_params.z);
  let quantize = u.zoom_params.w;

  // Read previous UV offset from history
  let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var offset = prevData.xy;

  // Mouse swirl interaction
  let aspect = res.x / res.y;
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseRadius = mix(0.05, 0.3, smearStrength);
  if (mouseDist < mouseRadius) {
    let angle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let swirl = vec2<f32>(cos(angle + time), sin(angle + time));
    let force = (1.0 - mouseDist / mouseRadius) * smearStrength * 0.02;
    offset = offset + swirl * force;
  }

  offset = offset * 0.96;
  offset = clamp(offset, vec2<f32>(-0.5), vec2<f32>(0.5));

  // Sample with offset
  let distortedUV = uv - offset;
  var current = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;
  let center = current;
  var avgCoeff = 0.0;

  // Anisotropic diffusion on the offset-distorted image
  let iterations = 2;
  for (var iter = 0; iter < iterations; iter++) {
    let n = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, 1.0) * pixelSize, 0.0).rgb;
    let s = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, -1.0) * pixelSize, 0.0).rgb;
    let e = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(1.0, 0.0) * pixelSize, 0.0).rgb;
    let w = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0).rgb;

    let gradN = length(n - current);
    let gradS = length(s - current);
    let gradE = length(e - current);
    let gradW = length(w - current);

    let cN = diffusionCoefficient(gradN, kappa);
    let cS = diffusionCoefficient(gradS, kappa);
    let cE = diffusionCoefficient(gradE, kappa);
    let cW = diffusionCoefficient(gradW, kappa);

    let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * smearStrength;
    let mouseBoost = 1.0 + mouseFactor * 5.0;

    let fluxN = cN * (n - current);
    let fluxS = cS * (s - current);
    let fluxE = cE * (e - current);
    let fluxW = cW * (w - current);

    current = current + dt * mouseBoost * (fluxN + fluxS + fluxE + fluxW);
    avgCoeff = (cN + cS + cE + cW) * 0.25;
  }

  let paintBoost = 1.0 + smearStrength * 0.3;
  var finalColor = mix(center, current, paintBoost);

  // Color quantization (glitch effect)
  if (quantize > 0.0) {
    let q = 20.0 * (1.0 - quantize) + 1.0;
    finalColor = floor(finalColor * q) / q;
  }

  textureStore(dataTextureA, global_id.xy, vec4<f32>(offset, 0.0, 0.0));
  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, avgCoeff));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
