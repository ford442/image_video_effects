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

  let flareWidth = u.zoom_params.x * 20.0 + 1.0;
  let flareInt = u.zoom_params.y * 2.0;
  let colorShift = u.zoom_params.z;
  let threshold = u.zoom_params.w;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Anamorphic lens flare math
  // We want a horizontal streak centered at mousePos.
  // Actually, usually anamorphic flares happen at BRIGHT spots in the image.
  // But user request is "Mouse responsive".
  // So let's make the mouse the source of the flare.

  let dy = abs(uv.y - mousePos.y);
  let dx = abs(uv.x - mousePos.x);

  // Vertical falloff (sharp)
  let vFalloff = exp(-dy * dy * 1000.0 / flareWidth);

  // Horizontal falloff (long)
  let hFalloff = exp(-dx * 2.0);

  let flareShape = vFalloff * hFalloff;

  // Color calculation
  // Use a blue-ish tint common in anamorphic lenses, capable of shifting
  let tint = vec3<f32>(0.5, 0.7, 1.0); // Standard Sci-Fi Blue
  // Shift tint based on param
  let shiftVec = vec3<f32>(colorShift, colorShift * 0.5, 1.0 - colorShift);
  let finalTint = mix(tint, shiftVec, 0.5);

  // Add a central glow
  let aspect = resolution.x / resolution.y;
  let dist = length(vec2<f32>((uv.x - mousePos.x) * aspect, uv.y - mousePos.y));
  let glow = exp(-dist * 10.0) * 0.5;

  let flare = (flareShape + glow) * flareInt * finalTint;

  // Additive blending
  let finalColor = baseColor + vec4<f32>(flare, 0.0);

  textureStore(writeTexture, global_id.xy, finalColor);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
