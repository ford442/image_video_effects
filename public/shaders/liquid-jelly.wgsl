// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Jelly Shader with Alpha Physics
//  Category: liquid-effects
//  Features: elastic bounce, volume shading, subsurface scattering simulation
//
//  ALPHA PHYSICS:
//  - Thickness from displacement magnitude
//  - Subsurface scattering approximation
//  - Fresnel at jelly boundaries
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate jelly alpha based on thickness and viewing angle
fn calculateJellyAlpha(
    thickness: f32,
    viewDotNormal: f32,
    subsurfaceFactor: f32
) -> f32 {
  // Jelly F0 slightly higher than water due to gel structure
  let F0 = 0.04;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Subsurface scattering reduces opacity
  // Thicker jelly = more scattering = more translucent
  let scattering = exp(-thickness * 2.0) * (1.0 - subsurfaceFactor * 0.3);
  
  // Base alpha: thicker = more opaque, but with scattering
  let baseAlpha = mix(0.5, 0.9, scattering);
  
  // Fresnel adds reflection at edges
  let alpha = baseAlpha * (1.0 - fresnel * 0.3);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate jelly color with subsurface scattering approximation
fn calculateJellyColor(
    baseColor: vec3<f32>,
    thickness: f32,
    shadowAccum: f32,
    wobble: f32
) -> vec3<f32> {
  // Subsurface scattering: light penetrates and scatters
  // Thinner areas = brighter, thicker = more saturated
  
  // Base scattering color (warm jelly tone)
  let scatterColor = vec3<f32>(1.0, 0.9, 0.7);
  
  // Thickness-based absorption
  let absorption = exp(-thickness * 1.5);
  
  // Mix base color with scattering
  let scattered = mix(scatterColor, baseColor, absorption);
  
  // Apply volume shadowing
  let shadowed = scattered * (1.0 - shadowAccum * 0.4);
  
  // Add wobble highlight
  let highlight = vec3<f32>(0.1, 0.15, 0.2) * wobble;
  
  return shadowed + highlight;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Mask: Only FG
  let fg_factor = 1.0 - smoothstep(0.8, 0.95, center_depth);

  var displacement = vec2<f32>(0.0);
  var shadow_accum = 0.0;
  var totalWobble = 0.0;

  if (fg_factor > 0.0) {
      let rippleCount = u32(u.config.y);
      for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rippleData = u.ripples[i];
        let timeSinceClick = currentTime - rippleData.z;

        if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
          let direction_vec = uv - rippleData.xy;
          let dist = length(direction_vec);

          // Elastic Bounce Logic
          let bounce_freq = 8.0;
          let decay = 2.0;
          let amplitude = 0.05; // Strong bulge
          let radius = 0.15;

          // Damped sine wave for the "wobble"
          let bounce = sin(timeSinceClick * bounce_freq) * exp(-timeSinceClick * decay);

          // Spatial shape: Smooth blob
          let shape = smoothstep(radius * 1.5, 0.0, dist);

          // Displacement: Push/Pull
          // Pushing outward makes the image look magnified/bulged.
          displacement += direction_vec * bounce * shape * amplitude * 10.0;

          // Fake ambient occlusion at the edges of the blob to simulate volume
          let edge = smoothstep(0.0, radius, dist) * smoothstep(radius, 0.0, dist);
          shadow_accum += edge * abs(bounce) * 2.0;
          
          // Track wobble magnitude
          totalWobble += abs(bounce) * shape;
        }
      }
  }

  // Apply masked displacement
  let finalDisplacement = displacement * fg_factor;
  let displacedUV = uv - finalDisplacement; // Subtract to "pull" texture (magnify)

  // Clamp
  let clampedUV = clamp(displacedUV, vec2(0.0), vec2(1.0));

  var baseColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Calculate jelly thickness from displacement magnitude
  let displacementMag = length(finalDisplacement);
  let jellyThickness = displacementMag * 5.0 + 0.2;
  
  // Approximate normal from displacement direction
  let normal = normalize(vec3<f32>(
      -finalDisplacement.x * 10.0,
      -finalDisplacement.y * 10.0,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  
  // Subsurface factor from wobble
  let subsurfaceFactor = smoothstep(0.0, 0.5, totalWobble);
  
  // Calculate jelly color with scattering
  let jellyColor = calculateJellyColor(baseColor, jellyThickness, shadow_accum, totalWobble);
  
  // Calculate alpha
  let alpha = calculateJellyAlpha(jellyThickness, viewDotNormal, subsurfaceFactor) * fg_factor;

  // Store with alpha
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(jellyColor, alpha));

  // Update depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
