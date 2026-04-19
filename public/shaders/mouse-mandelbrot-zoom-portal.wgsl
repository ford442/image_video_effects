// ═══════════════════════════════════════════════════════════════════
//  mouse-mandelbrot-zoom-portal
//  Category: interactive-mouse
//  Features: mouse-driven, fractal, zoom-portals
//  Complexity: Very High
//  Chunks From: chunk-library.md (palette)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse position navigates the infinite Mandelbrot landscape.
//  Click ripples create nested zoom portals showing deeper levels.
//  The input image is used as a color palette for escape values.
//  Alpha channel stores smooth iteration count.
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

fn mandelbrot(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
  var z = vec2<f32>(0.0);
  var i = 0;
  for (; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  let smooth_i = select(f32(i), f32(i) - log2(log2(max(dot(z, z), 1.0001))) + 4.0, dot(z, z) > 1.0);
  return vec2<f32>(smooth_i, f32(maxIter));
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

  let zoomLevel = mix(0.5, 4.0, u.zoom_params.x);
  let maxIterBase = i32(mix(30.0, 200.0, u.zoom_params.y));
  let paletteSpeed = u.zoom_params.z * 2.0;
  let portalBlend = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;

  // Base view: mouse maps to complex plane center
  // Map uv to complex plane: center at mouse position
  let baseScale = exp2(-zoomLevel);
  let baseCenter = vec2<f32>(
    (mousePos.x - 0.5) * 3.0 - 0.5,
    (mousePos.y - 0.5) * 2.5
  );
  let baseCoord = baseCenter + (uv - 0.5) * vec2<f32>(baseScale * aspect, baseScale);

  // Compute base Mandelbrot
  let baseResult = mandelbrot(baseCoord, maxIterBase);
  let baseIter = baseResult.x;
  let baseMax = baseResult.y;

  // Default color from input image (used as palette)
  let paletteT = fract(baseIter / 50.0 + time * paletteSpeed * 0.1);
  let mandelColor = palette(paletteT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  // Check if inside set
  let insideSet = baseIter >= baseMax - 0.5;
  var finalColor = select(mandelColor, vec3<f32>(0.0), insideSet);
  var finalIter = baseIter;

  // Zoom portals from ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 5.0) {
      let portalCenter = ripple.xy;
      let portalDist = length((uv - portalCenter) * vec2<f32>(aspect, 1.0));
      let portalRadius = 0.15 * smoothstep(0.0, 0.5, elapsed) * smoothstep(5.0, 3.0, elapsed);
      let inPortal = smoothstep(portalRadius, portalRadius * 0.7, portalDist);

      if (inPortal > 0.01) {
        // Deeper zoom inside portal
        let depthScale = exp2(-zoomLevel - 3.0 - f32(i) * 0.5);
        let portalCoord = vec2<f32>(
          (portalCenter.x - 0.5) * 3.0 - 0.5,
          (portalCenter.y - 0.5) * 2.5
        ) + (uv - portalCenter) * vec2<f32>(depthScale * aspect, depthScale);

        let portalResult = mandelbrot(portalCoord, maxIterBase * 2);
        let portalIter = portalResult.x;
        let portalT = fract(portalIter / 50.0 + time * paletteSpeed * 0.1 + f32(i) * 0.2);
        let portalColor = palette(portalT,
          vec3<f32>(0.5, 0.5, 0.5),
          vec3<f32>(0.5, 0.5, 0.5),
          vec3<f32>(1.0, 0.8, 0.6),
          vec3<f32>(0.1, 0.4, 0.7)
        );

        let portalInside = portalIter >= portalResult.y - 0.5;
        let pColor = select(portalColor, vec3<f32>(0.05, 0.0, 0.1), portalInside);

        // Blend with portal edge glow
        let edgeGlow = smoothstep(portalRadius, portalRadius * 0.85, portalDist) -
                       smoothstep(portalRadius * 0.85, portalRadius * 0.7, portalDist);
        let glowColor = vec3<f32>(0.4, 0.8, 1.0) * edgeGlow * 2.0;

        finalColor = mix(finalColor, pColor + glowColor, inPortal * portalBlend);
        finalIter = mix(finalIter, portalIter, inPortal);
      }
    }
  }

  // Mix with original image so it's not pure generative
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  finalColor = mix(finalColor, inputColor * 0.5 + finalColor * 0.5, 0.3);

  // Alpha = smooth iteration count normalized
  let alpha = clamp(finalIter / f32(maxIterBase), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
