// PP Chromatic — Cauchy-dispersed lens with temporal fringe persistence.
// A/C stores tone-mapped display RGBA. B and extraBuffer are unused.
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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

fn lensWarp(uv: vec2<f32>, center: vec2<f32>, curvature: f32, aspectVec: vec2<f32>) -> vec2<f32> {
  let p = (uv - center) * aspectVec;
  let r2 = dot(p, p);
  return center + p * (1.0 + curvature * r2 + curvature * curvature * r2 * r2 * 0.18) / aspectVec;
}

fn sampleBand(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
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

  let chroma = mix(0.0005, 0.032, u.zoom_params.x) * (1.0 + mids * 0.42);
  let curvature = (u.zoom_params.y - 0.5) * 1.7 * (1.0 + bass * 0.18);
  let vignetteStrength = u.zoom_params.z;
  let mode = u.zoom_params.w;
  let center = mix(vec2<f32>(0.5), mouse, 0.18 + select(0.12, 0.6, held));
  let warped = lensWarp(uv, center, curvature, aspectVec);
  let radial = normalize((warped - center) * aspectVec + vec2<f32>(0.0001, 0.0)) / aspectVec;
  let axial = normalize(vec2<f32>(cos(time * 0.23 + mouse.x * 3.0), sin(time * 0.19 + mouse.y * 3.0))) / aspectVec;
  let tangent = vec2<f32>(-radial.y, radial.x);
  let direction = normalize(mix(mix(radial, axial, smoothstep(0.0, 0.5, mode)), tangent, smoothstep(0.5, 1.0, mode)) * aspectVec) / aspectVec;

  var clickLens = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.34 + bass * 0.08);
      clickLens += sin((rd - front) * 64.0) * exp(-abs(rd - front) * 32.0) * exp(-age * 1.25);
    }
  }

  let pointerDist = length((uv - mouse) * aspectVec);
  let pointerLens = exp(-pointerDist * 8.0) * select(0.18, 1.0, held);
  let causticShift = direction * (clickLens * 0.004 + pointerLens * 0.0025);
  // Cauchy n(lambda) = A + B/lambda^2, evaluated at five visible wavelengths.
  let lambda0 = 0.650;
  let lambda1 = 0.580;
  let lambda2 = 0.530;
  let lambda3 = 0.480;
  let lambda4 = 0.440;
  let cauchyB = chroma * (0.034 + mode * 0.026);
  let n0 = 1.46 + cauchyB / (lambda0 * lambda0);
  let n1 = 1.46 + cauchyB / (lambda1 * lambda1);
  let n2 = 1.46 + cauchyB / (lambda2 * lambda2);
  let n3 = 1.46 + cauchyB / (lambda3 * lambda3);
  let n4 = 1.46 + cauchyB / (lambda4 * lambda4);
  let baseN = 1.46;
  let s0 = sampleBand(warped + direction * (n0 - baseN) + causticShift);
  let s1 = sampleBand(warped + direction * (n1 - baseN) + causticShift * 0.7);
  let s2 = sampleBand(warped + direction * (n2 - baseN));
  let s3 = sampleBand(warped + direction * (n3 - baseN) - causticShift * 0.55);
  let s4 = sampleBand(warped + direction * (n4 - baseN) - causticShift);
  var hdr = vec3<f32>(s0.r * 0.72 + s1.r * 0.28,
                      s1.g * 0.22 + s2.g * 0.58 + s3.g * 0.20,
                      s3.b * 0.32 + s4.b * 0.68);

  let history = historyAt(uv - direction * clickLens * 0.003, resolution);
  let radialDist = length((uv - center) * aspectVec);
  let vignette = 1.0 - smoothstep(mix(1.15, 0.48, vignetteStrength), mix(1.42, 0.9, vignetteStrength), radialDist);
  let spectralCaustic = pow(max(0.0, 0.5 + 0.5 * cos(radialDist * 88.0 - time * (2.0 + treble * 5.0) + clickLens * 5.0)), 12.0);
  hdr *= max(vignette, 0.0);
  hdr += vec3<f32>(0.42, 0.72, 1.35) * spectralCaustic * treble * chroma * 9.0;
  hdr = mix(hdr, history.rgb, clamp(0.025 + abs(clickLens) * 0.045 + chroma * 0.7, 0.0, 0.1));
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let sourceAlpha = textureSampleLevel(readTexture, u_sampler, clamp(warped, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;
  let lensCoverage = clamp(spectralCaustic * chroma * 7.0 + abs(clickLens) * 0.12, 0.0, 1.0);
  let alpha = clamp(sourceAlpha + (1.0 - sourceAlpha) * lensCoverage, 0.0, 1.0);
  let result = vec4<f32>(display, alpha);

  textureStore(dataTextureA, coord, result);
  textureStore(writeTexture, coord, result);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
