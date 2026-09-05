// Wave Equation — Codex (g) single-pass damped ripple field.
// A/C packing: height, velocity, foam energy, oscillator phase.
// B and extraBuffer are intentionally unused; C reads are exact and bounded.

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
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let waveSpeed = mix(0.055, 0.31, u.zoom_params.x) * (1.0 + audio.y * 0.08);
  let damping = mix(0.955, 0.9985, u.zoom_params.y);
  let sourceStrength = mix(0.08, 1.25, u.zoom_params.z) * (1.0 + audio.x * 0.7);
  let reflectivity = u.zoom_params.w;

  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
  let right = stateAt(pixel + vec2<i32>(1, 0), dims);
  let top = stateAt(pixel + vec2<i32>(0, -1), dims);
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims);
  let diagonal = stateAt(pixel + vec2<i32>(-1, -1), dims).r +
    stateAt(pixel + vec2<i32>(1, -1), dims).r +
    stateAt(pixel + vec2<i32>(-1, 1), dims).r +
    stateAt(pixel + vec2<i32>(1, 1), dims).r;
  let laplacian = (left.r + right.r + top.r + bottom.r) * 0.8 +
    diagonal * 0.2 - state.r * 4.0;

  var velocity = (state.g + laplacian * waveSpeed) * damping;
  var height = state.r + velocity;
  var foam = max(state.b * 0.962, abs(laplacian) * (0.18 + audio.z * 0.14));
  var phase = state.a;

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDistance = length(mouseDelta);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let driver = exp(-mouseDistance * mouseDistance * 180.0) * held;
  phase = fract(phase + driver * (0.035 + audio.z * 0.025));
  let driveWave = sin(phase * 6.283185) * driver * sourceStrength;
  height += driveWave * 0.13;
  velocity += driveWave * 0.035;
  foam += abs(driveWave) * 0.04;

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = length(q);
      let front = sin((d - age * 0.34) * 72.0) *
        exp(-abs(d - age * 0.34) * 28.0 - age * 0.8);
      height += front * sourceStrength * 0.08;
      velocity += front * sourceStrength * 0.018;
      foam += abs(front) * 0.045;
      clickFront += abs(front);
    }
  }

  let edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let wall = mix(smoothstep(0.0, 0.055, edgeDistance), 1.0, reflectivity);
  height = clamp(height * wall, -1.4, 1.4);
  velocity = clamp(velocity * wall, -0.75, 0.75);
  foam = clamp(foam * mix(0.7, 1.0, wall), 0.0, 1.2);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, phase));

  let gradient = vec2<f32>(right.r - left.r, bottom.r - top.r);
  let normal = normalize(vec3<f32>(-gradient * 6.0, 0.16));
  let offset = normal.xy * (0.018 + audio.x * 0.011);
  let sourceR = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + offset * 1.15, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sourceG = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sourceB = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + offset * 0.82, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let source = vec4<f32>(sourceR.r, sourceG.g, sourceB.b,
    max(sourceR.a, max(sourceG.a, sourceB.a)));
  let amplitudeRaw = sqrt(height * height + velocity * velocity);
  let amplitude = amplitudeRaw / (0.1 + amplitudeRaw);
  let hue = atan2(velocity, height) * 0.15915494 + time * 0.045 + audio.y * 0.12;
  let tint = spectral(hue);
  let specular = pow(max(dot(normal,
    normalize(vec3<f32>(0.45, 0.52, 1.0))), 0.0), 42.0);
  var rgb = source.rgb * (0.65 + normal.z * 0.35);
  rgb += tint * (amplitude * 0.72 + foam * 0.28 + clickFront * 0.05);
  rgb += vec3<f32>(1.0, 0.96, 0.86) * specular * 0.3;
  let alpha = clamp(source.a * 0.58 + amplitude * 0.28 + foam * 0.14, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(depth - height * 0.045 - foam * 0.008, 0.0, 1.0), 0.0, 0.0, 0.0));
}
