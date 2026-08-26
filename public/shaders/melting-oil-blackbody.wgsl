// Melting Oil Blackbody — Codex (e) thermal-gradient oil transport.
// A/C packing: velocity.xy, normalized temperature, molten coverage.
// B and extraBuffer are intentionally unused; C loads are exact and bounded.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
    max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
    vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbody(kelvin: f32) -> vec3<f32> {
  let t = clamp(kelvin / 1000.0, 0.8, 15.0);
  var rgb = vec3<f32>(1.0);
  if (t <= 6.5) {
    rgb.r = 1.0;
    rgb.g = clamp(0.39 * log(max(t, 0.001)) - 0.63, 0.0, 1.0);
    rgb.b = clamp(0.54 * log(max(t - 1.0, 0.001)) - 1.0, 0.0, 1.0);
  } else {
    rgb.r = clamp(1.29 * pow(max(t - 0.6, 0.001), -0.133), 0.0, 1.0);
    rgb.g = clamp(1.29 * pow(max(t - 0.6, 0.001), -0.076), 0.0, 1.0);
    rgb.b = 1.0;
  }
  return rgb * (0.35 + 0.65 * pow(t / 6.5, 2.0));
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn stateUV(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  return stateAt(vec2<i32>(floor(uv * vec2<f32>(dims))), dims);
}

fn sourceLuma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let texel = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let viscosity = mix(0.985, 0.84, u.zoom_params.x);
  let thermalRange = mix(0.65, 1.55, u.zoom_params.y);
  let radiation = mix(0.55, 2.8, u.zoom_params.z);
  let emberBloom = mix(0.02, 0.75, u.zoom_params.w);

  let gx = sourceLuma(uv + vec2<f32>(texel.x, 0.0)) -
    sourceLuma(uv - vec2<f32>(texel.x, 0.0));
  let gy = sourceLuma(uv + vec2<f32>(0.0, texel.y)) -
    sourceLuma(uv - vec2<f32>(0.0, texel.y));
  let gradient = vec2<f32>(gx, gy);
  let gradLength = max(length(gradient), 0.0001);
  let downhill = vec2<f32>(gradient.x, abs(gradient.y) + 0.08) / gradLength;

  let previous = stateAt(coord, dims);
  var velocity = previous.xy * viscosity;
  velocity += vec2<f32>(-gradient.y, gradient.x) * (0.004 + audio.y * 0.005);
  velocity += downhill * (0.0015 + (1.0 - viscosity) * 0.014);
  velocity += vec2<f32>(sin(uv.y * 19.0 + time * 2.1),
    cos(uv.x * 17.0 - time * 1.7)) * audio.z * 0.0016;

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseHeat = exp(-mouseDist * mouseDist * 70.0) * held;
  velocity += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    mouseHeat * 0.018;

  var clickHeat = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let front = exp(-abs(d - age * 0.30) * 34.0 - age * 0.9);
      velocity += vec2<f32>(q.x / aspect, q.y) / d * front * 0.011;
      clickHeat += front;
    }
  }

  velocity = clamp(velocity, vec2<f32>(-0.055), vec2<f32>(0.055));
  let advectedUV = clamp(uv - velocity, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = stateUV(advectedUV, dims);
  let neighbors = (stateAt(coord + vec2<i32>(-1, 0), dims) +
    stateAt(coord + vec2<i32>(1, 0), dims) +
    stateAt(coord + vec2<i32>(0, -1), dims) +
    stateAt(coord + vec2<i32>(0, 1), dims)) * 0.25;

  let luma = sourceLuma(advectedUV);
  var temperature = mix(advected.z, neighbors.z, 0.08 + (1.0 - viscosity) * 0.18);
  temperature += (0.12 + luma * 0.42) * thermalRange * 0.035;
  temperature += mouseHeat * 0.14 + clickHeat * 0.055 + audio.x * 0.018;
  temperature *= 0.988;
  temperature = clamp(temperature, 0.03, 1.35);
  var molten = mix(advected.w, smoothstep(0.18, 0.72, temperature), 0.075);
  molten = clamp(molten + mouseHeat * 0.04 + clickHeat * 0.018, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(velocity, temperature, molten));

  let source = textureSampleLevel(readTexture, u_sampler, advectedUV, 0.0);
  let kelvin = mix(850.0, 12500.0, clamp(temperature * thermalRange, 0.0, 1.0));
  let thermal = blackbody(kelvin) * radiation;
  let ember = pow(clamp(temperature, 0.0, 1.0), 3.0) *
    (emberBloom + audio.z * 0.22);
  var rgb = mix(source.rgb * vec3<f32>(0.23, 0.16, 0.12), thermal,
    clamp(0.28 + molten * 0.68, 0.0, 0.94));
  rgb += blackbody(kelvin * 1.18) * ember + vec3<f32>(1.0, 0.08, 0.01) * clickHeat * 0.15;
  let alpha = clamp(source.a * (0.58 + molten * 0.32) +
    temperature * 0.16 + mouseHeat * 0.08, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgb), alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    advectedUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - molten * 0.018 - temperature * 0.008, 0.0, 1.0), 0.0, 0.0, 0.0));
}
