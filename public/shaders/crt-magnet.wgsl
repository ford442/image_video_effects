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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  // Params
  let magStrength = (u.zoom_params.x - 0.5) * 4.0; // -2.0 to 2.0
  let radius = u.zoom_params.y * 0.4 + 0.05;
  let aberration = u.zoom_params.z * 0.05;
  let scanlineInt = u.zoom_params.w;

  // Calculate Distance to Mouse
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  // Correct aspect for circular field
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Magnetic Field Distortion
  // Exponential falloff
  let effect = magStrength * exp(-dist * dist / (radius * radius));

  // Displace UVs based on field
  // We displace the lookup coordinate.
  // If effect is positive (attract), we look closer to mouse?
  // Let's just apply displacement vector.
  let displacement = dVec * effect;

  let uv_r = uv - displacement;
  let uv_g = uv - displacement * (1.0 + aberration * 10.0); // Green channel slightly different
  let uv_b = uv - displacement * (1.0 + aberration * 20.0); // Blue channel more different

  // Sample Texture
  var r = textureSampleLevel(readTexture, u_sampler, clamp(uv_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, clamp(uv_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, clamp(uv_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Apply Scanlines (warped by Green channel UVs)
  let scanlineVal = sin(uv_g.y * resolution.y * 0.5) * 0.5 + 0.5;
  let scanline = mix(1.0, scanlineVal, scanlineInt);

  // Vignette for CRT feel
  let vigDist = length(uv - 0.5);
  let vignette = 1.0 - smoothstep(0.4, 0.7, vigDist) * 0.5;

  let finalColor = vec4<f32>(r, g, b, 1.0) * scanline * vignette;

  textureStore(writeTexture, global_id.xy, finalColor);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
