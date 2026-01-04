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
  config: vec4<f32>;
  zoom_config: vec4<f32>;
  zoom_params: vec4<f32>;
  ripples: array<vec4<f32>, 50>;
};

// Mapping (engine conventions):
// - time -> u.config.x
// - zoomTime -> u.zoom_config.x
// - zoom center -> u.zoom_config.yz
// - depth_threshold -> u.zoom_config.w
// - zoom_params.x = fg_speed, y = bg_speed, z = parallax_str, w = fog_density
// - lighting_params and camera_params are packed into extraBuffer:
//    extraBuffer[0] = light_strength
//    extraBuffer[1] = ambient
//    extraBuffer[2] = normal_strength
//    extraBuffer[3] = dof_amount
//    extraBuffer[4] = cameraZ
//    extraBuffer[5] = fov
//    extraBuffer[6] = near_clip
//    extraBuffer[7] = far_clip

fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

fn reconstruct_normal(uv: vec2<f32>, depth: f32, resolution: vec2<f32>) -> vec3<f32> {
    let normal_strength = if (arrayLength(&extraBuffer) > 2u) { extraBuffer[2] } else { 1.0 };
    let offset_x = vec2<f32>(1.0 / resolution.x, 0.0);
    let offset_y = vec2<f32>(0.0, 1.0 / resolution.y);

    let depth_x1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_x, 0.0).r;
    let depth_x2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_x, 0.0).r;
    let depth_y1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_y, 0.0).r;
    let depth_y2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_y, 0.0).r;

    let p_dx = vec3<f32>(offset_x.x * 2.0, 0.0, (depth_x2 - depth_x1) * normal_strength);
    let p_dy = vec3<f32>(0.0, offset_y.y * 2.0, (depth_y2 - depth_y1) * normal_strength);
    return normalize(cross(p_dy, p_dx));
}

fn calculate_fog(depth: f32, color: vec3<f32>) -> vec3<f32> {
    let fog_density = u.zoom_params.w;
    let fog_falloff = if (arrayLength(&extraBuffer) > 3u) { extraBuffer[3] } else { 1.0 };
    let fog_color = vec3<f32>(0.05, 0.1, 0.08);
    let fog_factor = 1.0 - exp(-pow(depth, fog_falloff) * fog_density);
    return mix(color, fog_color, clamp(fog_factor, 0.0, 1.0));
}

// Sample a layer with perspective projection
fn sample_layer(uv: vec2<f32>, zoom_center: vec2<f32>, layer_depth: f32) -> vec4<f32> {
    let cameraZ = if (arrayLength(&extraBuffer) > 4u) { extraBuffer[4] } else { 0.0 };
    // Perspective scaling and zoom
    let perspective = 1.0 + cameraZ * (1.0 - layer_depth * 0.5);
    let zoom = 1.0 + layer_depth * 4.0;
    let scale = zoom * perspective;

    let transformed_uv = (uv - zoom_center) / scale + zoom_center;
    let wrapped_uv = ping_pong_v2(transformed_uv);

    let color = textureSampleLevel(readTexture, u_sampler, wrapped_uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;

    return vec4<f32>(color.rgb, depth);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;

    // Camera and parallax
    let cameraZ = if (arrayLength(&extraBuffer) > 4u) { extraBuffer[4] } else { 0.0 };
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let parallax = (mousePos - vec2<f32>(0.5, 0.5)) * u.zoom_params.z * cameraZ * 0.1;
    let parallax_uv = uv + parallax;

    // Raymarch through depth slices
    let num_slices: i32 = 5;
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_depth = 0.0;
    var total_weight = 0.0;

    for (var i: i32 = 0; i < num_slices; i = i + 1) {
        let slice_depth = f32(i) / f32(num_slices - 1);
        let layer = sample_layer(parallax_uv, zoom_center, slice_depth);
        let color = layer.rgb;
        let depth = layer.a;

        // Depth-of-field: weight based on focal plane
        let focal_depth = fract(zoom_time * u.zoom_params.x);
        let dof_amount = if (arrayLength(&extraBuffer) > 3u) { extraBuffer[3] } else { 1.0 };
        let dof_factor = exp(-abs(depth - focal_depth) * dof_amount * 10.0);

        // Volumetric density falloff
        let density = exp(-slice_depth * 2.0);

        let weight = dof_factor * density;
        accumulated_color = accumulated_color + color * weight;
        accumulated_depth = accumulated_depth + depth * weight;
        total_weight = total_weight + weight;
    }

    let final_color = accumulated_color / max(total_weight, 0.0001);
    let final_depth = accumulated_depth / max(total_weight, 0.0001);

    // Edge detection for specular highlight
    let pixel_size = 1.0 / resolution;
    let depth_x = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixel_size.x, 0.0), 0.0).r;
    let depth_y = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixel_size.y), 0.0).r;
    let depth_grad = length(vec2<f32>(depth_x - final_depth, depth_y - final_depth));

    let specular = pow(max(depth_grad * 10.0, 0.0), 16.0) * (if (arrayLength(&extraBuffer) > 0u) { extraBuffer[0] } else { 1.0 });

    // Lighting
    let normal = reconstruct_normal(uv, final_depth, resolution);
    let light_angle = zoom_time * 0.5;
    let light_pos = vec3<f32>(cos(light_angle), sin(light_angle), -1.5);
    let view_pos = vec3<f32>(uv - vec2<f32>(0.5, 0.5), cameraZ);
    let light_dir = normalize(light_pos - view_pos);
    let diffuse = max(dot(normal, light_dir), 0.0) * (if (arrayLength(&extraBuffer) > 0u) { extraBuffer[0] } else { 1.0 });

    let ambient = if (arrayLength(&extraBuffer) > 1u) { extraBuffer[1] } else { 0.2 };
    let lit_color = final_color * (ambient + diffuse) + vec3<f32>(specular);

    // Fog
    let fogged_color = calculate_fog(final_depth, lit_color);

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(fogged_color, 1.0));
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(final_depth, 0.0, 0.0, 0.0));
}