// ═══════════════════════════════════════════════════════════════════
//  Psychedelic Noise Flow
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
  let p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                 dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
             mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                 dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let speed_param = u.zoom_params.x * (1.0 + bass * 0.3);
  let scale_param = u.zoom_params.y;
  let distort_param = u.zoom_params.z;
  let color_shift = u.zoom_params.w;

  let noise_scale = scale_param * 8.0 + 1.0;
  let strength = distort_param * 0.1 * (1.0 + mids * 0.5);

  let mouse = u.zoom_config.yz;
  let mouse_dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouse_dir = normalize(uv - mouse + vec2<f32>(0.001));
  let mouse_influence = smoothstep(0.4, 0.0, mouse_dist);

  let t = time * (speed_param * 2.0 + 0.1);
  let n_r = noise(uv * noise_scale + vec2<f32>(t, t * 0.5) - mouse_influence * mouse_dir);
  let n_g = noise(uv * noise_scale + vec2<f32>(t + 10.0, t * 0.6 + 10.0) + mouse_influence * mouse_dir * 0.5);
  let n_b = noise(uv * noise_scale + vec2<f32>(t + 20.0, t * 0.7 + 20.0));

  let d_r = vec2<f32>(n_r, noise(uv * noise_scale + vec2<f32>(n_r, t))) * strength;
  let d_g = vec2<f32>(n_g, noise(uv * noise_scale + vec2<f32>(n_g, t + 5.0))) * strength;
  let d_b = vec2<f32>(n_b, noise(uv * noise_scale + vec2<f32>(n_b, t + 10.0))) * strength;

  let final_d_r = d_r;
  let final_d_g = mix(d_r, d_g, color_shift);
  let final_d_b = mix(d_r, d_b, color_shift);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + final_d_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + final_d_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + final_d_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let alpha = clamp(baseColor.a * 0.5 + (length(d_r) + length(d_g) + length(d_b)) * 5.0 + mouse_influence * 0.2, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(r, g, b, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(r, g, b, alpha));
}
