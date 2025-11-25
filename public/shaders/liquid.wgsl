@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // --- Ambient Displacement (Background Only) ---
  var ambientDisplacement = vec2<f32>(0.0, 0.0);
  let background_factor = 1.0 - smoothstep(0.0, 0.1, center_depth);

  if (background_factor > 0.0) {
    let time = currentTime * 0.5;
    let base_ambient_strength = 0.004;
    let ambient_freq = 15.0;
    let motion = vec2<f32>(sin(uv.y * ambient_freq + time * 1.2), cos(uv.x * ambient_freq + time));
    ambientDisplacement = motion * base_ambient_strength * background_factor;
  }
  
  // --- Mouse-driven Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = u.config.x - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let rippleOriginDepthFactor = 1.0 - textureSampleLevel(readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0).r;
        let ripple_speed = mix(1.0, 2.0, rippleOriginDepthFactor);
        let ripple_amplitude = mix(0.005, 0.015, rippleOriginDepthFactor);
        let wave = sin(dist * 25.0 - timeSinceClick * ripple_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / (3.0 * mix(0.5, 1.0, rippleOriginDepthFactor)));
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        mouseDisplacement += (direction_vec / dist) * wave * ripple_amplitude * falloff;
      }
    }
  }
  
  // --- Final Output ---
  let totalDisplacement = mouseDisplacement + ambientDisplacement;
  let colorDisplacedUV = uv + totalDisplacement;
  let color = textureSampleLevel(readTexture, u_sampler, colorDisplacedUV, 0.0);
  textureStore(writeTexture, global_id.xy, color);

  // Update depth texture for next frame
  let depthDisplacedUV = uv + mouseDisplacement;
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthDisplacedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
