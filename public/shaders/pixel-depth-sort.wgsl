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

  let mouse = u.zoom_config.yz;

  // Params
  let depth_scale = mix(0.0, 0.2, u.zoom_params.x); // Max displacement
  let shadow_str = u.zoom_params.y;
  let quality = u.zoom_params.z;

  let num_layers = mix(10.0, 60.0, quality);

  // Tilt direction based on mouse position relative to center
  // Invert mouse y for intuitive tilt
  let tilt = vec2<f32>(0.5 - mouse.x, 0.5 - mouse.y);

  let view_vec = tilt * depth_scale;

  var final_color = vec3<f32>(0.0);

  // Iterate back to front
  // i represents height (0.0 = background, 1.0 = foreground)
  for (var i = 0.0; i <= 1.0; i += 1.0 / num_layers) {
     let layer_height = i;
     // The "higher" the pixel is, the more it shifts relative to the base
     let offset = view_vec * layer_height;

     // We are looking for the pixel that *would be* at 'uv' if it were at 'layer_height'.
     // So we sample at 'uv + offset'.
     let sample_uv = uv + offset;

     if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
       let samp = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
       let luma = getLuma(samp);

       // If the sampled pixel's height (luma) is at least the current layer height,
       // then this pixel exists at this layer and occludes whatever was behind it.
       if (luma >= layer_height) {
         final_color = samp;

         // Simple rim shadowing
         if (luma < layer_height + 0.05 && shadow_str > 0.0) {
            final_color *= (1.0 - shadow_str * 0.5);
         }
       }
     }
  }

  textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
