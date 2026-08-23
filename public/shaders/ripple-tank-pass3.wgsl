// Ripple Tank — Codex (e) graph node 4: chromatic water render.
// Reads exact bounded C state, commits unchanged state to A, and uses no B/extraBuffer.

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

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims).r;
  let right = stateAt(pixel + vec2<i32>(1, 0), dims).r;
  let top = stateAt(pixel + vec2<i32>(0, -1), dims).r;
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims).r;
  let gradient = vec2<f32>(right - left, bottom - top);
  let curvature = left + right + top + bottom - 4.0 * state.r;
  let normal = normalize(vec3<f32>(-gradient * 6.5, 0.14));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let refraction = normal.xy * (0.022 + audio.x * 0.012) *
    (0.65 + depth * 0.35);
  let r = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction * 1.18, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let g = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let b = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction * 0.78, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sourceRGB = vec3<f32>(r.r, g.g, b.b);
  let sourceAlpha = max(r.a, max(g.a, b.a));

  let amplitudeRaw = sqrt(state.r * state.r + state.g * state.g);
  let amplitude = amplitudeRaw / (0.12 + amplitudeRaw);
  let phase = atan2(state.g, state.r) * 0.15915494 + 0.5;
  let interference = spectral(phase + time * 0.055 + audio.y * 0.12);
  let lightDirection = normalize(vec3<f32>(0.42, 0.55, 0.82));
  let diffuse = max(dot(normal, lightDirection), 0.0);
  let specular = pow(max(dot(reflect(-lightDirection, normal),
    vec3<f32>(0.0, 0.0, 1.0)), 0.0), 44.0);
  let caustic = pow(clamp(abs(curvature) * 16.0 + state.b * 0.45,
    0.0, 1.8), 1.6) * (1.0 + audio.z * 0.75);

  var rgb = sourceRGB * (0.54 + diffuse * 0.52);
  rgb += interference * amplitude * (0.65 + audio.y * 0.28);
  rgb += vec3<f32>(1.0, 0.96, 0.86) * specular * 0.38;
  rgb += vec3<f32>(0.36, 0.82, 1.0) * caustic * 0.24;
  let alpha = clamp(sourceAlpha * 0.52 + amplitude * 0.34 +
    state.b * 0.12 + caustic * 0.035, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(depth - state.r * 0.05 - state.b * 0.008, 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, state);
}
