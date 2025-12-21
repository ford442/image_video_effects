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

  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = vec2<f32>(1.0) / resolution;

  // Mouse acts as the light source
  let mouse = u.zoom_config.yz;

  // Vector from pixel to mouse (Light Direction)
  // We want the light to come FROM the mouse.
  // So direction is normalize(mouse - uv).
  // But for simple emboss, usually we dot the gradient with light direction.

  let light_vec = mouse - uv;
  // Normalize, but handle zero length
  var light_dir = vec2<f32>(0.0, 0.0);
  if (length(light_vec) > 0.001) {
    light_dir = normalize(light_vec);
  }

  // Parameters
  let strength = u.zoom_params.x * 5.0; // Scale up for visibility. Default 0.5 -> 2.5
  let mix_amt = u.zoom_params.y;        // 0.0 = Emboss only, 1.0 = Original image
  let color_mode = u.zoom_params.z;     // 0.0 = Gray Emboss, 1.0 = Color Emboss

  // Sample neighbors for Sobel-ish gradient
  // -1 0 1
  // -2 0 2
  // -1 0 1

  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(texel.x, 0.0), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, texel.y), 0.0).rgb;

  // Calculate luminance for height map approx
  let l_lum = dot(l, vec3(0.299, 0.587, 0.114));
  let r_lum = dot(r, vec3(0.299, 0.587, 0.114));
  let t_lum = dot(t, vec3(0.299, 0.587, 0.114));
  let b_lum = dot(b, vec3(0.299, 0.587, 0.114));

  // Gradient vector (dx, dy)
  let dx = (l_lum - r_lum); // Left is higher? Or Right?
  // If light comes from right, and right pixel is darker (lower), it's in shadow?
  // Let's just stick to dot product logic.
  let dy = (t_lum - b_lum);

  let grad = vec2<f32>(dx, dy);

  // Emboss value: dot product of gradient and light direction
  let diff = dot(grad, light_dir) * strength;

  // Gray emboss base
  let gray_emboss = vec3<f32>(0.5 + diff);

  // Color emboss: Add diff to original color
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let color_emboss = c + vec3<f32>(diff);

  let result_emboss = mix(gray_emboss, color_emboss, step(0.5, color_mode));

  // Mix with original based on parameter
  let final_color = mix(result_emboss, c, 1.0 - mix_amt); // If mix_amt is "Effect Strength", then 1.0 means full effect.
  // Wait, I said param y is "mix_amt". Let's name it "Intensity" in JSON.
  // If Intensity = 1.0, we see full emboss.

  textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

  // Pass depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
