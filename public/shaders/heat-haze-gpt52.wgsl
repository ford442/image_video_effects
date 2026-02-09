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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash(i + vec2<f32>(0.0, 0.0));
  let b = hash(i + vec2<f32>(1.0, 0.0));
  let c = hash(i + vec2<f32>(0.0, 1.0));
  let d = hash(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x * 0.2;
  let texel = 1.0 / resolution;

  // Params
  let intensity = u.zoom_params.x; // 0..1
  let rise = u.zoom_params.y;      // 0..1
  let frequency = u.zoom_params.z; // 0..1
  let chroma = u.zoom_params.w;    // 0..1

  let freq = mix(2.0, 8.0, frequency);
  let flow = vec2<f32>(0.0, -time * mix(0.2, 1.0, rise));

  let n1 = noise(uv * freq * 2.0 + vec2<f32>(time * 0.3, -time * 0.2) + flow);
  let n2 = noise(uv * freq * 4.0 + vec2<f32>(-time * 0.15, time * 0.25) + flow * 1.3);
  let n3 = noise(uv * freq * 6.0 + vec2<f32>(time * 0.5, time * 0.1) + flow * 0.7);

  let haze = (vec2<f32>(n1 - 0.5, n2 - 0.5) + vec2<f32>(n2 - 0.5, n3 - 0.5)) * 0.03 * intensity;

  let shimmer = smoothstep(0.6, 1.0, n3) * intensity * 0.15;
  let grad_x = noise(uv + vec2<f32>(texel.x, 0.0) * 3.0) - noise(uv - vec2<f32>(texel.x, 0.0) * 3.0);
  let grad_y = noise(uv + vec2<f32>(0.0, texel.y) * 3.0) - noise(uv - vec2<f32>(0.0, texel.y) * 3.0);
  let grad = vec2<f32>(grad_x, grad_y) * 0.02 * intensity;

  let warp = haze + grad + vec2<f32>(0.0, sin((uv.x + time) * 6.28318) * 0.002 * intensity);

  let dispersion = warp * (0.6 + chroma) * 0.5;
  let r = textureSampleLevel(readTexture, u_sampler, uv + warp + dispersion, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + warp, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + warp - dispersion, 0.0).b;

  var color = vec3<f32>(r, g, b);
  color += vec3<f32>(0.05, 0.02, 0.01) * shimmer;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
