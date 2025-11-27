@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>; // Bound but unused for masking
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

  // --- Mouse-driven Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;

    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        // No depth factor here! Uniform effect.
        let ripple_speed = 2.0;
        let ripple_amplitude = 0.01;
        let wave = sin(dist * 25.0 - timeSinceClick * ripple_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        mouseDisplacement += (direction_vec / dist) * wave * ripple_amplitude * falloff * attenuation;
      }
    }
  }

  // --- Rainbow Logic ---
  let totalDisplacement = mouseDisplacement;
  let magnitude = length(totalDisplacement);

  // Dynamic color splitting
  // We oscillate the channel offsets based on time and displacement intensity
  let shift_speed = 0.5;
  let shift_amount = 0.005 + magnitude * 0.2; // More displacement = more split

  let r_offset = vec2<f32>(sin(currentTime * shift_speed), cos(currentTime * shift_speed)) * shift_amount;
  let g_offset = vec2<f32>(0.0, 0.0);
  let b_offset = vec2<f32>(sin(currentTime * shift_speed + 2.09), cos(currentTime * shift_speed + 2.09)) * shift_amount; // 2.09 is 2*pi/3

  // Apply displacement AND chromatic offset
  let r_uv = uv + totalDisplacement + r_offset;
  let g_uv = uv + totalDisplacement + g_offset;
  let b_uv = uv + totalDisplacement + b_offset;

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
  let a = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).a;

  textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, a));

  // Pass through original depth (we don't modify it, just keep it stable)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
