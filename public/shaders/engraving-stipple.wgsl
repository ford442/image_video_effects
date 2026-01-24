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

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
  let density = mix(1.0, 4.0, u.zoom_params.x); // Dot density scaling
  let threshold_bias = u.zoom_params.y; // Overall darkness
  let mouse_light_strength = u.zoom_params.z;

  let mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Sample Image
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var luma = getLuma(color);

  // Mouse Interaction: Flashlight / Reveal
  // Calculate distance to mouse
  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  // Create a light spot
  let light_radius = 0.3;
  let light = smoothstep(light_radius, 0.0, dist); // 1.0 at mouse, 0.0 at radius

  // Modify luma based on light.
  // Maybe the "paper" is dark and the light reveals the image,
  // OR the image is stippled and the light increases contrast/clarity.

  // Let's make the light increase local contrast and brightness,
  // simulating a spotlight on an engraving.
  luma = luma + light * mouse_light_strength * 0.3;

  // Stippling Logic
  // We compare luma against random noise.
  // To make it look like engraving, we can mix noise with a pattern.

  // Simple white noise
  let noise = hash12(uv * vec2<f32>(dims) * density);

  // Ordered dithering effect (Bayer-like) could be better, but noise is fine for "stipple".
  // Let's bias the threshold.
  // If luma > noise, pixel is white (paper). Else black (ink).

  // Adjust threshold with bias
  let threshold = luma + (threshold_bias - 0.5);

  var final_col = vec3<f32>(0.0);

  // "Ink" color (Dark Blue/Black)
  let ink = vec3<f32>(0.1, 0.1, 0.15);
  // "Paper" color (Off-white)
  let paper = vec3<f32>(0.95, 0.93, 0.88);

  if (threshold < noise) {
    final_col = ink;
  } else {
    final_col = paper;
  }

  // Add a subtle vignette from the mouse light to the color itself
  final_col = mix(final_col * 0.5, final_col, 0.5 + 0.5 * light);

  textureStore(writeTexture, coord, vec4<f32>(final_col, 1.0));
}
