// ═══════════════════════════════════════════════════════════════════
//  mouse-julia-morph
//  Category: interactive-mouse
//  Features: mouse-driven, fractal, temporal
//  Complexity: High
//  Chunks From: chunk-library.md (palette)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse position controls the Julia set constant c, morphing the
//  fractal in real time. Click ripples pin Julia configurations
//  that blend together. Input image serves as the color palette.
//  Alpha channel stores escape iteration count.
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

// ═══ CHUNK: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn julia(z0: vec2<f32>, c: vec2<f32>, maxIter: i32) -> vec2<f32> {
  var z = z0;
  var i = 0;
  for (; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  let smooth_i = select(f32(i), f32(i) - log2(log2(max(dot(z, z), 1.0001))) + 4.0, dot(z, z) > 1.0);
  return vec2<f32>(smooth_i, f32(maxIter));
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

  let zoom = mix(1.0, 4.0, u.zoom_params.x);
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
  let paletteUV = vec2<f32>(fract(baseIter * 0.03), fract(baseIter * 0.07 + 0.5));
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

        let pinPaletteUV = vec2<f32>(fract(pinnedIter * 0.03 + f32(i) * 0.1), fract(pinnedIter * 0.07));
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

  // Alpha = escape iteration count normalized
  let alpha = clamp(finalIter / f32(maxIter), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
