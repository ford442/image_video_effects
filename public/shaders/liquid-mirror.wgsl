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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // Params
  let distortion_amt = u.zoom_params.x * 0.2;
  let smoothness = u.zoom_params.y; // Unused but reserved for future noise scale
  let reflection_strength = u.zoom_params.z;
  let push_size = u.zoom_params.w * 0.5;

  // Liquid distortion from mouse
  let dist = distance(uv_corrected, mouse_corrected);
  var displacement = vec2<f32>(0.0);

  if (dist < push_size && dist > 0.001) {
    let push = (1.0 - dist / push_size);
    let dir = normalize(uv_corrected - mouse_corrected);
    displacement = dir * push * distortion_amt * sin(dist * 20.0 - time * 5.0);
  }

  // Base liquid noise (simplified sine waves for fluid feel)
  let noise_uv = uv * 3.0;
  let liquid_wave = vec2<f32>(
    sin(noise_uv.y * 5.0 + time) * 0.01,
    cos(noise_uv.x * 5.0 + time) * 0.01
  );

  let final_uv = uv + displacement + liquid_wave;

  // Sample texture with reflection feel (mirroring edges)
  let mirrored_uv = vec2<f32>(
      abs(fract(final_uv.x * 0.5) * 2.0 - 1.0), // Simple wrap mirroring
      abs(fract(final_uv.y * 0.5) * 2.0 - 1.0)
  );

  // Check if we want standard mirroring or just clamping
  // For a liquid mirror, let's just clamp/wrap cleanly or use the sampler's mode.
  // We'll trust the sampler (usually repeat or clamp) but adding a metallic tint.

  var color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;

  // Metallic effect: boost contrast and add a silver tint
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let metallic = vec3<f32>(luma * 1.2, luma * 1.25, luma * 1.3); // Slight blue tint

  color = mix(color, metallic, reflection_strength);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
