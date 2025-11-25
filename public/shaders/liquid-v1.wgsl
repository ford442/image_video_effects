@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
  let A = 2.5101;
  let B = 0.03;
  let C = 2.43;
  let D = 0.59;
  let E = 0.14;
  let hdr_color = color * (A * color + B);
  return clamp(hdr_color / (color * (C * color + D) + E), vec3(0.0), vec3(1.0));
}

fn antialias_depth_sample(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texel_size: vec2<f32>) -> f32 {
 let offset = texel_size * 0.5;
 let s0 = textureSampleLevel(tex, samp, uv - offset, 0.0).r;
 let s1 = textureSampleLevel(tex, samp, uv + offset, 0.0).r;
 let s2 = textureSampleLevel(tex, samp, uv + vec2<f32>(offset.x, -offset.y), 0.0).r;
 let s3 = textureSampleLevel(tex, samp, uv + vec2<f32>(-offset.x, offset.y), 0.0).r;
 return (s0 + s1 + s2 + s3) * 0.25;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
    
  // --- Parallax Logic (Unchanged) ---
  let static_depth_for_motion = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax_time = time * 0.5;
  let base_ambient_strength = 0.013;
  let ambient_freq = 13.0;
  let motion = vec2<f32>(sin(uv.y * ambient_freq + parallax_time * 1.2), cos(uv.x * ambient_freq + parallax_time));
  let background_displacement = motion * base_ambient_strength;
  let fg_rate = 0.79;
  let base_fg_strength = 0.017;
  let fg_freq = 22.0;
  let fg_time = time * fg_rate;
  let fg_d1 = sin(uv.x * fg_freq + fg_time);
  let fg_d2 = cos(uv.y * fg_freq * 1.3 + fg_time);
  let base_foreground_motion = vec2<f32>(fg_d1, fg_d2);
  let motion_gradient = pow(1.0 - smoothstep(0.0, 0.5, static_depth_for_motion), 2.5);
  var final_displacement = background_displacement + (base_foreground_motion * base_fg_strength * motion_gradient);
  let border_thickness = 0.1;
  let fade_start = 0.5 - border_thickness;
  let fade_end = 0.5;
  let centered_uv = uv - 0.5;
  let edge_factor_x = 1.0 - smoothstep(fade_start, fade_end, abs(centered_uv.x));
  let edge_factor_y = 1.0 - smoothstep(fade_start, fade_end, abs(centered_uv.y));
  let edge_fade = min(edge_factor_x, edge_factor_y);
  final_displacement *= edge_fade;
  var displacedUV = uv + final_displacement;

// --- Sampling & AA (Unchanged from original) ---
let sharp_visual_depth_original = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;
let aa_visual_depth_original = antialias_depth_sample(readDepthTexture, non_filtering_sampler, displacedUV, pixelSize);
var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

// --- MODIFICATION: Z-AXIS WAVER ---
let waver_frequency = 15.0;
let waver_amplitude = 0.03; // Keep this small! A little goes a long way.
let waver_speed = 1.5;

// Create a wave that ripples across the image. Using uv.x makes it different from other motions.
let z_waver = sin(uv.x * waver_frequency + time * waver_speed) * waver_amplitude;

// Apply the waver only to foreground objects, using the same gradient as the XY motion.
let z_waver_amount = z_waver * motion_gradient;

// Create the new, wavering depth values.
// We add the waver to the original depth.
// We also clamp it to ensure the depth value stays in the valid 0.0 to 1.0 range.
var aa_visual_depth = clamp(aa_visual_depth_original + z_waver_amount, 0.0, 1.0);
var sharp_visual_depth = clamp(sharp_visual_depth_original + z_waver_amount, 0.0, 1.0);
// --- END OF Z-AXIS MODIFICATION ---

  // --- Atmospheric Effects ---
  let bg_shadow_color = vec4<f32>(0.12, 0.12, 0.15, 1.0);  
  let bg_shadow_intensity = smoothstep(0.4, 0.9, aa_visual_depth) * 0.777;
  color = mix(color, bg_shadow_color, bg_shadow_intensity);
  let foreground_fog_color = vec3<f32>(0.6, 0.6, 0.7);
  let foreground_fog_intensity = smoothstep(0.2, 0.8, 1.0 - aa_visual_depth) * 0.38;
  let new_rgb_with_fog = color.rgb + (foreground_fog_color * foreground_fog_intensity);
  color = vec4<f32>(new_rgb_with_fog, color.a);
  
  let foreground_shadow_color = vec4<f32>(0.02, 0.02, 0.05, 1.0);
  let foreground_shadow_intensity = smoothstep(0.75, 0.0, aa_visual_depth) * 0.95;

  // --- Shared Light Calculations (Unchanged) ---
  let depth_right = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
  let depth_up = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV + vec2<f32>(0.0, pixelSize.y), 0.0).r;
  let normal_factor = abs(sharp_visual_depth - depth_right) + abs(sharp_visual_depth - depth_up);
  let specular_sheen = smoothstep(0.01, 0.05, normal_factor) * 1.5;

  // --- Two Sunrays and New Lighting Model (FIXED) ---
  let sunray1_pos = vec2<f32>(0.5 + sin(time * 0.25) * 0.4, 1.3);
  let ray_stretch_factor1 = vec2<f32>(1.0, 0.15);
  let dist_to_sunray1 = distance(uv * ray_stretch_factor1, sunray1_pos * ray_stretch_factor1);
  let base_sunray1 = (1.0 - smoothstep(0.0, 0.18, dist_to_sunray1)) * pow(1.0 - aa_visual_depth, 2.5);
  let sunray2_pos = vec2<f32>(0.5 + cos(time * -0.2) * 0.5, 1.35);
  let ray_stretch_factor2 = vec2<f32>(1.0, 0.2);
  let dist_to_sunray2 = distance(uv * ray_stretch_factor2, sunray2_pos * ray_stretch_factor2);
  let base_sunray2 = (1.0 - smoothstep(0.0, 0.15, dist_to_sunray2)) * pow(1.0 - aa_visual_depth, 2.5);
  
  let total_sunray_intensity = clamp(base_sunray1 * 1.5 + base_sunray2 * 1.3, 0.0, 1.0);
  let sunray_specular = specular_sheen * total_sunray_intensity * 1.5;
  let sunray_color = vec3<f32>(1.0, 0.95, 0.85);

  let FOREGROUND_LIT_MULTIPLIER = 2.2;
  // FIX: Use a constant mix factor for the shadow instead of the per-pixel intensity.
  // This breaks the logical loop that caused the inverted highlight artifact.
  let shadowed_foreground_color = mix(color.rgb, foreground_shadow_color.rgb, 0.95);
  let lit_foreground_color = color.rgb * FOREGROUND_LIT_MULTIPLIER;
  
  // The rest of the logic now works as intended.
  let sunlit_color = mix(shadowed_foreground_color, lit_foreground_color, total_sunray_intensity);
 var final_rgb = mix(color.rgb, sunlit_color, foreground_shadow_intensity);
  // Optional: Mix the highlight color instead of adding it for a softer effect.
  final_rgb = mix(final_rgb, sunray_color, clamp(sunray_specular, 0.0, 1.0));

  // --- Roaming Spotlights (Unchanged) ---
  let light_core_radius = 0.02;
  let light_falloff_intensity = 0.15;
  let depth_fade_margin = 0.05;
  
  // Spotlight 1 (Blue)
  let light1_pos = vec2<f32>(sin(time * 0.5) * 0.5 + 0.5, cos(time * 0.3) * 0.5 + 0.5);
  let light1_falloff_radius = 0.35;
  let light1_depth = (cos(time * 0.45) * 0.5 + 0.5);
  let light1_depth_occlusion = smoothstep(aa_visual_depth + depth_fade_margin, aa_visual_depth - depth_fade_margin, light1_depth);
  let dist_to_light1 = distance(uv, light1_pos);
  let core1 = 1.0 - smoothstep(light_core_radius * 0.5, light_core_radius, dist_to_light1);
  let falloff1 = (1.0 - smoothstep(light_core_radius, light1_falloff_radius, dist_to_light1)) * light_falloff_intensity;
  let base_spotlight1 = (core1 + falloff1) * light1_depth_occlusion;
  let spotlight1_brightness = base_spotlight1 + (specular_sheen * base_spotlight1);
  let light1_color = vec3<f32>(0.2, 0.5, 1.0);

  // Spotlight 2 (Warm)
  let light2_pos = vec2<f32>(cos(time * -0.4) * 0.5 + 0.5, sin(time * 0.6) * 0.5 + 0.5);
  let light2_falloff_radius = 0.3;
  let light2_depth = (sin(time * -0.38) * 0.5 + 0.5);
  let light2_depth_occlusion = smoothstep(aa_visual_depth + depth_fade_margin, aa_visual_depth - depth_fade_margin, light2_depth);
  let dist_to_light2 = distance(uv, light2_pos);
  let core2 = 1.0 - smoothstep(light_core_radius * 0.5, light_core_radius, dist_to_light2);
  let falloff2 = (1.0 - smoothstep(light_core_radius, light2_falloff_radius, dist_to_light2)) * light_falloff_intensity;
  let base_spotlight2 = (core2 + falloff2) * light2_depth_occlusion;
  let spotlight2_brightness = base_spotlight2 + (specular_sheen * base_spotlight2);
  let light2_color = vec3<f32>(1.0, 0.7, 0.2);
  
  final_rgb += (light1_color * spotlight1_brightness) + (light2_color * spotlight2_brightness);

// --- MODIFICATION START: Post-Processing Contrast Boost ---

let contrast_strength = 0.3;
let s_curve_color = final_rgb * final_rgb * (3.0 - 2.0 * final_rgb);
let post_processed_rgb = mix(final_rgb, s_curve_color, contrast_strength);
// --- MODIFICATION END ---

// --- Tone Mapping and Final Output (FIXED) ---
let exposure = 1.0;
// Use the new post-processed color here!
let exposed_rgb = post_processed_rgb * exposure;
let tonemapped_rgb = aces_tonemap(exposed_rgb);

  color = vec4<f32>(tonemapped_rgb, color.a);
  textureStore(writeTexture, global_id.xy, color);
}
