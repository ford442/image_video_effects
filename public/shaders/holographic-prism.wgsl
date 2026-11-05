// ═══════════════════════════════════════════════════════════════════
//  Holographic Prism v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: Cauchy dispersion (§12.2F); total-internal-reflection flash
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn snellRefract(incident: vec2<f32>, n: vec2<f32>, n1: f32, n2: f32) -> vec2<f32> {
  let eta = n1 / n2;
  let cosI = clamp(-dot(incident, n), -1.0, 1.0);
  let sinT2 = eta * eta * (1.0 - cosI * cosI);
  let cosT = sqrt(max(0.0, 1.0 - sinT2));
  return incident * eta + n * (eta * cosI - cosT);
}

// n(λ) = 1 + B/λ², relative to green. λ in µm.
fn cauchyRel(bCoeff: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.4225, 0.3025, 0.2025);
  let n = vec3<f32>(1.0) + vec3<f32>(bCoeff) / lam2;
  return n / max(n.y, 0.001);
}

fn wavelengthToRGB(wavelength: f32) -> vec3<f32> {
  var c = vec3<f32>(0.0);
  if (wavelength < 440.0) {
    c = vec3<f32>(-(wavelength - 440.0) / 60.0, 0.0, 1.0);
  } else if (wavelength < 490.0) {
    c = vec3<f32>(0.0, (wavelength - 440.0) / 50.0, 1.0);
  } else if (wavelength < 510.0) {
    c = vec3<f32>(0.0, 1.0, -(wavelength - 510.0) / 20.0);
  } else if (wavelength < 580.0) {
    c = vec3<f32>((wavelength - 510.0) / 70.0, 1.0, 0.0);
  } else if (wavelength < 645.0) {
    c = vec3<f32>(1.0, -(wavelength - 645.0) / 65.0, 0.0);
  } else {
    c = vec3<f32>(1.0, 0.0, 0.0);
  }
  return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var q = abs(p);
    q -= 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
    q -= vec2<f32>(clamp(q.x, -k.z * r, k.z * r), r);
    return length(q) * sign(q.y);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let time = u.config.x;
  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let facets = max(3.0, floor(mix(3.0, 12.0, u.zoom_params.x)));
  let dispersion = u.zoom_params.y * 0.06;
  let rotationSpeed = u.zoom_params.z;
  let holoContrast = u.zoom_params.w;

  // Live pointer. The extraBuffer spring was cleared by the host every frame.
  let smooth_mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held_intensity = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let center = vec2<f32>(0.5, 0.5) + (smooth_mouse - 0.5) * 0.2 * (1.0 + depth * 0.5);
  let p = (uv - center) * vec2<f32>(aspect, 1.0);
  let dist = max(length(p), 0.001);
  let baseAngle = atan2(p.y, p.x);
  
  let shapeDist = mix(sdCircle(p, 0.2), sdHexagon(p, 0.2 + bass * 0.05), held_intensity);
  let shapeEdge = smoothstep(0.02, 0.0, abs(shapeDist));
  
  let prismRotation = baseAngle + time * rotationSpeed * (1.0 + bass * 0.5) + bass * 0.3;
  let facet = abs(fract(prismRotation / 6.28318 * facets) - 0.5) * 2.0;

  let n1 = 1.0;
  let n2 = 1.52 + held_intensity * 0.2;
  let prismNormal = vec2<f32>(cos(facet * 3.14159265 + 1.570796), sin(facet * 3.14159265 + 1.570796));
  let incident = normalize(p + vec2<f32>(0.001, 0.0));
  let refracted = snellRefract(incident, prismNormal, n1, n2);
  // Exit refraction is glass into air. Past the critical angle the facet mirrors.
  let etaOut = n2 / max(n1, 0.001);
  let cosI = clamp(abs(dot(incident, prismNormal)), 0.0, 1.0);
  let sinOut = etaOut * etaOut * (1.0 - cosI * cosI);
  // ── Idea 2: TIR flash ─────────────────────────────────────────────
  let tir = smoothstep(0.92, 1.08, sinOut);

  let facetWarp = vec2<f32>(refracted.x / aspect, refracted.y) * (0.025 + bass * 0.015 + held_intensity * 0.02) / (dist + 0.1);
  let holoSpeckle = hash12(floor(uv * 256.0 + fract(sin(time * 0.5) * 1000.0))) * 2.0 - 1.0;
  let speckleMask = smoothstep(0.35, 0.65, abs(holoSpeckle)) * holoContrast;

  let glitchJitter = vec2<f32>(
    sin(uv.y * 80.0 + time * (5.0 + treble * 8.0)),
    cos(uv.x * 90.0 + time * (4.0 + mids * 7.0))
  ) * 0.004 * holoContrast;

  let baseUV = clamp(uv + facetWarp + glitchJitter, vec2<f32>(0.001), vec2<f32>(0.999));

  // ── Idea 1: Cauchy dispersion (§12.2F) ───────────────────────────
  // Dispersion is B in n(λ) = 1 + B/λ². Green stays the reference.
  let rel = cauchyRel(mix(0.04, 0.32, clamp(u.zoom_params.y, 0.0, 1.0)));
  let rShift = refracted * dispersion * rel.x / (dist + 0.1);
  let bShift = refracted * dispersion * rel.z / (dist + 0.1);

  let uvR = clamp(baseUV + vec2<f32>(rShift.x / aspect, rShift.y) * 0.03, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = baseUV;
  let uvB = clamp(baseUV - vec2<f32>(bShift.x / aspect, bShift.y) * 0.03, vec2<f32>(0.001), vec2<f32>(0.999));

  let dataC = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

  let sampled = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  let wavelengthColor = wavelengthToRGB(mix(450.0, 700.0, facet));
  let caustic = wavelengthColor * exp(-dist * (2.2 + mids * 2.0)) * (0.2 + bass * 0.15) * (1.0 + dataC.r * 0.1);
  let interference = sin(dist * 60.0 - time * 3.0 + facet * 12.0) * 0.5 + 0.5;
  let holoFringe = caustic * interference * (0.5 + treble * 0.5) * speckleMask;

  let shardRing = smoothstep(0.08, 0.0, abs(dist - (0.18 + bass * 0.08))) + shapeEdge * 0.5;
  let bloom = vec3<f32>(1.0, 0.92, 0.55) * shardRing * (0.2 + mids * 0.3) * (1.0 + treble * 0.4);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
      let event = u.ripples[i];
      let age = max(time - event.z, 0.0);
      let r_dist = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
      if (age < 2.0) {
          let wave = exp(-age * 1.8) * exp(-abs(r_dist - age * 0.38) * 58.0);
          clickFront += min(wave, 1.0);
      }
  }
  
  let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

  let shapeGlow = spectral * shapeEdge * held_intensity;

  var finalColor = sampled * (0.75 + caustic.b * 0.15) + caustic * 0.7 + holoFringe + bloom + shapeGlow;
  finalColor += spectral * (abs(clockRings) * 0.1 + min(clickFront, 1.5) * 0.35);
  let tirMask = tir * smoothstep(0.14, 0.0, abs(shapeDist));
  finalColor = mix(finalColor, wavelengthColor * (0.85 + bass * 0.4), tirMask * 0.8);
  
  finalColor = acesTonemap(max(finalColor, vec3<f32>(0.0)) * 1.25);

  let dispersionAlpha = length(caustic) * 0.6 + shardRing * 0.3 + speckleMask * 0.15 + clickFront * 0.3 + shapeEdge * 0.5;
  let finalAlpha = clamp(dispersionAlpha * holoContrast + held_intensity * 0.2 + bass * 0.1, 0.0, 1.0);

  let finalDisplayRGBA = vec4<f32>(finalColor, finalAlpha);
  let depthOut = clamp(depth + shardRing * 0.06 + shapeEdge * 0.1, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), finalDisplayRGBA);
  textureStore(dataTextureA, vec2<i32>(gid.xy), finalDisplayRGBA);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
