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
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
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

  let scanSpeed = u.zoom_params.x;
  let glitch = u.zoom_params.y;
  let hue = u.zoom_params.z;
  let focus = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let stabilize = mix(1.0, smoothstep(0.0, 0.5, dist), focus);

  let scan = sin(uv.y * 900.0 + time * (6.0 + scanSpeed * 4.0)) * 0.12;
  let slowScan = sin(uv.y * 15.0 - time * (1.0 + scanSpeed)) * 0.2;

  let lineNoise = noise(vec2<f32>(uv.y * 80.0, time * 3.0));
  let jitter = (lineNoise - 0.5) * glitch * 0.04 * stabilize;

  let wobble = sin(uv.y * 40.0 + time * 2.0) * 0.003 * stabilize;
  let offset = vec2<f32>(jitter + wobble, 0.0);

  let aberr = glitch * 0.015 + 0.003;
  let r = textureSampleLevel(readTexture, u_sampler, uv + offset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + offset - vec2<f32>(aberr, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b);

  let tint = vec3<f32>(
    0.6 + 0.4 * sin(hue * 6.28318 + 0.0),
    0.7 + 0.3 * sin(hue * 6.28318 + 2.1),
    0.6 + 0.4 * sin(hue * 6.28318 + 4.2)
  );

  color = color * tint * 1.4;
  color += scan + slowScan;

  let flicker = 0.9 + 0.1 * noise(vec2<f32>(time * 4.0, uv.y * 3.0));
  color *= flicker;

  let grid = sin(uv.x * 120.0) * sin(uv.y * 120.0) * 0.02;
  color += vec3<f32>(grid);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
