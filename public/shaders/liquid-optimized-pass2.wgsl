// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Optimized – Pass 2: Fluid Rendering
//  Category: liquid-effects
//  Features: multi-pass-2, Fresnel, Beer-Lambert, specular, alpha blending
//  Inputs: dataTextureC (physics state from Pass 1)
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═══════════════════════════════════════════════════════════════════════════════

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

fn sampleHeight(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).g;
}

fn sampleHeightClamped(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let clampedUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  return sampleHeight(clampedUV);
}

fn calculateNormal(uv: vec2<f32>, pixelSize: vec2<f32>, heightScale: f32) -> vec3<f32> {
  let left   = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let right  = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottom = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let top    = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  let dx = (right - left) * heightScale;
  let dy = (top - bottom) * heightScale;
  return normalize(vec3<f32>(-dx, -dy, 2.0));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = vec2<f32>(1.0) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);
  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let turbidity = u.zoom_params.w;

  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let newHeight = persistentData.g;
  let newVelocity = persistentData.b;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let liquidHeight = abs(newHeight) * 2.0;
  let liquidThickness = liquidHeight * (1.0 + turbidity);

  let normal = calculateNormal(uv, pixelSize, 1.0);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);

  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);

  let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
  let absorptionR = exp(-effectiveDepth * 2.0);
  let absorptionG = exp(-effectiveDepth * 1.6);
  let absorptionB = exp(-effectiveDepth * 1.2);
  let absorption = (absorptionR + absorptionG + absorptionB) / 3.0;

  let heightTint = vec3<f32>(0.0, 0.1, 0.15) * newHeight * 0.5;
  let liquidColor = vec3<f32>(
    baseColor.r * absorptionR,
    baseColor.g * absorptionG + heightTint.g,
    baseColor.b * absorptionB + heightTint.b
  );

  let lightDir = normalize(vec3<f32>(0.3, 0.5, 1.0));
  let halfDir = normalize(lightDir + viewDir);
  let specAngle = max(0.0, dot(normal, halfDir));
  let specular = pow(specAngle, 128.0) * 0.8 * (1.0 - turbidity * 0.5);

  let finalLiquidColor = liquidColor + vec3<f32>(specular);
  let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  let finalAlpha = clamp(alpha, 0.0, 1.0) * backgroundFactor;
  let finalColor = mix(baseColor, finalLiquidColor, finalAlpha);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
