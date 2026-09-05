// Alpha HDR Bloom Chain — temporal spectral bloom with exposure-preserving feedback.
// A/C packing remains [raw HDR rgb, overexposure]. B and extraBuffer are unused.
// Premium mixed-eight upgrade: 2026-08-27.

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

const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

fn spectralSample(uv: vec2<f32>, direction: vec2<f32>, shift: f32) -> vec3<f32> {
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + direction * shift * 1.13, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + direction * shift * 0.19, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - direction * shift * 0.91, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let radius = mix(0.006, 0.085, u.zoom_params.x) * (1.0 + bass * 0.24);
  let intensity = mix(0.15, 2.8, u.zoom_params.y) * (1.0 + mids * 0.55);
  let exposureScale = mix(0.45, 2.4, u.zoom_params.z);
  let saturation = mix(0.15, 1.9, u.zoom_params.w) * (1.0 + treble * 0.12);

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let mouseDelta = (uv - mouse) * aspectVec;
  let mouseDist = length(mouseDelta);
  let mouseDir = mouseDelta / max(mouseDist, 0.0001);
  let hoverHalo = exp(-mouseDist * (9.0 + u.zoom_params.x * 15.0));
  let heldGain = select(0.18, 1.0, held);

  var clickFront = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.28 + bass * 0.08);
      clickFront += exp(-abs(rd - front) * 42.0) * exp(-age * 1.4);
    }
  }

  var bloom = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var i = 0; i < 16; i = i + 1) {
    let fi = f32(i);
    let ring = 0.45 + 0.55 * f32(i % 4) / 3.0;
    let angle = TAU * fi / 16.0 + time * (0.025 + treble * 0.018);
    let direction = vec2<f32>(cos(angle), sin(angle)) / aspectVec;
    let shift = radius * ring * (1.0 + clickFront * 0.35);
    let sampleColor = spectralSample(uv, direction, shift);
    let bright = max(luma(sampleColor) * exposureScale - (0.62 - bass * 0.06), 0.0);
    let weight = exp(-ring * ring * 1.35) * bright;
    bloom += sampleColor * weight;
    weightSum += weight;
  }
  bloom /= max(weightSum, 0.001);

  let swirl = vec2<f32>(-mouseDir.y, mouseDir.x) / aspectVec;
  let historyUV = uv - swirl * hoverHalo * heldGain * (0.002 + mids * 0.003) - mouseDir / aspectVec * clickFront * 0.003;
  let history = historyAt(historyUV, resolution);
  let spectralTint = 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.02, 0.36, 0.70) + time * 0.035 + mouseDist * 0.28));
  var hdr = source.rgb * exposureScale;
  hdr += bloom * intensity * (0.65 + hoverHalo * heldGain * 0.85);
  hdr += spectralTint * (hoverHalo * heldGain + clickFront) * intensity * (0.18 + treble * 0.22);
  hdr = mix(hdr, history.rgb, clamp(0.035 + mids * 0.025 + clickFront * 0.035, 0.0, 0.14));

  let gray = vec3<f32>(luma(hdr));
  hdr = max(mix(gray, hdr, saturation), vec3<f32>(0.0));
  let overexposure = max(max(hdr.r, max(hdr.g, hdr.b)) - 1.0, 0.0);
  let display = aces(hdr);
  let bloomCoverage = clamp(max(overexposure * 0.22, max(hoverHalo * heldGain, clickFront) * 0.42), 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * bloomCoverage, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(hdr, overexposure));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
