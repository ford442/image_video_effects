// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Mouse position
  let mouse = u.zoom_config.yz;

  // Parameters
  // Param 1: Blur Strength (0.0 to 1.0) -> scaled for effect
  let strength = u.zoom_params.x * 0.5;

  // Param 2: Samples (mapped 5 to 50)
  // We can't use variable loop counts easily in all drivers without unrolling issues,
  // but a fixed max loop with early break or just fixed is safer.
  // Let's use fixed 30 samples for consistent performance.
  let samples = 30;

  var color = vec4<f32>(0.0);

  // Vector from current pixel to mouse
  let dir = mouse - uv;

  // Accumulate
  for (var i = 0; i < samples; i++) {
    let t = f32(i) / f32(samples - 1);
    // Non-linear sampling for better look? Or linear.
    // Linear is fine for standard radial blur.

    // Sample position: move towards mouse
    let offset = dir * strength * t;
    let sampleUV = uv + offset;

    // Clamp to valid UV? Texture sampler handles clamping/repeating based on config.
    // Usually 'repeat' or 'clamp-to-edge'.

    color += textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  }

  color = color / f32(samples);

  textureStore(writeTexture, global_id.xy, color);
}
