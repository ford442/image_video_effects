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

// Hash function for per-vortex variation
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = 1.0 / resolution;

  // Vortex calculation
  var mouseDisplacement = vec2<f32>(0.0);
  var chromaticAccumulator = 0.0;
  let rippleCount = u32(u.config.y);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;

    if (timeSinceClick <= 0.0) {
      continue;
    }

    // Randomized vortex parameters based on position
    let vortexSeed = hash2(rippleData.xy * 100.0);
    let vortexDuration = mix(3.0, 6.0, vortexSeed);
    let chromaticStrength = mix(0.001, 0.005, hash2(rippleData.xy * 200.0));

    if (timeSinceClick < vortexDuration) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);

      if (dist > 0.0001) {
        // Fixed depth factor (assume surface)
        let rippleOriginDepthFactor = 0.5;

        // Vortex calculation: tangential velocity
        let tangent = vec2<f32>(-direction_vec.y, direction_vec.x);

        // Angular velocity
        let normalizedTime = timeSinceClick / vortexDuration;
        let angularVelocity = (1.0 - normalizedTime * normalizedTime) * 8.0;

        // Vortex strength (fixed mix)
        let vortex_amplitude = 0.05;

        // Falloff
        let falloff = 1.0 / (dist * 15.0 + 1.0);

        // Attenuation
        let attenuation = 1.0 - smoothstep(0.0, 1.0, normalizedTime);

        // Spiral component
        let spiralFactor = sin(normalizedTime * 3.14159) * 0.3;
        let radialComponent = (direction_vec / dist) * spiralFactor;

        let vortexDisplacement = (tangent * angularVelocity + radialComponent) * vortex_amplitude * falloff * attenuation;

        mouseDisplacement += vortexDisplacement;
        chromaticAccumulator += chromaticStrength * length(vortexDisplacement) * 100.0;
      }
    }
  }

  // 4 tap smoothing
  let smoothedDisplacement = mouseDisplacement * 0.7;

  let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0);
  let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixelSize.x, 0.0), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -pixelSize.y), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0);

  let neighborAvg = (right + left + up + down) * 0.25;
  let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cohesionEffect = (neighborAvg - centerColor) * 0.3;

  let finalMouseDisplacement = smoothedDisplacement + cohesionEffect.xy * 0.01;

  // --- Chromatic Aberration ---
  let totalDisplacement = finalMouseDisplacement; // No ambient
  let chromaticOffset = chromaticAccumulator * 0.5; // Removed depth modulation

  let redUV = uv + totalDisplacement * (1.0 + chromaticOffset);
  let greenUV = uv + totalDisplacement;
  let blueUV = uv + totalDisplacement * (1.0 - chromaticOffset);

  let redChannel = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
  let greenChannel = textureSampleLevel(readTexture, u_sampler, greenUV, 0.0).g;
  let blueChannel = textureSampleLevel(readTexture, u_sampler, blueUV, 0.0).b;
  let alpha = textureSampleLevel(readTexture, u_sampler, greenUV, 0.0).a;

  let color = vec4<f32>(redChannel, greenChannel, blueChannel, alpha);

  // --- Final Output ---
  textureStore(writeTexture, global_id.xy, color);

  // Update depth texture (propagate existing depth with displacement)
  let depthDisplacedUV = uv + finalMouseDisplacement;
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthDisplacedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
