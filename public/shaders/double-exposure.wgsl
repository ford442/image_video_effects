// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Warp
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Pixelocity Shader Upgrade Swarm — Phase A
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI = 3.14159265358979323846;
const TAU = 6.28318530717958647692;
const PHI = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * PHI)) * 2.0 - 1.0;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i).x;
  let b = hash21(i + vec2<f32>(1.0, 0.0)).x;
  let c = hash21(i + vec2<f32>(0.0, 1.0)).x;
  let d = hash21(i + vec2<f32>(1.0, 1.0)).x;
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 5; i = i + 1) {
    s = s + a * valueNoise(q);
    q = q * 2.02; a = a * 0.5;
  }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
  let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
  return fbm(p + 4.0*r);
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
  var F1 = 1e9; var F2 = 1e9;
  let ip = floor(p);
  for (var i = -1; i <= 1; i = i + 1) {
    for (var j = -1; j <= 1; j = j + 1) {
      let n = ip + vec2<f32>(f32(i), f32(j));
      let h = fract(sin(dot(n, vec2<f32>(127.1, 311.7))) * 43758.5453);
      let off = vec2<f32>(h, fract(h * PHI));
      let d = length(p - n - off);
      if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }
  }
  return F2 - F1;
}

fn rotate2d(uv: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle); let s = sin(angle);
  return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coords = vec2<i32>(global_id.xy);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));

  let zoom = 0.5 + u.zoom_params.x * 2.5;
  let angle = (u.zoom_params.y - 0.5) * PI * 0.5;
  let opacity = u.zoom_params.z;
  let warpStrength = u.zoom_params.w;
  let t = u.config.x * 0.2;

  let bass = plasmaBuffer[0].x;
  let audioZoom = zoom * (1.0 + bass * 0.15);

  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / max(resolution.y, 1.0);

  let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var p = uv - mouse;
  p.x *= aspect;
  p = rotate2d(p, angle);
  p = p / max(audioZoom, 0.001);

  let warpScale = 2.0 + warpStrength * 4.0;
  let w = warpedFBM(p * warpScale, t) * 0.025 * (0.3 + warpStrength);
  p = p + vec2<f32>(cos(t * 0.7 + w * TAU), sin(t * 0.5 + w * TAU)) * w;

  p.x /= aspect;
  let uv2 = clamp(p + mouse, vec2<f32>(0.0), vec2<f32>(1.0));
  let c2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

  let voro = voronoiF2minusF1(uv * 3.0 + t * 0.15) * 2.0;
  let mask = smoothstep(0.0, 0.5, voro + opacity * 0.5);

  var blended = 1.0 - (1.0 - c1.rgb) * (1.0 - c2.rgb * opacity * (0.7 + mask * 0.3));

  let gray = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
  blended = mix(vec3<f32>(gray), blended, 0.6 + opacity * 0.4);

  let luminance = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
  let depthFactor = 0.7 + depth * 0.3;
  let alpha = clamp(luminance * (0.5 + opacity * 0.5) * depthFactor + 0.15, 0.25, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(blended, alpha));
}
