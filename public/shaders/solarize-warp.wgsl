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
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;

  // Params
  let twistStrength = (u.zoom_params.x - 0.5) * 20.0;
  let solarThreshold = u.zoom_params.y;
  let radius = u.zoom_params.z;
  let solarSoftness = u.zoom_params.w; // Unused but reserved, maybe mix amount?

  // Aspect Corrected Distance
  let uv_c = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uv_c, mouse_c);

  // Warp Logic
  // Smoothstep returns 0.0 if dist > radius, 1.0 if dist < 0
  // Note: smoothstep(high, low, val) is undefined behavior in WGSL. Use 1.0 - smoothstep(low, high, val).
  let influence = 1.0 - smoothstep(0.0, radius, dist);
  let angle = influence * twistStrength;
  let s = sin(angle);
  let c = cos(angle);

  // To rotate around mouse, we need vectors relative to mouse
  // But we must correct for aspect ratio during rotation, then convert back?
  // Easier to just rotate the UV vector around the mouse center in aspect-space?
  // Let's do simple non-aspect corrected rotation for swirl, it looks fine usually,
  // or use the aspect-corrected vector for rotation.

  let dir = uv - mouse;
  // Aspect correct the direction for rotation logic
  var dir_c = vec2<f32>(dir.x * aspect, dir.y);

  // Rotate dir_c
  let rotated_dir_c = vec2<f32>(dir_c.x * c - dir_c.y * s, dir_c.x * s + dir_c.y * c);

  // Convert back to UV space (divide x by aspect)
  let rotated_dir = vec2<f32>(rotated_dir_c.x / aspect, rotated_dir_c.y);

  let sourceUV = mouse + rotated_dir;

  let color = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

  // Solarize Logic
  // Standard solarize: if value > threshold, invert?
  // Or: color = 1.0 - abs(color - 0.5) * 2.0; (This creates a V shape)
  // Let's do threshold inversion based on params.

  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var solarColor = color.rgb;

  // We want the solarization to be intense near the warp center
  // And maybe normal outside? Or controlled by param?
  // Let's make the solarization global but the threshold modulated by param?
  // Or make it only happen inside the warp?

  // Let's try: "Solarize Warp" - The warped area is solarized.
  // influence is 1.0 at center, 0.0 at radius.

  // Only solarize if influence > 0?
  // Let's blend.

  if (luma > solarThreshold) {
      solarColor = 1.0 - solarColor;
  }

  // Make solarization dependent on influence
  // If influence is high, we solarize fully.
  // If influence is low, we see normal color.

  let finalColor = mix(color.rgb, solarColor, influence * solarSoftness + (1.0 - solarSoftness) * 0.0);
  // Actually let's just use solarSoftness as a global "Mix" slider.
  // If solarSoftness is 1.0, the effect is localized by influence?
  // Let's say param W controls "Effect Intensity" which modulates the mix.

  // Let's just output the warped color, and if inside radius, apply solarization.

  var result = color.rgb;
  if (luma > solarThreshold) {
      result = 1.0 - result;
  }

  // Mix based on distance?
  // If we want "Solarize Warp", usually the whole image is solarized or just the warp?
  // Let's make it local to the warp.

  result = mix(color.rgb, result, influence);

  textureStore(writeTexture, global_id.xy, vec4<f32>(result, 1.0));

   // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
