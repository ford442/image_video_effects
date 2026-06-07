// ═══════════════════════════════════════════════════════════════════
//  Hypnotic Vortex Tunnel
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
//  An infinite tunnel of nested vortex rings coloured by
//  spectral light — bass drives rotation, treble adds strobe arcs.
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
  zoom_params: vec4<f32>,  // x=Rings, y=RotSpeed, z=Zoom, w=Distort
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Map (r, theta) tunnel coordinates to colour
fn tunnelLayer(
  r: f32, theta: f32, z: f32,
  t: f32, bass: f32, mids: f32, treble: f32,
  rotSpeed: f32, distort: f32
) -> vec3<f32> {
  // Spinning angle offset driven by bass
  let spin = theta + t * rotSpeed * (1.0 + bass * 0.5) + z * 0.3;

  // Hex/ring pattern
  let ringMask = sin(r * 30.0 - t * (2.0 + bass * 1.5)) * 0.5 + 0.5;
  let spokeMask = sin(spin * 8.0 + z * 0.5) * 0.5 + 0.5;
  let combined = ringMask * spokeMask;

  // Colour from depth and angle
  let hue = fract(z * 0.15 + theta * 0.16 + t * 0.05 + mids * 0.1);
  let col = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * hue),
    0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
    0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
  );

  // Treble arc: bright radial flare on high energy
  let arcAngle = fract(spin / 6.2832);
  let arc = smoothstep(0.04, 0.0, abs(arcAngle - 0.5)) * treble * 0.5;

  // Distortion wave on mids
  let warp = distort * 0.15 * sin(r * 10.0 + t * 3.0 + mids * 2.0);
  return col * (combined + arc) * (1.0 + warp);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let nRings   = mix(4.0, 16.0, u.zoom_params.x);
  let rotSpeed = mix(0.2, 2.0, u.zoom_params.y);
  let zoom     = mix(0.5, 2.5, u.zoom_params.z) * (1.0 + bass * 0.2);
  let distort  = u.zoom_params.w;

  // Mouse steers vanishing-point offset
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let vp = mouse * 0.4 * u.zoom_config.w;  // vanishing point
  let pv = p - vp;

  let r = length(pv);
  let theta = atan2(pv.y, pv.x);

  // Tunnel z-coordinate: logarithmic depth
  let zBase = -log(max(r / zoom, 0.001)) + t * 0.5 * (1.0 + bass * 0.2);

  var col = vec3<f32>(0.0);
  let layers = i32(nRings);
  for (var i = 0; i < layers; i++) {
    let z = zBase + f32(i) * (6.28318 / nRings);
    col += tunnelLayer(r, theta, z, t, bass, mids, treble, rotSpeed, distort);
  }
  col /= f32(layers);

  // Dark centre iris
  let iris = 1.0 - smoothstep(0.0, 0.06, r);
  col = mix(col, vec3<f32>(0.0), iris);

  // Edge vignette
  col *= 1.0 - smoothstep(0.8 * zoom, 1.4 * zoom, r);

  col = aces(col * 1.2);

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma + (1.0 - iris) * 0.05, 0.0, 1.0);
  let depth = clamp(1.0 - r / zoom, 0.0, 1.0);

  let finalColor = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
