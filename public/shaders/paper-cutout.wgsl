struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Params
  let num_layers = mix(2.0, 10.0, u.zoom_params.x);
  let shadow_dist = u.zoom_params.y * 0.1;
  let softness = u.zoom_params.z;
  let separation = u.zoom_params.w;

  // Mouse interaction for light direction
  // u.zoom_config.yz is mouse position (0-1)
  let mouse = u.zoom_config.yz;
  // If mouse is at 0,0 (init), center it
  let light_target = select(mouse, vec2<f32>(0.5, 0.5), mouse.x == 0.0 && mouse.y == 0.0);

  // Calculate light direction (from mouse to pixel, or paper casting shadow away from light)
  // Let's make mouse the light source. Shadows point AWAY from mouse.
  let aspect = u.config.z / u.config.w;
  let dist_vec = (uv - light_target) * vec2<f32>(aspect, 1.0);
  let light_dir = normalize(dist_vec);
  let dist_to_light = length(dist_vec);

  // Sample base color
  let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(base_color);

  // Quantize luma for "paper layers"
  let quantized_luma = floor(luma * num_layers) / num_layers;

  // Calculate shadow
  // We sample "upstream" (towards light) to see if there is a higher layer blocking light
  // Shadow offset depends on how "high" the blocking layer is.
  // Simplified: Check a fixed distance towards the light.

  var shadow = 0.0;
  let shadow_samples = 4;

  for (var i = 1; i <= shadow_samples; i++) {
    let t = f32(i) / f32(shadow_samples);
    let sample_offset = -light_dir * shadow_dist * t; // Look towards light
    let sample_uv = uv + sample_offset;

    // Boundary check
    if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
      continue;
    }

    let sample_col = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
    let sample_luma = getLuma(sample_col);
    let sample_quant = floor(sample_luma * num_layers) / num_layers;

    // If the sample is "higher" (brighter) than current pixel, it casts a shadow
    // We assume brighter = higher layer
    if (sample_quant > quantized_luma + separation) {
      shadow += (1.0 - t) * (1.0 - softness);
    }
  }

  shadow = clamp(shadow, 0.0, 0.8);

  // Re-construct color based on quantized luma (posterized look)
  // To keep color, we normalize base color by luma and multiply by quantized luma
  let norm_color = base_color / (luma + 0.001);
  let paper_color = norm_color * quantized_luma;

  // Apply shadow
  let final_color = paper_color * (1.0 - shadow);

  textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
