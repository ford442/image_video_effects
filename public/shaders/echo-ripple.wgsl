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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let mouse = u.zoom_config.yz;

  // Params
  let frequency = u.zoom_params.x * 20.0 + 5.0; // Ripple density
  let speed = u.zoom_params.y * 5.0;            // Ripple expansion
  let decay = u.zoom_params.z;                  // Trail persistence
  let strength = u.zoom_params.w * 0.1;         // Distortion amount

  // Aspect correct UV for distance calc
  var uv_corrected = uv;
  uv_corrected.x *= aspect;
  var mouse_corrected = mouse;
  mouse_corrected.x *= aspect;

  let dist = distance(uv_corrected, mouse_corrected);

  // Ripple Wave Calculation
  // sin(dist * freq - time * speed)
  let wave = sin(dist * frequency - time * speed);

  // Attenuate with distance from mouse
  let attenuation = smoothstep(0.8, 0.0, dist);
  let distort_amt = wave * strength * attenuation;

  // Direction from mouse to pixel
  var dir = uv - mouse;
  if (length(dir) > 0.001) {
    dir = normalize(dir);
  } else {
    dir = vec2<f32>(0.0);
  }

  // Sample distorted texture
  let final_uv = uv - dir * distort_amt;
  let current_color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;

  // Read history (feedback)
  let history_color = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;

  // Add some chromatic aberration to the ripple edge
  let ripple_color = vec3<f32>(
    wave * 0.1,
    wave * 0.05,
    -wave * 0.1
  ) * attenuation * strength * 20.0;

  // Blend
  // If decay is high, we keep more history.
  // But we want the ripple to "echo".
  // Let's mix history and current based on decay.
  let mixed_color = mix(current_color + ripple_color, history_color, decay);

  // Write outputs
  textureStore(writeTexture, global_id.xy, vec4<f32>(mixed_color, 1.0));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mixed_color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
