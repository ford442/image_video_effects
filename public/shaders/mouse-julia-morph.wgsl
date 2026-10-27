// ═══════════════════════════════════════════════════════════════════
//  mouse-julia-morph
//  Category: interactive-mouse
//  Features: mouse-driven, fractal, temporal, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: chunk-library.md (palette)
//  Created: 2026-04-18
//  By: Agent 2C
//  Upgraded: 2026-10-27
//  Ideas: orbit-trap filament glow; bass-driven zoom breathing; exterior distance rim; spiral palette from arg(z)
//  A packing: ACES display RGBA. Alpha stays normalized escape.
// ═══════════════════════════════════════════════════════════════════
//  Mouse position controls the Julia set constant c, morphing the
//  fractal in real time. Click ripples pin Julia configurations
//  that blend together. Input image serves as the color palette.
//  Alpha channel stores escape iteration count.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Returns (smooth escape, maxIter, exterior distance, argument of the final z).
fn julia(z0: vec2<f32>, c: vec2<f32>, maxIter: i32) -> vec4<f32> {
  var z = z0;
  var dz = vec2<f32>(1.0, 0.0);
  var i = 0;
  for (; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    dz = 2.0 * vec2<f32>(z.x * dz.x - z.y * dz.y, z.x * dz.y + z.y * dz.x);
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  let r2 = max(dot(z, z), 1.0001);
  let smooth_i = select(f32(i), f32(i) - log2(log2(r2)) + 4.0, dot(z, z) > 1.0);
  let radius = sqrt(r2);
  let de = clamp(0.5 * log(radius) * radius / max(length(dz), 0.001), 0.0, 1.0);
  return vec4<f32>(smooth_i, f32(maxIter), de, atan2(z.y, z.x));
}

// Idea 1: orbit-trap filament glow — same iteration as `julia`, but also
// tracks the closest the orbit ever comes to the origin. Points that graze
// the origin trace the fractal's own filament structure, which is exactly
// where a Julia set's finest boundary detail lives.
fn juliaOrbitTrap(z0: vec2<f32>, c: vec2<f32>, maxIter: i32) -> f32 {
  var z = z0;
  var trap = 1e9;
  for (var i = 0; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    trap = min(trap, dot(z, z));
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  return sqrt(trap);
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

  let bass = plasmaBuffer[0].x;
  // Idea 2: bass-driven zoom breathing — a gentle pulse on top of the
  // existing zoom param, so the fractal visibly breathes with the music.
  let zoom = mix(1.0, 4.0, u.zoom_params.x) * (1.0 - bass * 0.06);
  let maxIter = i32(mix(30.0, 150.0, u.zoom_params.y));
  let morphSpeed = u.zoom_params.z * 2.0;
  let rippleInfluence = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;

  // Current c from mouse position (mapped to classic Julia range)
  let currentC = vec2<f32>(
    (mousePos.x - 0.5) * 2.0,
    (mousePos.y - 0.5) * 2.0
  );

  // Auto-morph over time even without movement
  let autoC = vec2<f32>(
    cos(time * morphSpeed * 0.3) * 0.7,
    sin(time * morphSpeed * 0.5) * 0.4
  );
  let blendedC = mix(currentC, autoC, 0.3);

  // Map UV to complex plane
  let z0 = (uv - 0.5) * vec2<f32>(zoom * aspect, zoom);

  // Base Julia set
  let baseResult = julia(z0, blendedC, maxIter);
  let baseIter = baseResult.x;

  // Sample input image as palette based on escape value
  // ── Idea: spiral palette — arg(z) at escape slides the photo lookup along the arms.
  let paletteUV = vec2<f32>(fract(baseIter * 0.03 + baseResult.w * 0.05), fract(baseIter * 0.07 + 0.5));
  let paletteColor = textureSampleLevel(readTexture, u_sampler, paletteUV, 0.0).rgb;

  let inside = baseIter >= baseResult.y - 0.5;
  var finalColor = select(paletteColor, vec3<f32>(0.02, 0.0, 0.05), inside);
  var finalIter = baseIter;

  // Ripple pins: each ripple blends in its pinned Julia configuration
  let rippleCount = min(u32(u.config.y), 50u);
  var totalWeight = 0.0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 4.0) {
      let ripplePos = ripple.xy;
      let rDist = length((uv - ripplePos) * vec2<f32>(aspect, 1.0));
      let radius = 0.2 * smoothstep(0.0, 0.3, elapsed) * smoothstep(4.0, 2.0, elapsed);
      let weight = smoothstep(radius, 0.0, rDist) * rippleInfluence;

      if (weight > 0.001) {
        // Pinned c from ripple position
        let pinnedC = vec2<f32>(
          (ripplePos.x - 0.5) * 2.0 + sin(elapsed + f32(i)) * 0.1,
          (ripplePos.y - 0.5) * 2.0 + cos(elapsed + f32(i)) * 0.1
        );
        let pinnedResult = julia(z0, pinnedC, maxIter);
        let pinnedIter = pinnedResult.x;

        let pinPaletteUV = vec2<f32>(fract(pinnedIter * 0.03 + pinnedResult.w * 0.05 + f32(i) * 0.1), fract(pinnedIter * 0.07));
        let pinColor = textureSampleLevel(readTexture, u_sampler, pinPaletteUV, 0.0).rgb;

        let pinInside = pinnedIter >= pinnedResult.y - 0.5;
        let pColor = select(pinColor, vec3<f32>(0.05, 0.0, 0.1), pinInside);

        finalColor = mix(finalColor, pColor, weight);
        finalIter = mix(finalIter, pinnedIter, weight);
        totalWeight = totalWeight + weight;
      }
    }
  }

  // Boost saturation for psychedelic effect
  let lum = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  finalColor = mix(vec3<f32>(lum), finalColor, 1.3);

  // Idea 1: orbit-trap filament glow on the base fractal only — brightest
  // exactly where the orbit grazes the origin, tracing the finest boundary
  // filaments of this Julia set.
  let trap = juliaOrbitTrap(z0, blendedC, maxIter);
  let filament = pow(1.0 - clamp(trap, 0.0, 1.0), 8.0);
  finalColor = finalColor + vec3<f32>(0.9, 0.7, 1.0) * filament * 0.5;

  // ── Idea: exterior distance rim from the derivative of the same loop.
  let rim = smoothstep(0.12, 0.0, baseResult.z) * select(1.0, 0.0, inside);
  finalColor = mix(finalColor, finalColor * 0.2 + vec3<f32>(0.85, 0.92, 1.0) * 0.55, rim);
  finalColor = acesToneMap(finalColor);

  // Alpha = escape iteration count normalized
  let alpha = clamp(finalIter / f32(maxIter) + filament * 0.2 + rim * 0.15, 0.0, 1.0);
  let outColor = vec4<f32>(finalColor, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
