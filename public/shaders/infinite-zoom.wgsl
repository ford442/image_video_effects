@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,        // time, unused, resolutionX, resolutionY
  zoom_config: vec4<f32>,  // zoomTime, zoomCenterX, zoomCenterY, depth_threshold
  zoom_params: vec4<f32>,  // fg_speed, bg_speed, parallax_str, fog_density
  lighting_params: vec4<f32>, // light_strength, ambient, normal_strength, fog_falloff
};

@group(0) @binding(3) var<uniform> u: Uniforms;

fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

// --- IMPROVEMENT 3: Normal Reconstruction ---
// Reconstructs a surface normal from the depth texture by sampling neighbor pixels.
fn reconstruct_normal(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let resolution = u.config.zw;
    let normal_strength = u.lighting_params.z;

    let offset_x = vec2<f32>(1.0 / resolution.x, 0.0);
    let offset_y = vec2<f32>(0.0, 1.0 / resolution.y);

    // Sample depth at neighboring pixels
    let depth_x1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_x, 0.0).r;
    let depth_x2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_x, 0.0).r;
    let depth_y1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_y, 0.0).r;
    let depth_y2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_y, 0.0).r;

    // Create two vectors on the surface plane.
    // The Z component is scaled by normal_strength to control the "height" of the terrain.
    let p_dx = vec3<f32>(offset_x.x * 2.0, 0.0, (depth_x2 - depth_x1) * normal_strength);
    let p_dy = vec3<f32>(0.0, offset_y.y * 2.0, (depth_y2 - depth_y1) * normal_strength);

    // The normal is the cross product of these two vectors.
    // The direction is flipped to point "out" of the screen (towards the camera, positive Z).
    let n = normalize(cross(p_dy, p_dx));

    return n;
}

// --- IMPROVEMENT 2: Atmospheric Fog ---
// Calculates fog using a more physically-based exponential falloff.
fn calculate_fog(depth: f32, color: vec3<f32>) -> vec3<f32> {
    let fog_density = u.zoom_params.w;
    let fog_falloff = u.lighting_params.w;
    let fog_color = vec3<f32>(0.05, 0.1, 0.08);

    // Exponential fog provides a more natural falloff.
    // pow(depth, fog_falloff) makes the fog appear more suddenly in the distance.
    let fog_factor = 1.0 - exp(-pow(depth, fog_falloff) * fog_density);

    return mix(color, fog_color, clamp(fog_factor, 0.0, 1.0));
}

// samples a transformed UV for both color and depth
fn sample_layer(uv: vec2<f32>, zoom_time: f32, zoom_center: vec2<f32>) -> vec4<f32> {
  let transformed_uv = (uv - zoom_center) * zoom_time + zoom_center;
  let wrapped_uv = ping_pong_v2(transformed_uv);

  let color = textureSampleLevel(readTexture, non_filtering_sampler, wrapped_uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;

  return vec4(color.rgb, depth);
}

// Calculate the depth of the foreground layer for a given screen UV.
fn get_fg_depth_at(uv: vec2<f32>, zoom_center: vec2<f32>, scale: f32) -> f32 {
    let transformed_uv = (uv - zoom_center) / scale + zoom_center;
    let wrapped_uv = ping_pong_v2(transformed_uv);
    return textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let zoom_time = u.zoom_config.x;
  let zoom_center = u.zoom_config.yz;

  // --- Foreground layer (zooming towards camera) ---
  let fg_speed = u.zoom_params.x;
  let zoom_progress = fract(zoom_time * fg_speed);
  let scale = 1.0 + zoom_progress * 4.0; // zoom_intensity = 4.0

  let transformed_uv = (uv - zoom_center) / scale + zoom_center;
  let wrapped_uv = ping_pong_v2(transformed_uv);

  var fg_color = textureSampleLevel(readTexture, non_filtering_sampler, wrapped_uv, 0.0);
  let fg_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;

  // --- Background layer (the next image zooming in from the center) ---
  let bg_speed = u.zoom_params.y;
  let next_zoom_progress = fract(zoom_time * bg_speed + 0.5); // use offset
  let next_scale = 1.0 + next_zoom_progress * 4.0;

  let next_transformed_uv = (uv - zoom_center) / next_scale + zoom_center;
  let next_wrapped_uv = ping_pong_v2(next_transformed_uv);

  let bg_color = textureSampleLevel(readTexture, non_filtering_sampler, next_wrapped_uv, 0.0);

  // --- IMPROVEMENT 1: Gradient-Based Anti-Aliasing for Depth Cutout ---
  // Instead of alpha blending fullscreen layers, we cut a "hole" in the foreground
  // to reveal the background, and anti-alias the edge of this hole.
  let depth_threshold = u.zoom_config.w;
  let dist = fg_depth - depth_threshold;

  // Manual gradient calculation since dpdx/dpdy are not available in compute shaders
  let pixel_size = 1.0 / resolution;
  let dist_x = get_fg_depth_at(uv + vec2(pixel_size.x, 0.0), zoom_center, scale) - depth_threshold;
  let dist_y = get_fg_depth_at(uv + vec2(0.0, pixel_size.y), zoom_center, scale) - depth_threshold;

  let gradient = length(vec2(dist_x - dist, dist_y - dist));

  // Create a smooth transition across the edge based on its screen-space sharpness.
  // The '2.0' is a softness factor you can tune.
  let edge_alpha = smoothstep(-gradient * 2.0, gradient * 2.0, dist);

  var final_color = mix(bg_color, fg_color, edge_alpha);

  // --- IMPROVEMENT 3: Dynamic Lighting ---
  let light_strength = u.lighting_params.x;
  let ambient = u.lighting_params.y;

  // Reconstruct surface normal from the final, combined depth map.
  // We use the depth of whichever layer is visible.
  let final_depth = mix(
      textureSampleLevel(readDepthTexture, non_filtering_sampler, next_wrapped_uv, 0.0).r,
      fg_depth,
      edge_alpha
  );
  let normal = reconstruct_normal(uv, final_depth);

  // Create a moving light source (sun) that orbits.
  let light_angle = zoom_time * 0.5;
  let light_pos = vec3<f32>(cos(light_angle), sin(light_angle), -1.5); // Behind camera

  // Calculate Lambertian diffuse lighting
  let surface_pos = vec3<f32>(uv.x, uv.y, final_depth);
  let light_dir = normalize(light_pos - surface_pos);
  let diffuse = max(dot(normal, light_dir), 0.0);

  // Apply lighting: ambient + diffuse
  let lighting = ambient + diffuse * light_strength;
  final_color = vec4<f32>(final_color.rgb * lighting, final_color.a);

  // --- IMPROVEMENT 2: Apply Atmospheric Fog ---
  // Fog is applied after lighting.
  final_color = vec4<f32>(calculate_fog(final_depth, final_color.rgb), final_color.a);

  textureStore(writeTexture, global_id.xy, vec4(final_color.rgb, 1.0));

  // --- Depth Texture Update ---
  // Write the final, combined depth value to the output depth texture.
  // This ensures the depth feedback loop matches the color feedback loop.
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(final_depth, 0.0, 0.0, 0.0));
}
