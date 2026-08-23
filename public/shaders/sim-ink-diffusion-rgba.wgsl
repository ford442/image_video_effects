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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn aces(x: vec3f) -> vec3f {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + vec3f(b))) / (x * (c * x + vec3f(d)) + vec3f(e)), vec3f(0.0), vec3f(1.0));
}

fn stateAt(p: vec2i, dims: vec2i) -> vec4f {
  return textureLoad(dataTextureC, clamp(p, vec2i(0), dims - vec2i(1)), 0);
}

fn hash21(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let dimsU = textureDimensions(dataTextureC);
  if (gid.x >= dimsU.x || gid.y >= dimsU.y) { return; }
  let p = vec2i(gid.xy);
  let dims = vec2i(dimsU);
  let uv = (vec2f(gid.xy) + vec2f(0.5)) / vec2f(dimsU);
  let aspect = u.config.zw.x / max(u.config.zw.y, 1.0);
  let wetness = clamp(u.zoom_params.x, 0.0, 1.0);
  let diffusion = clamp(u.zoom_params.y, 0.0, 1.0);
  let mixing = clamp(u.zoom_params.z, 0.0, 1.0);
  let evaporation = clamp(u.zoom_params.w, 0.0, 1.0);
  let dt = clamp((1.0 / 60.0), 0.0, 0.033);
  let c = stateAt(p, dims);
  let n = stateAt(p + vec2i(0, 1), dims);
  let s = stateAt(p + vec2i(0, -1), dims);
  let e = stateAt(p + vec2i(1, 0), dims);
  let w = stateAt(p + vec2i(-1, 0), dims);
  let avg = (n + s + e + w) * 0.25;
  let water = clamp(c.a + (avg.a - c.a) * (0.035 + 0.18 * wetness), 0.0, 1.0);
  var pigment = max(c.rgb + (avg.rgb - c.rgb) * (0.012 + 0.16 * diffusion * (0.2 + water)), vec3f(0.0));
  let chromaMean = vec3f(dot(pigment, vec3f(0.333333)));
  pigment = mix(pigment, chromaMean, 0.012 * mixing * water);

  let audio = plasmaBuffer[0].xyz;
  let pointer = u.zoom_config.yz;
  let q = (uv - pointer) * vec2f(aspect, 1.0);
  let held = step(0.5, u.zoom_config.w);
  let brush = exp(-dot(q, q) * (210.0 - 100.0 * wetness));
  let rotatingInk = 0.5 + 0.5 * cos(vec3f(0.0, 2.094, 4.189) + u.config.x * 0.7);
  pigment += held * brush * (0.028 + 0.09 * max(audio, vec3f(0.08))) * rotatingInk;
  var nextWater = water + held * brush * 0.045;

  let clickCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < clickCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = u.config.x - event.z;
    if (age >= 0.0 && age < 2.4) {
      let cp = event.xy;
      let cq = (uv - cp) * vec2f(aspect, 1.0);
      let radius = 0.04 + age * (0.09 + 0.06 * wetness);
      let ring = exp(-pow((length(cq) - radius) * 55.0, 2.0)) * exp(-age * 1.3);
      let hue = 0.5 + 0.5 * cos(vec3f(0.0, 2.094, 4.189) + f32(i) * 1.7);
      pigment += ring * hue * (0.018 + 0.045 * audio.y);
      nextWater += ring * 0.025;
    }
  }

  pigment *= exp(-dt * (0.08 + 0.42 * evaporation));
  nextWater = clamp(nextWater * exp(-dt * (0.14 + 0.75 * evaporation)), 0.0, 1.0);
  let grain = hash21(vec2f(p) + floor(u.config.x * 12.0));
  pigment = clamp(pigment + (grain - 0.5) * 0.0008 * nextWater, vec3f(0.0), vec3f(2.0));
  textureStore(dataTextureA, p, vec4f(pigment, nextWater));

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let paper = mix(vec3f(0.96, 0.94, 0.89), source.rgb, 0.55);
  let absorb = exp(-pigment * vec3f(2.8, 2.45, 2.65));
  let stained = paper * absorb + pigment.bgr * 0.08 * nextWater;
  let edge = length(vec2f(e.r - w.r, n.g - s.g));
  let color = aces(stained + edge * vec3f(0.08, 0.11, 0.15) + audio * pigment * 0.12);
  let alpha = clamp(max(max(pigment.r, pigment.g), pigment.b) * 0.72 + nextWater * 0.2, 0.0, 1.0);
  textureStore(writeTexture, p, vec4f(color, alpha));
}
