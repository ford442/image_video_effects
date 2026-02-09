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
  return fract(sin(dot(p, vec2<f32>(19.27, 91.61))) * 43758.5453);
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
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  var center = u.zoom_config.yz;
  if (center.x < 0.0) {
    center = vec2<f32>(0.5, 0.5);
  }

  let intensity = u.zoom_params.x * 2.2;
  let decay = 0.88 + u.zoom_params.y * 0.11;
  let density = mix(0.6, 1.4, u.zoom_params.z);
  let threshold = u.zoom_params.w;

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let dir = (center - uv) * vec2<f32>(aspect, 1.0);
  let steps = 48;
  let delta = dir / f32(steps) * density;

  var accum = vec3<f32>(0.0);
  var weight = 1.0;
  var current = uv;

  for (var i = 0; i < steps; i++) {
    let sample = textureSampleLevel(readTexture, u_sampler, current, 0.0).rgb;
    let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
    if (luma > threshold) {
      accum += sample * weight * intensity;
    }

    let dust = noise(current * resolution * 0.02 + vec2<f32>(time * 0.5, -time * 0.3));
    accum += vec3<f32>(dust * 0.02) * weight * intensity;

    weight *= decay;
    current += delta;
  }

  accum *= 1.0 / f32(steps) * 0.9;
  accum *= vec3<f32>(1.1, 1.05, 0.95);

  let dist = length((uv - center) * vec2<f32>(aspect, 1.0));
  let halo = smoothstep(0.5, 0.0, dist) * intensity * 0.35;

  let finalColor = original.rgb + accum + vec3<f32>(halo * 1.1, halo, halo * 0.8);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
