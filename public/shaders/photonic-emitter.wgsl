// Photonic Caustics — surface normal + light seed (graph node 1)
// dataTextureA: .rgb = surface normal, .a = light height factor
// zoom_params: .x ior (normal steepness), .y lightSize, .z dispersion hint, .w intensity

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

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u_val = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u_val.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u_val.x),
    u_val.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    value += amplitude * noise2D(p * freq + vec2<f32>(time * 0.2, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

fn getSurfaceNormal(uv: vec2<f32>, texelSize: vec2<f32>, time: f32, noiseAmp: f32) -> vec3<f32> {
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
  let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).r;
  let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
  let noiseScale = 8.0;
  let treble = plasmaBuffer[0].z;
  let nL = fbm(uv * noiseScale + vec2<f32>(-texelSize.x * noiseScale, 0.0), time) * noiseAmp * (1.0 + treble * 0.3);
  let nR = fbm(uv * noiseScale + vec2<f32>(texelSize.x * noiseScale, 0.0), time) * noiseAmp * (1.0 + treble * 0.3);
  let nU = fbm(uv * noiseScale + vec2<f32>(0.0, -texelSize.y * noiseScale), time) * noiseAmp * (1.0 + treble * 0.3);
  let nD = fbm(uv * noiseScale + vec2<f32>(0.0, texelSize.y * noiseScale), time) * noiseAmp * (1.0 + treble * 0.3);
  let dx = ((hR + nR) - (hL + nL)) * 2.0;
  let dy = ((hD + nD) - (hU + nU)) * 2.0;
  let nz = mix(0.35, 0.12, u.zoom_params.x);
  return normalize(vec3<f32>(-dx, -dy, nz));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;

  let dispersionHint = u.zoom_params.z;
  let noiseAmp = mix(0.06, 0.18, 0.5 + dispersionHint * 0.5);

  let mouseDown = u.zoom_config.w;
  let lightHeight = mix(0.5, 2.0, mouseDown) * mix(0.85, 1.25, u.zoom_params.y);

  let normal = getSurfaceNormal(uv, texelSize, time, noiseAmp);
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(normal, lightHeight));
}
