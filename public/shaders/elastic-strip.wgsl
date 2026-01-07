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
  let mouse = u.zoom_config.yz; // Mouse UV

  // Params
  let stripCount = mix(10.0, 100.0, u.zoom_params.x); // Density
  let strength = (u.zoom_params.y - 0.5) * 2.0;       // Stretch intensity (+/-)
  let falloff = u.zoom_params.z;                      // Radius of influence
  let direction = u.zoom_params.w;                    // > 0.5 Horizontal Strips (displace X)

  // Standard (direction < 0.5): Vertical Strips (bands vary along X), Displace Y.
  // Rotated (direction > 0.5): Horizontal Strips (bands vary along Y), Displace X.

  var stripCoord = uv.x;
  var displaceAxis = uv.y;
  var mouseStrip = mouse.x;
  var mouseDisplace = mouse.y;

  if (direction > 0.5) {
      stripCoord = uv.y;
      displaceAxis = uv.x;
      mouseStrip = mouse.y;
      mouseDisplace = mouse.x;
  }

  // Quantize strip coord to find which strip we are in
  let cell = floor(stripCoord * stripCount) / stripCount;
  // Center of the strip
  let stripCenter = cell + (0.5 / stripCount);

  // Distance from this strip to the mouse's strip
  let dist = abs(stripCenter - mouseStrip);

  // Gaussian influence based on distance
  let influence = exp(-pow(dist / (falloff * 0.5 + 0.01), 2.0));

  // Calculate shift
  // We shift the UV coordinate we sample from.
  // If we want to pull the image UP towards the mouse, we subtract from sample Y?
  // Let's make it follow the mouse.
  // shift = (mousePos - currentPos) * strength * influence
  // Simplified: relative to center.

  let shift = (mouseDisplace - 0.5) * strength * influence;

  var sourceUV = uv;

  if (direction > 0.5) {
     sourceUV.x -= shift;
  } else {
     sourceUV.y -= shift;
  }

  // Clamp to avoid artifacts at edges
  sourceUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let color = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

  textureStore(writeTexture, global_id.xy, color);

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
