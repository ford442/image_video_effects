// ═══════════════════════════════════════════════════════════════════
//  Pin Art 3D
//  Category: image
//  Features: 3D-pin-art, specular-lighting, audio-reactive, mouse-interactive, depth-aware
//  Complexity: Medium-High
//  Created: 2026-04-18
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

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

fn luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    let density = u.zoom_params.x * 90.0 + 10.0;
    let pin_radius_factor = u.zoom_params.y * 0.5 + 0.4;
    let push_strength = u.zoom_params.z;
    let metallic = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 0.5 + depth * 0.5;

    let grid_uv = vec2<f32>(uv.x * aspect, uv.y) * density;
    let cell_id = floor(grid_uv);
    let cell_local = fract(grid_uv) - 0.5;

    let cell_center_uv_x = (cell_id.x + 0.5) / density / aspect;
    let cell_center_uv_y = (cell_id.y + 0.5) / density;
    let sample_uv = vec2<f32>(cell_center_uv_x, cell_center_uv_y);

    var color = vec4<f32>(0.0);
    if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
        color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
    }

    let luma = luminance(color.rgb);

    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let cell_center_aspect = vec2<f32>((cell_id.x + 0.5) / density, (cell_id.y + 0.5) / density);
    let dist_to_mouse = distance(mouse_aspect, cell_center_aspect);
    let influence_radius = 0.15;
    let push = smoothstep(influence_radius, 0.0, dist_to_mouse) * push_strength;

    // Bass-driven pin vibration
    let vibration = bass * 0.08 * sin(u.config.x * 20.0 + f32(cell_id.x) * 3.7 + f32(cell_id.y) * 2.3);
    let height = clamp(luma - push + vibration, 0.0, 1.0);

    let dist_from_center = length(cell_local);
    let pin_radius = 0.5 * pin_radius_factor;
    let aa = 0.02 * density;

    // Shadow
    let shadow_offset_dir = vec2<f32>(0.2, 0.2);
    let max_shadow_dist = 0.3;
    let shadow_pos = cell_local - shadow_offset_dir * height * max_shadow_dist;
    let dist_shadow = length(shadow_pos);
    let shadow_mask = 1.0 - smoothstep(pin_radius - aa, pin_radius + aa, dist_shadow);
    let shadow_alpha = 0.6 * shadow_mask;

    // Pin Head
    let pin_mask = 1.0 - smoothstep(pin_radius - aa, pin_radius + aa, dist_from_center);

    // Normal estimation for sphere cap
    let normal_xy = cell_local / pin_radius;
    var normal_z = 0.0;
    if (length(normal_xy) < 1.0) {
        normal_z = sqrt(1.0 - dot(normal_xy, normal_xy));
    }
    let normal = normalize(vec3<f32>(normal_xy, normal_z));

    // Depth-aware light angle
    let light_dir = normalize(vec3<f32>(-0.5 + depth * 0.3, -0.5, 1.0));
    let diffuse = max(dot(normal, light_dir), 0.0);

    let view_dir = vec3<f32>(0.0, 0.0, 1.0);
    let reflect_dir = reflect(-light_dir, normal);
    let spec = pow(max(dot(view_dir, reflect_dir), 0.0), 16.0) * metallic * (1.0 + treble);

    var final_color = vec3<f32>(0.05, 0.05, 0.05);
    final_color = mix(final_color, vec3<f32>(0.0), shadow_alpha);

    let shaded_pin = color.rgb * (0.3 + 0.7 * diffuse) + vec3<f32>(spec);

    // Chromatic aberration on pin highlights
    let caStrength = 0.003 * spec * (1.0 + bass);
    let caOffsetR = cell_local + vec2<f32>(caStrength, 0.0);
    let caOffsetB = cell_local - vec2<f32>(caStrength, 0.0);
    let normal_xy_r = caOffsetR / pin_radius;
    let normal_xy_b = caOffsetB / pin_radius;
    var normal_z_r = 0.0;
    var normal_z_b = 0.0;
    if (length(normal_xy_r) < 1.0) { normal_z_r = sqrt(1.0 - dot(normal_xy_r, normal_xy_r)); }
    if (length(normal_xy_b) < 1.0) { normal_z_b = sqrt(1.0 - dot(normal_xy_b, normal_xy_b)); }
    let normal_r = normalize(vec3<f32>(normal_xy_r, normal_z_r));
    let normal_b = normalize(vec3<f32>(normal_xy_b, normal_z_b));
    let diffuse_r = max(dot(normal_r, light_dir), 0.0);
    let diffuse_b = max(dot(normal_b, light_dir), 0.0);
    let shaded_pin_r = color.r * (0.3 + 0.7 * diffuse_r) + spec;
    let shaded_pin_b = color.b * (0.3 + 0.7 * diffuse_b) + spec;
    var ca_pin = shaded_pin;
    ca_pin.r = shaded_pin_r;
    ca_pin.b = shaded_pin_b;

    final_color = mix(final_color, ca_pin, pin_mask);

    // Temporal feedback: pin displacement persistence
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    final_color = mix(final_color, prev.rgb, 0.06 * (1.0 + bass));

    // ACES tone mapping
    final_color = acesToneMap(final_color * 1.2);

    // Depth boost
    final_color *= depthFactor;

    // Semantic alpha: pin coverage × specular intensity × depth
    let alpha = clamp(pin_mask * (1.0 + spec) * depthFactor, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
