// Hyper Tensor Fluid — Codex (e) anisotropic tensor-guided fluid field.
// A/C packing: velocity.xy, tensor anisotropy, transported dye.
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

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn stateUV(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  return stateAt(vec2<i32>(floor(uv * vec2<f32>(dims))), dims);
}

fn sourceAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn lumaAt(uv: vec2<f32>) -> f32 {
  return dot(sourceAt(uv).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(cell), hash12(cell + vec2<f32>(1.0, 0.0)), s.x),
    mix(hash12(cell + vec2<f32>(0.0, 1.0)),
      hash12(cell + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.52 + 0.48 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.34, 0.68)));
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

  let tensorStrength = mix(0.15, 2.4, u.zoom_params.x);
  let viscosity = mix(0.035, 0.32, u.zoom_params.y);
  let turbulence = mix(0.02, 0.55, u.zoom_params.z);
  let advectionSpeed = mix(0.35, 2.8, u.zoom_params.w);

  let gx = lumaAt(uv + vec2<f32>(texel.x, 0.0)) -
    lumaAt(uv - vec2<f32>(texel.x, 0.0));
  let gy = lumaAt(uv + vec2<f32>(0.0, texel.y)) -
    lumaAt(uv - vec2<f32>(0.0, texel.y));
  let gradient = vec2<f32>(gx, gy);
  let gradientLength = max(length(gradient), 0.0001);
  let tangent = vec2<f32>(-gradient.y, gradient.x) / gradientLength;
  let lambdaMajor = dot(gradient, gradient);
  let lambdaMinor = abs(gx * gy) * 0.15;
  let anisotropy = clamp((lambdaMajor - lambdaMinor) /
    max(lambdaMajor + lambdaMinor, 0.0001), 0.0, 1.0);

  let previous = stateAt(coord, dims);
  var velocity = previous.xy;
  let averageVelocity = (stateAt(coord + vec2<i32>(-1, 0), dims).xy +
    stateAt(coord + vec2<i32>(1, 0), dims).xy +
    stateAt(coord + vec2<i32>(0, -1), dims).xy +
    stateAt(coord + vec2<i32>(0, 1), dims).xy) * 0.25;
  velocity = mix(velocity, averageVelocity, viscosity);
  velocity += tangent * anisotropy * tensorStrength * 0.0035;

  let n0 = noise(uv * 7.0 + vec2<f32>(time * 0.21, -time * 0.17));
  let nx = noise(uv * 7.0 + vec2<f32>(texel.x * 3.0, 0.0) +
    vec2<f32>(time * 0.21, -time * 0.17));
  let ny = noise(uv * 7.0 + vec2<f32>(0.0, texel.y * 3.0) +
    vec2<f32>(time * 0.21, -time * 0.17));
  velocity += vec2<f32>(n0 - ny, nx - n0) * turbulence *
    (0.008 + audio.z * 0.009);

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let stir = exp(-mouseDist * mouseDist * 42.0) * held;
  velocity += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    stir * 0.024 * tensorStrength;

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let front = sin((d - age * 0.38) * 68.0) *
        exp(-abs(d - age * 0.38) * 25.0 - age * 0.9);
      velocity += vec2<f32>(q.x / aspect, q.y) / d * front * 0.014;
      clickFront += abs(front);
    }
  }

  velocity *= 0.986 + audio.x * 0.006;
  velocity = clamp(velocity, vec2<f32>(-0.07), vec2<f32>(0.07));
  let advectedUV = clamp(uv - velocity * advectionSpeed,
    vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = stateUV(advectedUV, dims);
  var dye = advected.w * 0.985 + lumaAt(uv) * 0.012 + audio.y * 0.004;
  dye += stir * 0.035 + clickFront * 0.018;
  dye = clamp(dye, 0.0, 1.4);
  textureStore(dataTextureA, coord,
    vec4<f32>(velocity, anisotropy, dye));

  let source = sourceAt(clamp(uv + velocity * advectionSpeed * 0.7,
    vec2<f32>(0.0), vec2<f32>(1.0)));
  let flowAngle = atan2(velocity.y, velocity.x) * 0.15915494 + time * 0.035;
  let tint = spectral(flowAngle + anisotropy * 0.18 + audio.y * 0.12);
  let tensorRibbon = pow(anisotropy, 1.6) *
    (0.5 + 0.5 * sin(dot(p, tangent) * 54.0 - time * (3.0 + audio.x * 3.0)));
  var rgb = mix(source.rgb, tint * (0.32 + dye),
    clamp(dye * 0.42 + tensorRibbon * 0.34, 0.0, 0.82));
  rgb += tint * (tensorRibbon * 0.24 + clickFront * 0.12 + audio.z * 0.035);
  let alpha = clamp(source.a * 0.7 + dye * 0.2 +
    tensorRibbon * 0.08 + stir * 0.08, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgb), alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    advectedUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - tensorRibbon * 0.018 - dye * 0.006, 0.0, 1.0), 0.0, 0.0, 0.0));
}
