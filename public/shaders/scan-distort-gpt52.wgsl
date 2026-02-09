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
  return fract(sin(dot(p, vec2<f32>(41.7, 289.3))) * 43758.5453);
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

  // Params
  let lineParam = u.zoom_params.x;
  let bendParam = u.zoom_params.y;
  let glitchParam = u.zoom_params.z;
  let rollParam = u.zoom_params.w;

  let lines = mix(200.0, 1400.0, lineParam);
  let bend = mix(0.0, 0.18, bendParam);
  let glitch = glitchParam * 0.08;
  let roll = time * mix(0.2, 2.5, rollParam);

  var warped = uv;
  let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  warped += centered * (radius * radius) * bend;

  let linePhase = (warped.y + roll) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  let scanBoost = 0.85 + 0.15 * scan;

  let lineId = floor(warped.y * lines * 0.05);
  let jitter = (hash(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, glitchParam * 0.6);

  let offset = vec2<f32>(jitter + blockJitter, 0.0);

  let aberr = glitchParam * 0.01 + 0.002;
  let r = textureSampleLevel(readTexture, u_sampler, warped + offset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + offset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + offset - vec2<f32>(aberr, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b) * scanBoost;
  color += vec3<f32>(0.02, 0.01, 0.03) * (hash(uv * resolution + time) - 0.5) * glitchParam;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
