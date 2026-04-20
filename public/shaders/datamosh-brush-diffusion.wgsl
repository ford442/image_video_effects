// ═══════════════════════════════════════════════════════════════════
//  Datamosh Brush Diffusion
//  Category: advanced-hybrid
//  Features: datamosh, anisotropic-diffusion, mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: datamosh-brush.wgsl, conv-anisotropic-diffusion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Interactive datamoshing brush merged with Perona-Malik anisotropic
//  diffusion. Paint to freeze pixels while diffusion smooths along
//  edges, creating oil-painted MPEG artifact trails with temporal
//  persistence.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
    return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;

  let brushSize = mix(0.02, 0.2, u.zoom_params.x);
  let kappa = mix(0.01, 0.2, u.zoom_params.y);
  let dt = mix(0.05, 0.25, u.zoom_params.z);
  let alphaGhost = mix(0.3, 1.0, u.zoom_params.w);

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Read previous frame
  var prevSample = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  var prevColor = prevSample.rgb;
  var prevAlpha = prevSample.a;

  if (prevAlpha < 0.01) {
      let currSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
      prevColor = currSample.rgb;
      prevAlpha = currSample.a;
  }

  var inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var inputColor = inputSample.rgb;

  // Datamosh decay
  var blendedColor = mix(prevColor, inputColor, 0.05);
  var blendedAlpha = mix(prevAlpha, inputSample.a, 0.05);
  blendedAlpha = blendedAlpha * 0.98;

  // Brush interaction
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  if (mouseDown > 0.5 && dist < brushSize) {
      let blockID = floor(uv * 20.0);
      let noiseVal = hash12(blockID + vec2<f32>(time));
      if (noiseVal > 0.3) {
          let offsetUV = uv + vec2<f32>(noiseVal * 0.05);
          let glitchSample = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);
          blendedColor = glitchSample.rgb;
          blendedAlpha = glitchSample.a * 0.8 + 0.1;
      } else {
         blendedColor = prevColor;
         blendedAlpha = prevAlpha * alphaGhost;
      }
      blendedAlpha = max(blendedAlpha, 0.1);
  }

  // ═══ ANISOTROPIC DIFFUSION ═══
  let center = blendedColor;
  let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 1.0) * pixelSize, 0.0).rgb;
  let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -1.0) * pixelSize, 0.0).rgb;
  let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 0.0) * pixelSize, 0.0).rgb;
  let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0).rgb;

  let gradN = length(n - center);
  let gradS = length(s - center);
  let gradE = length(e - center);
  let gradW = length(w - center);

  let cN = diffusionCoefficient(gradN, kappa);
  let cS = diffusionCoefficient(gradS, kappa);
  let cE = diffusionCoefficient(gradE, kappa);
  let cW = diffusionCoefficient(gradW, kappa);

  // Mouse heat source for diffusion
  let mouseDist = length(uv - mouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * select(0.0, 1.0, mouseDown > 0.5);
  let mouseBoost = 1.0 + mouseFactor * 5.0;

  let fluxN = cN * (n - center);
  let fluxS = cS * (s - center);
  let fluxE = cE * (e - center);
  let fluxW = cW * (w - center);

  let diffused = center + dt * mouseBoost * (fluxN + fluxS + fluxE + fluxW);

  // Blend datamosh with diffusion
  let avgCoeff = (cN + cS + cE + cW) * 0.25;
  let finalColor = mix(blendedColor, diffused, 0.5 + avgCoeff * 0.5);

  blendedAlpha = clamp(blendedAlpha, 0.0, 1.0);

  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, blendedAlpha));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, blendedAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
