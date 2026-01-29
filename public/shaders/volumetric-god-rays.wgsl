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

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  // Params
  let density = u.zoom_params.x; // Density
  let decay = u.zoom_params.y;   // Decay
  let weight = u.zoom_params.z;  // Weight
  let exposure = u.zoom_params.w;// Exposure

  let numSamples = 64;

  // Calculate vector from pixel to light source (mouse)
  // Adjust aspect ratio for correct direction?
  // God rays usually work in UV space directly for the "smear" effect.

  let deltaTextCoord = (uv - mousePos);

  // Scale the step size by density.
  // If density is 0, steps are 0. If 1, steps cover more distance.
  // We divide by numSamples to distribute the steps.
  let step = (deltaTextCoord * density) / f32(numSamples);

  var currentUV = uv;
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Apply a threshold to the base color effectively so rays only come from bright spots?
  // Or just accumulate whatever is there. Standard algorithm accumulates whatever.
  // But let's boost it.

  var illuminationDecay = 1.0;
  var accumulatedColor = vec4<f32>(0.0);

  for (var i = 0; i < numSamples; i++) {
    currentUV = currentUV - step;

    // Sample
    var sampleColor = textureSampleLevel(readTexture, u_sampler, currentUV, 0.0);

    // Apply decay and weight
    sampleColor = sampleColor * illuminationDecay * weight;

    accumulatedColor = accumulatedColor + sampleColor;

    illuminationDecay = illuminationDecay * decay;
  }

  // Combine
  let finalColor = (color * ((1.0 - exposure) + 0.5)) + (accumulatedColor * exposure);
  // Note: The exposure mixing above is a bit arbitrary, but aiming for a balanced look.
  // Standard is: return color * exposure; (but we want to mix with original image)

  // Let's try simple additive blend:
  // let result = color + accumulatedColor * exposure;

  // Ensure alpha is 1.0
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, 1.0));

  // Pass through depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
