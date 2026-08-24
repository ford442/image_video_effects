// Hyperbolic Tessellation Engine — recursive Poincare-disk geometry
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
  zoom_params: vec4<f32>, // symmetry, depth color, rotation speed, boundary glow
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn rotate2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a); let s = sin(a);
  return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}

fn mobius(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
  let num = z - a;
  let den = vec2<f32>(1.0 - dot(a, z), a.y * z.x - a.x * z.y);
  let d2 = max(dot(den, den), 0.0001);
  return vec2<f32>(num.x * den.x + num.y * den.y,
                   num.y * den.x - num.x * den.y) / d2;
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.48) + vec3<f32>(0.52) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.03, 0.31, 0.62)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let sampleP = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 1.9;
  var disk = sampleP;
  let originalRadius = length(disk);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let symmetryCtl = clamp(u.zoom_params.x, 0.0, 1.0);
  let depthColor = clamp(u.zoom_params.y, 0.0, 1.0);
  let rotationSpeed = clamp(u.zoom_params.z, 0.0, 1.0);
  let boundaryGlowCtl = clamp(u.zoom_params.w, 0.0, 1.0);
  let symmetry = 4.0 + floor(symmetryCtl * 8.0 + 0.5);
  let sectorAngle = TAU / symmetry;

  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 1.2;
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let translation = mix(vec2<f32>(sin(time * 0.19), cos(time * 0.17)) * (0.12 + bass * 0.025), mouse * 0.52, held);
  disk = mobius(disk, clamp(translation, vec2<f32>(-0.62), vec2<f32>(0.62)));
  disk = rotate2(disk, time * mix(-0.12, 0.42, rotationSpeed) * (1.0 + mids * 0.16));

  var z = disk;
  var recursiveDepth = 0.0;
  var edge = 0.0;
  for (var i = 0; i < 8; i++) {
    let angle = atan2(z.y, z.x);
    let foldedAngle = abs((fract(angle / sectorAngle + 0.5) - 0.5) * sectorAngle);
    z = vec2<f32>(length(z) * cos(foldedAngle), length(z) * sin(foldedAngle));
    let lineDist = abs(z.y);
    let lineWidth = mix(0.027, 0.009, f32(i) / 7.0) * (1.0 + treble * 0.28);
    edge = max(edge, 1.0 - smoothstep(lineWidth, lineWidth * 2.7, lineDist));
    let scale = 1.36 + symmetryCtl * 0.28;
    z = z * scale - vec2<f32>(0.44 + bass * 0.025, 0.0);
    recursiveDepth += 1.0;
    if (length(z) > 1.55) { break; }
  }

  let diskMask = 1.0 - smoothstep(0.965, 1.015, originalRadius);
  let boundary = exp(-abs(originalRadius - 0.98) * mix(34.0, 105.0, boundaryGlowCtl));
  let tilePulse = 0.5 + 0.5 * cos(length(z) * (16.0 + symmetry) - time * (0.7 + rotationSpeed * 2.0));
  let depthPhase = recursiveDepth / 8.0;
  var raw = palette(depthPhase * (0.35 + depthColor * 2.4) + time * 0.025 + mids * 0.08);
  raw *= (0.18 + tilePulse * 0.82) * diskMask * (0.85 + bass * 0.35);
  raw += palette(depthPhase + 0.33 + treble * 0.05) * edge * (0.85 + treble * 1.1) * diskMask;
  raw += vec3<f32>(0.4, 0.72, 1.35) * boundary * boundaryGlowCtl * (1.0 + treble * 0.7);

  var clickGlow = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 1.9;
      clickGlow += exp(-abs(distance(sampleP, center) - age * 0.24) * 68.0) * exp(-age * 1.35);
    }
  }
  raw += palette(clickGlow + depthPhase) * clickGlow * 0.65;

  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.94, raw, 0.26 + rotationSpeed * 0.07), vec3<f32>(0.0), vec3<f32>(7.0));
  let coverage = clamp(diskMask * (0.12 + edge * 0.58 + tilePulse * 0.2) + boundary * 0.25 + clickGlow * 0.15, 0.03, 0.98);
  let depth = clamp(diskMask * (0.15 + depthPhase * 0.62 + edge * 0.2), 0.0, 1.0);
  let display = acesToneMap(raw * 1.12);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, coverage));
  textureStore(writeTexture, pixel, vec4<f32>(display, coverage));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
