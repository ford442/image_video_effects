@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,      // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,  // zoomTime, farthestX, farthestY, unused
  zoom_params: vec4<f32>,  // fg_speed, bg_speed, parallax_str, fog_density
  ripples: array<vec4<f32>, 50>, // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

fn sample_zooming_layer(
  uv: vec2<f32>,
  depth: f32,
  zoom_time: f32,
  zoom_center: vec2<f32>,
  cycle_offset: f32
) -> vec4<f32> {
  let fg_speed = u.zoom_params.x;
  let bg_speed = u.zoom_params.y;
  let parallax_strength = u.zoom_params.z;

  // Depth 0.0 = Near, 1.0 = Far
  // parallax_factor: 1.0 (Near) -> 0.0 (Far)
  let parallax_factor = pow(1.0 - depth, parallax_strength);

  // Calculate speed. If bg_speed is 0 and depth is 1.0, speed is 0.
  let per_pixel_speed = mix(bg_speed, fg_speed, parallax_factor);
  
  // High intensity allows objects to get very large ("move past")
  let zoom_intensity = 4.0;

  // cycle_offset shifts the phase for multi-layering
  // fract ensure it loops 0..1
  let zoom_progress = fract(zoom_time * per_pixel_speed + cycle_offset);

  // SCALE:
  // We want Outward movement (Zoom In).
  // Scale should go from 1.0 (distance) -> Large (near).
  // We multiply by parallax_factor so that if factor is 0 (Far), scale stays 1.0.
  let scale = 1.0 + zoom_progress * zoom_intensity * parallax_factor;

  // Transform UVs
  let repeating_uv = (uv - zoom_center) / scale + zoom_center;

  // Use seamless wrapping
  let wrapped_uv = ping_pong_v2(repeating_uv);

  let color = textureSampleLevel(readTexture, non_filtering_sampler, wrapped_uv, 0.0);

  // ALPHA / FADING:
  // We want to fade out as we get very close (zoom_progress -> 1.0).
  // We want to fade in as we appear from distance (zoom_progress -> 0.0).
  let fade_duration = 0.3;
  let fade_in = smoothstep(0.0, fade_duration, zoom_progress);
  let fade_out = 1.0 - smoothstep(1.0 - fade_duration, 1.0, zoom_progress);

  // Combined alpha
  var alpha = fade_in * fade_out;

  // CRITICAL: If this is the background (parallax_factor ~ 0), we want it fully opaque.
  // We don't want the background to pulse.
  // We interpolate alpha towards 1.0 based on how "far" the pixel is.
  // If parallax_factor is 0 (Far), alpha becomes 1.0.
  // If parallax_factor is 1 (Near), alpha is governed by the fade loop.
  alpha = mix(alpha, 1.0, 1.0 - smoothstep(0.0, 0.1, parallax_factor));

  return vec4(color.rgb, alpha);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let zoom_time = u.zoom_config.x;
  let zoom_center = u.zoom_config.yz;

  let static_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // --- Compositing ---
  // Layer 1 and Layer 2 provide the continuous stream of objects.
  let layer1 = sample_zooming_layer(uv, static_depth, zoom_time, zoom_center, 0.0);
  let layer2 = sample_zooming_layer(uv, static_depth, zoom_time, zoom_center, 0.5);

  // Blend layers.
  // Since we forced background alpha to 1.0, both layers might be opaque in background.
  // But they should be identical in background (scale 1.0, same UVs).
  // So standard mixing is fine.
  var final_color = mix(layer1, layer2, layer2.a);

  // --- Fog ---
  // Fog should apply to distant objects (high depth value).
  let fog_density = u.zoom_params.w;
  let fog_color = vec3<f32>(0.05, 0.1, 0.08); 
  let fog_amount = pow(static_depth, 2.0) * fog_density; 
  
  final_color = vec4<f32>(mix(final_color.rgb, fog_color, fog_amount), final_color.a);

  textureStore(writeTexture, global_id.xy, vec4(final_color.rgb, 1.0));


  // --- Depth Texture Update ---
  // We must transform the depth texture exactly like the color texture so they move together.
  // However, blending 2 depth layers is tricky.
  // Usually, we want the "closest" depth (min value? or max value? 0=Near).
  // If blending colors, we see the top layer.
  // We should probably just sample layer2 if layer2.a > 0.5?

  // Re-calculate parameters for the update logic
  let fg_speed = u.zoom_params.x;
  let bg_speed = u.zoom_params.y;
  let parallax_strength = u.zoom_params.z;
  let parallax_factor = pow(1.0 - static_depth, parallax_strength);
  let per_pixel_speed = mix(bg_speed, fg_speed, parallax_factor);
  let zoom_intensity = 4.0;

  // We follow the MAIN layer (whichever is dominant).
  // Let's assume a simple single-pass transform for the depth map to avoid artifacts,
  // OR we try to replicate the mix.
  // If we just transform the depth map using the "primary" zoom cycle, it might drift.
  // Ideally, the depth map IS the static map, and we are just reading from it to distort the image.
  // Wait. The code writes to `writeDepthTexture`.
  // If `liquid-zoom` is just a render effect, we shouldn't modify the depth texture permanently?
  // BUT the renderer architecture swaps read/write depth textures?
  // `this.swapDepthTextures()` is called in `Renderer.ts`.
  // If we modify the depth texture, the next frame uses the distorted depth.
  // This creates a feedback loop!

  // User wants "move independently... illusion of moving through".
  // If we distort the depth map, the depth "moves" with the objects.
  // If we DON'T distort the depth map, the objects move but their depth reading stays static on screen?
  // That would be wrong. As an object moves effectively "closer" (scales up), its depth value should essentially travel with it?
  // Actually, if we are just displacing UVs, we should displace the Depth sample too.

  // Let's replicate the dominant layer logic.
  // If layer2 alpha is high, we use layer2's transform.

  let zoom_progress_1 = fract(zoom_time * per_pixel_speed + 0.0);
  let zoom_progress_2 = fract(zoom_time * per_pixel_speed + 0.5);

  // Determine dominant layer based on the fade logic used above
  let fade_dur = 0.3;
  let fade_in_2 = smoothstep(0.0, fade_dur, zoom_progress_2);
  let fade_out_2 = 1.0 - smoothstep(1.0 - fade_dur, 1.0, zoom_progress_2);
  let alpha_2 = fade_in_2 * fade_out_2;
  // Apply the background fix to alpha_2
  let final_alpha_2 = mix(alpha_2, 1.0, 1.0 - smoothstep(0.0, 0.1, parallax_factor));

  var active_progress = zoom_progress_1;
  // If layer 2 is opaque enough, use it. (Simple threshold or blend?)
  // Using a hard threshold helps avoid "ghost" depth values.
  if (final_alpha_2 > 0.5) {
     active_progress = zoom_progress_2;
  }

  let scale = 1.0 + active_progress * zoom_intensity * parallax_factor;
  let transformed_uv = (uv - zoom_center) / scale + zoom_center;
  let wrapped_uv = ping_pong_v2(transformed_uv);

  let new_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;

  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(new_depth, 0.0, 0.0, 0.0));
}
