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

  var uv = vec2<f32>(global_id.xy) / resolution;
  var mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Fisheye Logic
  var center = mouse;
  let uv_centered = uv - center;

  // Aspect corrected vector
  let uv_aspect = vec2<f32>(uv_centered.x * aspect, uv_centered.y);
  let dist = length(uv_aspect);

  let strength = u.zoom_params.x;
  let radius = u.zoom_params.y;
  let curve = u.zoom_params.z * 2.0 + 0.5;
  let vignetteStrength = u.zoom_params.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let reactiveRadius = radius * (1.0 + bass * 0.2);

  var sampleUV = uv;
  if (dist < reactiveRadius) {
      let norm_dist = dist / reactiveRadius;
      let weight = pow(1.0 - norm_dist, curve);
      let factor = 1.0 - (strength * weight);
      sampleUV = mouse + uv_centered * factor;
  }

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  // Subtle vignette alpha falloff at the distortion radius edge
  var finalAlpha = color.a;
  if (dist < reactiveRadius) {
      let edgeFade = smoothstep(reactiveRadius * 0.85, reactiveRadius, dist);
      let vignetteAlpha = color.a * mix(1.0, 0.85, edgeFade);
      finalAlpha = mix(color.a, vignetteAlpha, vignetteStrength);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, finalAlpha));

  // Depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
