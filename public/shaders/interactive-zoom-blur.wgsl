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
  let uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Mouse Input
  let mouse = u.zoom_config.yz; // 0..1
  var center = mouse;
  if (center.x < 0.0) { center = vec2<f32>(0.5, 0.5); }

  // Parameters
  let blurStrength = u.zoom_params.x * 0.1; // Max sample offset
  let samples = i32(mix(4.0, 32.0, u.zoom_params.y));
  let centerBias = u.zoom_params.z; // 0 = linear, 1 = concentrated at center
  let aberration = u.zoom_params.w * 0.05;

  let aspect = resolution.x / resolution.y;
  let uv_aspect = uv * vec2<f32>(aspect, 1.0);
  let center_aspect = center * vec2<f32>(aspect, 1.0);

  // Direction vector from pixel to mouse center
  let dir = center_aspect - uv_aspect;
  // Normalize direction but keep length for falloff if needed?
  // Standard zoom blur samples along the vector towards the center.

  // We need dir in UV space (undo aspect for sampling)
  let dirUV = center - uv;

  var color = vec3<f32>(0.0);
  var totalWeight = 0.0;

  // Random dither to break banding
  let random = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);

  for (var i = 0; i < samples; i++) {
      let t = (f32(i) + random) / f32(samples);

      // Non-linear sampling weight
      let weight = 1.0;
      if (centerBias > 0.0) {
          weight = mix(1.0, 1.0 - t, centerBias);
      }

      let percent = t * blurStrength;

      // Sample R, G, B with slight offsets for aberration
      let sampleUV = uv + dirUV * percent;

      let r = textureSampleLevel(readTexture, u_sampler, sampleUV - dirUV * aberration * t, 0.0).r;
      let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
      let b = textureSampleLevel(readTexture, u_sampler, sampleUV + dirUV * aberration * t, 0.0).b;

      color += vec3<f32>(r, g, b) * weight;
      totalWeight += weight;
  }

  color = color / totalWeight;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
