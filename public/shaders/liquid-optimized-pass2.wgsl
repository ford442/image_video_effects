// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Optimized – Pass 2: Fluid Rendering
//  Category: liquid-effects
//  Features: multi-pass-2, Fresnel, Beer-Lambert, specular, alpha blending, upgraded-rgba
//  Upgraded: 2026-10-17
//  Ideas: Snell offset of the photo along the normal; velocity-stretched specular streak
//  A packing: display ACES RGBA on writeTexture. Does not write A.
//  Inputs: dataTextureC (physics state from Pass 1)
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
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
  // Gravity flattens the shaded normal; damping tightens the glint.
  // At the saved defaults (0.5) both scales match the previous constants.
  let heightScale = mix(1.35, 0.65, clamp(u.zoom_params.y, 0.0, 1.0));
  let specPower = mix(96.0, 160.0, clamp(u.zoom_params.z, 0.0, 1.0));

  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let newHeight = persistentData.g;
  let newVelocity = persistentData.b;

  let liquidHeight = abs(newHeight) * 2.0;
  let liquidThickness = liquidHeight * (1.0 + turbidity);

  let normal = calculateNormal(uv, pixelSize, heightScale);
  // Idea 1: Snell offset. The photo shifts along the normal so the surface refracts.
  let refractAmt = (1.0 - 1.0 / 1.33) * liquidHeight * (0.08 + surfaceTension * 0.04);
  let refractUV = clamp(uv + normal.xy * refractAmt, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseSample = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);
  let baseColor = baseSample.rgb;
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
  // Idea 2: velocity glint. A fast wave stretches the highlight into a streak.
  let streak = clamp(abs(newVelocity) * 6.0, 0.0, 3.0);
  let specular = pow(specAngle, specPower / (1.0 + streak)) * 0.8 * (1.0 - turbidity * 0.5);
  let tangentSheen = exp(-abs(viewDotNormal - 0.86) * 22.0) * streak * 0.22;

  let finalLiquidColor = liquidColor + vec3<f32>(specular) + vec3<f32>(0.85, 0.95, 1.0) * tangentSheen;
  let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  let finalAlpha = clamp(alpha, 0.0, 1.0) * backgroundFactor;
  let finalColor = mix(baseColor, finalLiquidColor, finalAlpha);
  let mapped = aces(max(finalColor, vec3<f32>(0.0)));
  let outAlpha = clamp(baseSample.a * (1.0 - finalAlpha) + finalAlpha, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(mapped, outAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
