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

fn mod(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
  return x - y * floor(x / y);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  let aspect = f32(dims.x) / f32(dims.y);
  var uv_corrected = uv;
  uv_corrected.x *= aspect;

  // Params
  let grid_size = mix(10.0, 50.0, u.zoom_params.x);
  let brush_size = mix(0.1, 0.5, u.zoom_params.y);
  let shine = u.zoom_params.z;
  let gold_mix = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

  // Staggered Grid (Circle Packing)
  let row_height = 0.866; // sin(60)
  var grid_uv = uv_corrected * grid_size;

  // Determine row
  let row = floor(grid_uv.y / row_height);

  // Shift x if row is odd
  let is_odd = mod(vec2<f32>(row), vec2<f32>(2.0)).x;
  if (is_odd > 0.5) {
      grid_uv.x += 0.5;
  }

  let cell_id = floor(grid_uv);
  let local_uv = fract(grid_uv) * 2.0 - 1.0; // -1 to 1

  // Reconstruct center
  var world_center = vec2<f32>(cell_id.x + 0.5 - (is_odd * 0.5), (cell_id.y + 0.5) * row_height) / grid_size;

  // Distance to mouse from sequin center
  let dist = distance(world_center, mouse_corrected);

  // Influence (0 to 1)
  let influence = smoothstep(brush_size + 0.1, brush_size - 0.1, dist);

  // Rotation angle (radians)
  // 0 -> Image, PI -> Back
  let angle = influence * 3.14159;

  // Circle mask
  let radius = length(local_uv);
  if (radius > 0.9) {
      // Gaps
      textureStore(writeTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
      return;
  }

  let cos_a = cos(angle);
  let sin_a = sin(angle);

  // Project to surface
  // y_surf = y_screen / cos(angle)
  // Limit cos_a to avoid division by zero
  let cos_clamped = sign(cos_a) * max(abs(cos_a), 0.01);
  let tex_y = local_uv.y / cos_clamped;

  if (abs(tex_y) > 0.9) {
       // Clipped by disk tilt
       textureStore(writeTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
       return;
  }

  var col = vec3<f32>(0.0);
  var normal = vec3<f32>(0.0, 0.0, 1.0);

  if (cos_a >= 0.0) {
      // Front: Image
      var sample_uv = world_center;
      sample_uv.x /= aspect;
      // Clamp UV
      sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

      col = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

      // Plastic sphere normal
      let sphere_z = sqrt(max(0.0, 1.0 - local_uv.x*local_uv.x - tex_y*tex_y));
      normal = vec3<f32>(local_uv.x, tex_y, sphere_z);
  } else {
      // Back: Metal
      let metal_col = mix(vec3<f32>(0.8, 0.8, 0.9), vec3<f32>(1.0, 0.8, 0.2), gold_mix);
      col = metal_col;

      // Faceted normal
      let noise_n = sin(local_uv.x * 20.0) * sin(tex_y * 20.0);
      let sphere_z = sqrt(max(0.0, 1.0 - local_uv.x*local_uv.x - tex_y*tex_y));
      normal = normalize(vec3<f32>(local_uv.x + noise_n*0.2, tex_y + noise_n*0.2, sphere_z));
  }

  // Rotate normal
  var rot_normal = normal;
  rot_normal.y = normal.y * cos_a - normal.z * sin_a;
  rot_normal.z = normal.y * sin_a + normal.z * cos_a;
  rot_normal = normalize(rot_normal);

  // Light
  let light_dir = normalize(vec3<f32>(0.2, -0.5, 1.0));
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let half_vec = normalize(light_dir + view_dir);

  let NdotL = max(0.0, dot(rot_normal, light_dir));
  let NdotH = max(0.0, dot(rot_normal, half_vec));
  let spec = pow(NdotH, 20.0) * shine;

  // Fresnel/Rim
  let rim = 1.0 - max(0.0, dot(rot_normal, view_dir));
  col += vec3<f32>(rim * 0.2);

  col = col * (0.3 + 0.7 * NdotL) + vec3<f32>(spec);

  textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
