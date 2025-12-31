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

// Helper for hue to rgb
fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
  var t_ = t;
  if(t_ < 0.0) { t_ += 1.0; }
  if(t_ > 1.0) { t_ -= 1.0; }
  if(t_ < 1.0/6.0) { return p + (q - p) * 6.0 * t_; }
  if(t_ < 1.0/2.0) { return q; }
  if(t_ < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t_) * 6.0; }
  return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  var r: f32;
  var g: f32;
  var b: f32;

  if(s == 0.0) {
    r = l;
    g = l;
    b = l;
  } else {
    var q: f32;
    if(l < 0.5) { q = l * (1.0 + s); } else { q = l + s - l * s; }
    let p = 2.0 * l - q;
    r = hue2rgb(p, q, h + 1.0/3.0);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1.0/3.0);
  }
  return vec3<f32>(r, g, b);
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
  let ink_hue = u.zoom_params.x;
  let spread_speed = u.zoom_params.y;
  let fade_speed = u.zoom_params.z;
  let density = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouse_down = u.zoom_config.w; // 1.0 if down

  // 1. Read previous ink state from dataTextureC
  // ink state is stored in R channel (intensity). G could be hue, but let's stick to single hue for now.
  let prev_ink = textureSampleLevel(dataTextureC, filteringSampler, uv, 0.0).r;

  // 2. Add new ink if mouse is down
  // Adjust aspect ratio for circular brush
  let aspect = u.config.z / u.config.w;
  let d = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0, 0.0));
  let brush_size = 0.05;

  var new_ink_add = 0.0;
  if (mouse_down > 0.5 && d < brush_size) {
    new_ink_add = smoothstep(brush_size, 0.0, d);
  }

  // 3. Diffuse ink (spread)
  // Simple 4-neighbor average
  let pixel_size = 1.0 / vec2<f32>(dims);
  let n = textureSampleLevel(dataTextureC, filteringSampler, uv + vec2<f32>(0.0, pixel_size.y), 0.0).r;
  let s = textureSampleLevel(dataTextureC, filteringSampler, uv - vec2<f32>(0.0, pixel_size.y), 0.0).r;
  let e = textureSampleLevel(dataTextureC, filteringSampler, uv + vec2<f32>(pixel_size.x, 0.0), 0.0).r;
  let w = textureSampleLevel(dataTextureC, filteringSampler, uv - vec2<f32>(pixel_size.x, 0.0), 0.0).r;

  let average = (n + s + e + w) * 0.25;

  // Mix current with average based on spread speed
  // If spread is high, we move closer to average quickly
  var current_ink = mix(prev_ink, average, spread_speed * 0.1); // Small step per frame

  current_ink = min(current_ink + new_ink_add, 1.0);

  // 4. Fade
  current_ink *= (1.0 - fade_speed * 0.01);
  if (current_ink < 0.001) { current_ink = 0.0; }

  // 5. Store state
  textureStore(dataTextureA, coord, vec4<f32>(current_ink, 0.0, 0.0, 1.0));

  // 6. Render
  let video_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let ink_color_rgb = hslToRgb(ink_hue, 0.8, 0.3); // Dark, saturated ink

  // Composite: Darken video where ink is
  let final_color = mix(video_color, video_color * ink_color_rgb, current_ink * density);

  textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
