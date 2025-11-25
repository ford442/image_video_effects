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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Mask: Only FG
  let fg_factor = 1.0 - smoothstep(0.8, 0.95, center_depth);

  var displacement = vec2<f32>(0.0);
  var shadow_accum = 0.0;

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
        }
      }
  }

  // Apply masked displacement
  let finalDisplacement = displacement * fg_factor;
  let displacedUV = uv - finalDisplacement; // Subtract to "pull" texture (magnify)

  // Clamp
  let clampedUV = clamp(displacedUV, vec2(0.0), vec2(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

  // Apply "volume shading" (fake shadows/highlights based on wobble)
  let shading = 1.0 - (shadow_accum * 0.3 * fg_factor);
  color *= shading;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Update depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
