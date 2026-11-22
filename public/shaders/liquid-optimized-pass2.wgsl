// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Optimized – Pass 2: Fluid Rendering
//  Category: liquid-effects
//  Features: multi-pass-2, Fresnel, Beer-Lambert, specular, alpha blending, upgraded-rgba
//  Upgraded: 2026-11-22
//  Ideas: Henyey-Greenstein in-scatter veil for turbid water; total-internal-reflection roll-off on steep crests
//  Rescue: slope/streak gains calibrated for the stable pass-1 solver (HEAD assumed ±0.5 noise); exact C loads
//  A packing: display ACES RGBA on writeTexture. Does not write A.
//  Inputs: dataTextureC (physics state from Pass 1, one frame late by design)
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn loadH(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).g;
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn henyeyGreenstein(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  return (1.0 - g2) / (4.0 * 3.14159265 * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-3), 1.5));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let pc = vec2<i32>(global_id.xy);
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);
  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let turbidity = u.zoom_params.w;
  // Gravity flattens the shaded normal; damping tightens the glint.
  // At the saved defaults (0.5) both scales match the previous constants.
  let heightScale = mix(1.35, 0.65, clamp(u.zoom_params.y, 0.0, 1.0));
  let specPower = mix(96.0, 160.0, clamp(u.zoom_params.z, 0.0, 1.0));

  let persistentData = textureLoad(dataTextureC, pc, 0);
  let newHeight = persistentData.g;
  let newVelocity = persistentData.b;

  let liquidHeight = abs(newHeight) * 2.0;
  let liquidThickness = liquidHeight * (1.0 + turbidity);

  // Height taps (exact loads). Slope is per-UV so the look does not depend on render size;
  // the 9.5 gain is calibrated for the viscous pass-1 solver (rms ∂h/∂u ≈ 0.05).
  let left   = loadH(pc + vec2<i32>(-1, 0), hi);
  let right  = loadH(pc + vec2<i32>(1, 0), hi);
  let bottom = loadH(pc + vec2<i32>(0, -1), hi);
  let top    = loadH(pc + vec2<i32>(0, 1), hi);
  let dhdu = vec2<f32>(right - left, top - bottom) * 0.5 * resolution;
  let normal = normalize(vec3<f32>(-dhdu.x * heightScale * 9.5, -dhdu.y * heightScale * 9.5, 2.0));

  // Snell offset. The photo shifts along the normal so the surface refracts. A shallow base
  // depth keeps the offset alive where the surface is flat.
  let refractAmt = (1.0 - 1.0 / 1.33) * (0.06 + liquidHeight) * (0.5 + surfaceTension * 0.25);
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
  // Velocity glint. A fast wave stretches the highlight into a streak (gain ×5 for the
  // stable solver, whose peak speed is ~0.1 rather than the ±1 clamp).
  let streak = clamp(abs(newVelocity) * 30.0, 0.0, 3.0);
  let specular = pow(specAngle, specPower / (1.0 + streak)) * 0.8 * (1.0 - turbidity * 0.5);
  let tangentSheen = exp(-abs(viewDotNormal - 0.86) * 22.0) * streak * 0.22;

  // ── Idea 1: Henyey-Greenstein in-scatter veil ───────────────────────
  // Turbid water scatters sunlight toward the eye, forward-peaked. The transmitted ray tilts
  // with the wave slope, so crests that face the sun glow milkier. Turbidity (default 0)
  // scales it, so the clear-water default is unchanged.
  let transmitted = normalize(vec3<f32>(normal.xy * (1.0 - 1.0 / 1.33), 1.0));
  let hg = henyeyGreenstein(dot(transmitted, lightDir), 0.6);
  let veil = vec3<f32>(0.78, 0.92, 1.0) * hg * turbidity * (0.12 + liquidThickness) * 0.9;

  let finalLiquidColor = liquidColor + vec3<f32>(specular) + vec3<f32>(0.85, 0.95, 1.0) * tangentSheen + veil;

  // ── Idea 2: total-internal-reflection roll-off ──────────────────────
  // Light rising from the photo meets the surface at the local tilt. Past the critical angle
  // asin(1/1.33) ≈ 48.8° it cannot leave, so steep crests show a darkened mirror tap instead.
  let tir = smoothstep(0.80, 0.62, normal.z);
  let mirrorUV = clamp(uv - normal.xy * refractAmt * 3.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let mirrorTap = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0).rgb * 0.55 + vec3<f32>(0.03, 0.06, 0.09);
  let rolled = mix(finalLiquidColor, mirrorTap, tir * backgroundFactor);

  let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  let finalAlpha = clamp(alpha, 0.0, 1.0) * backgroundFactor;
  let finalColor = mix(baseColor, rolled, finalAlpha);
  let mapped = aces(max(finalColor, vec3<f32>(0.0)));
  let outAlpha = clamp(baseSample.a * (1.0 - finalAlpha) + finalAlpha, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(mapped, outAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
