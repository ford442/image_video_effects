// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid – Pass 2: Fluid Rendering with Alpha Physics
//  Category: image
//  Features: multi-pass-2, refraction, Fresnel, Beer-Lambert, specular, upgraded-rgba, audio-reactive
//  Upgraded: 2026-11-22
//  Ideas: sun glitter off wave facets (treble); Cauchy dispersion of the refraction
//  Rescue: slope/curvature now per-UV so the sheet is visible on a stable solver; exact C loads
//  A packing: display ACES RGBA on writeTexture; height stays in pass 1's A
//  Inputs: dataTextureC (physics state from Pass 1, one frame late by design), readTexture
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn loadH(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).g;
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pc = vec2<i32>(global_id.xy);
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);
  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let turbulence = u.zoom_params.y;
  let rippleStrength = u.zoom_params.z;
  let turbidity = u.zoom_params.w;
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let persistentData = textureLoad(dataTextureC, pc, 0);
  let newHeight = persistentData.g;

  // Height taps (exact loads). Slope and curvature are per-UV so the look does not depend on
  // the render size, and the gain is calibrated for the stable pass-1 solver (|h| ≈ 0.02-0.1).
  let left   = loadH(pc + vec2<i32>(-1, 0), hi);
  let right  = loadH(pc + vec2<i32>(1, 0), hi);
  let bottom = loadH(pc + vec2<i32>(0, -1), hi);
  let top    = loadH(pc + vec2<i32>(0, 1), hi);
  let dhdu = vec2<f32>(right - left, top - bottom) * 0.5 * resolution;
  let slopeGain = 2.25 * surfaceTension * (0.65 + turbulence);
  let normal = normalize(vec3<f32>(-dhdu.x * slopeGain, -dhdu.y * slopeGain, 2.0));

  let refractionStrength = 0.045 * surfaceTension;
  let refractDisplacement = normal.xy * refractionStrength * backgroundFactor;
  let totalDisplacement = refractDisplacement + vec2<f32>(newHeight * 0.01);

  // ── Idea 2: Cauchy dispersion ───────────────────────────────────────
  // n(λ) = A + B/λ²: blue bends more than red, so the three photo taps share the refraction
  // offset but scale it by (n_c − 1)/(n_g − 1). B is exaggerated ×40 so the fringe reads.
  let dispersionAmt = 0.5 + rippleStrength;
  let scaleR = 1.0 - 0.18 * dispersionAmt;
  let scaleB = 1.0 + 0.26 * dispersionAmt;
  let uvG = clamp(uv + totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvR = clamp(uv + totalDisplacement * scaleR, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + totalDisplacement * scaleB, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  // Curvature in per-UV² units, normalised so a typical crest reads ≈ ±0.3.
  let curvature = (right + left + top + bottom - 4.0 * newHeight) * resolution.x * resolution.y / 1500.0;
  let laplacePressure = abs(curvature) * surfaceTension * 2.0;
  let specular = pow(max(0.0, normal.z), 20.0) * laplacePressure * 0.3 * (0.4 + rippleStrength);
  // Fold caustics where the surface is concave and focuses light.
  let caustic = pow(saturate(-curvature * 6.0), 2.0) * (0.35 + rippleStrength);

  // ── Idea 1: sun glitter ─────────────────────────────────────────────
  // A facet flashes when its normal lines up with the half-vector between a low sun and the
  // eye. Treble raises how many capillary facets are steep enough to catch it.
  let sunDir = normalize(vec3<f32>(0.35, 0.45, 0.82));
  let halfSun = normalize(sunDir + vec3<f32>(0.0, 0.0, 1.0));
  let facet = pow(max(0.0, dot(normal, halfSun)), 320.0);
  let glitter = facet * (0.3 + 1.6 * treble) * backgroundFactor;

  let liquidThickness = abs(newHeight) * 2.0 + 0.1;
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);

  let absorptionR = exp(-liquidThickness * (1.0 + turbidity));
  let absorptionG = exp(-liquidThickness * (0.8 + turbidity * 0.9));
  let absorptionB = exp(-liquidThickness * (0.6 + turbidity * 0.8));
  let heightTint = vec3<f32>(0.0, 0.1, 0.15) * newHeight * 0.5;
  let liquidColor = vec3<f32>(
    baseColor.r * absorptionR,
    baseColor.g * absorptionG + heightTint.g,
    baseColor.b * absorptionB + heightTint.b
  );

  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
  let absorption = exp(-effectiveDepth * 2.0);
  let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  let finalAlpha = clamp(alpha, 0.0, 1.0) * backgroundFactor;

  let finalColor = liquidColor + vec3<f32>(specular + caustic * 0.55 + glitter);
  // Dark wetting rim where the water meets the depth edge.
  let contact = smoothstep(0.0, 0.06, depth) * (1.0 - smoothstep(0.06, 0.18, depth));
  let wetRim = contact * exp(-abs(newHeight) * 40.0);
  let rimmed = finalColor * (1.0 - wetRim * 0.55);
  let outputColor = mix(baseColor, rimmed, finalAlpha);
  let display = acesToneMap(max(outputColor, vec3<f32>(0.0)));

  textureStore(writeTexture, global_id.xy, vec4<f32>(display, finalAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
