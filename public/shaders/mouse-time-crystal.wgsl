// ═══════════════════════════════════════════════════════════════════
//  mouse-time-crystal
//  Category: interactive-mouse
//  Features: mouse-driven, temporal, crystal-growth, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-20
//  Ideas: growth-face glint; cooling rim; density veins
//  A packing: raw (age, branchID, density, temperature); ACES on display only
// ═══════════════════════════════════════════════════════════════════
//  Mouse clicks seed crystal growth points. Crystals grow over time
//  using diffusion-limited aggregation modulated by image luminance.
//  Crystal branches follow the image's natural gradients. Uses
//  dataTextureC for persistent crystal state.
//  Alpha = crystal color temperature (age gradient).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let growthRate = mix(0.3, 1.5, u.zoom_params.x);
  let crystalDensity = mix(0.5, 3.0, u.zoom_params.y);
  let ageColorSpeed = mix(0.1, 1.0, u.zoom_params.z);
  let glowIntensity = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let coord = vec2<i32>(global_id.xy);
  let hi = vec2<i32>(resolution) - vec2<i32>(1);

  // Read previous crystal state (R=age, G=branchID, B=density, A=temperature)
  let prevState = textureLoad(dataTextureC, coord, 0);
  var crystalAge = prevState.r;
  var branchID = prevState.g;
  var density = prevState.b;
  var temperature = prevState.a;

  // Sample image for growth modulation
  let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(imageColor);

  // Growth probability based on image edges (luminance variation)
  let px = 1.0 / resolution;
  let right = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb);
  let up = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb);
  let gradient = abs(luma - right) + abs(luma - up);

  // Seed new crystals from ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 5.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let seedRadius = 0.03 * smoothstep(0.0, 0.5, elapsed);
      if (rDist < seedRadius && crystalAge < 0.01) {
        crystalAge = elapsed;
        branchID = f32(i) + 1.0;
        density = 1.0;
        temperature = 1.0;
      }
    }
  }

  // Crystal growth: DLA-like expansion from existing crystals
  if (crystalAge > 0.0) {
    crystalAge = crystalAge + 0.016 * growthRate * (1.0 + bass * 0.25);
    // ── Idea 2: cooling rim ───────────────────────────────────────
    // Flat interiors lose heat. The growth front stays hot.
    let front = clamp(gradient * 3.0, 0.0, 1.0);
    temperature = temperature * mix(0.988, 0.998, front);

    // Diffuse density to neighbors (simulate aggregation)
    let n = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
    let s = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), hi), 0);
    let e = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
    let w = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), hi), 0);

    // If neighbor is crystallized and we're not, chance to crystallize
    let neighborAge = max(max(n.r, s.r), max(e.r, w.r));
    let neighborBranch = select(n.g, s.g, s.r > n.r);
    let neighborDensity = max(max(n.b, s.b), max(e.b, w.b));

    if (crystalAge < 0.1 && neighborAge > 0.1) {
      let growthProb = gradient * crystalDensity * 0.5 + hash12(uv * 100.0 + time) * 0.3;
      if (growthProb > 0.4) {
        crystalAge = neighborAge;
        branchID = neighborBranch;
        density = neighborDensity * 0.95 + gradient;
        temperature = 1.0;
      }
    }

    density = min(density * 1.001, 3.0);
  }

  // Color based on crystal age and branch
  let ageColor = palette(
    fract(branchID * 0.1 + crystalAge * ageColorSpeed * 0.1),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 0.8),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  // Mix with base image
  let crystalMask = smoothstep(0.0, 0.05, crystalAge);
  var finalColor = mix(imageColor, ageColor * (0.5 + luma), crystalMask * 0.8);

  // Temperature glow
  let tempGlow = temperature * glowIntensity * crystalMask;
  finalColor = finalColor + vec3<f32>(0.8, 0.6, 0.4) * tempGlow;

  // Mouse proximity accelerates nearby crystal growth visually
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseHeat = exp(-mouseDist * mouseDist * 200.0) * 0.2;
  finalColor = finalColor + vec3<f32>(1.0, 0.9, 0.7) * mouseHeat * crystalMask;

  // ── Idea 1: growth-face glint ─────────────────────────────────
  // The luma gradient that already steers sticking is the face normal.
  let face = vec2<f32>(luma - right, luma - up);
  let faceN = face / max(length(face), 0.0001);
  let light2 = normalize(vec2<f32>(0.45, 0.75));
  let glint = pow(max(dot(faceN, light2), 0.0), 16.0) * crystalMask * (0.12 + glowIntensity * 0.4);
  finalColor = finalColor + vec3<f32>(0.85, 0.95, 1.0) * glint;

  // ── Idea 3: density veins ─────────────────────────────────────
  let vein = smoothstep(0.6, 2.4, density) * crystalMask;
  finalColor = mix(finalColor, finalColor * vec3<f32>(0.52, 0.6, 0.68), vein * 0.4);
  finalColor = aces(max(finalColor, vec3<f32>(0.0)));

  // Store crystal state
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(crystalAge, branchID, density, temperature));

  // Alpha = crystal color temperature (maps to warm/cool)
  let alpha = clamp(temperature * 0.5 + crystalMask * 0.4 + glint * 0.25 + vein * 0.1, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
