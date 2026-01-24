// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Frequency, y=Distortion, z=Aberration, w=Complexity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Params
  let freq = mix(20.0, 200.0, u.zoom_params.x);
  let strength = u.zoom_params.y * 0.05;
  let abb = u.zoom_params.z * 0.02;
  let complexity = u.zoom_params.w;

  // Points
  let center = vec2<f32>(0.5 * aspect, 0.5);
  let mouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
  let current_uv = vec2<f32>(uv.x * aspect, uv.y);

  // Distances
  let d1 = distance(current_uv, center);
  let d2 = distance(current_uv, mouse);

  // Wave functions
  let w1 = sin(d1 * freq - time * 2.0);
  let w2 = sin(d2 * freq - time * 2.0);

  // Basic Interference
  var interference = w1 + w2;

  // Complexity adds a third point or modulates freq
  if (complexity > 0.0) {
      let d3 = distance(current_uv, mix(center, mouse, 0.5)); // midpoint
      let w3 = sin(d3 * freq * 1.5 + time);
      interference += w3 * complexity;
  }

  // Normalize roughly
  interference = interference * 0.5;

  // Distortion Vector
  // We displace along the gradient of the interference, or just radially?
  // Let's displace based on the interference value acting as a height map.
  // Simple hack: displace towards center masked by interference.
  let dir = normalize(uv - vec2<f32>(0.5));

  // Or better: Displace based on the derivative of the pattern?
  // Simpler: Use the interference value to offset UVs directly.
  let displacement = vec2<f32>(cos(interference * 3.14), sin(interference * 3.14)) * strength;

  // Sample with Aberration
  let r_uv = uv + displacement * (1.0 + abb * 10.0);
  let g_uv = uv + displacement;
  let b_uv = uv + displacement * (1.0 - abb * 10.0);

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Add interference bands visual overlay (optional)
  // Makes the "waves" visible as light/dark bands
  let bands = smoothstep(0.0, 0.1, abs(interference)) * 0.2 + 0.8;
  // color *= bands; // Maybe too intrusive? Let's keep it clean glass-like.

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
