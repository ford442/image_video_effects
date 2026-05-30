// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam
//  Category: generative
//  Features: audio-reactive, upgraded-rgba, procedural
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Simulates the seething quantum vacuum: bubbles of spacetime
//  pop in and out of existence, driven by audio energy.
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
  zoom_params: vec4<f32>,  // x=Density, y=BubbleSize, z=Chroma, w=Speed
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash31(p3: vec3<f32>) -> f32 {
  var q = fract(p3 * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec3<f32>(p.x, p.y, p.x);
  var q2 = fract(q * vec3<f32>(0.1031, 0.1030, 0.0973));
  q2 += dot(q2, q2.yzx + 33.33);
  return fract((q2.xx + q2.yz) * q2.zy);
}

// Worley (cellular) noise — returns distance to nearest point
fn worley(p: vec2<f32>) -> vec2<f32> {
  let ip = floor(p);
  let fp = fract(p);
  var d1 = 8.0;
  var d2 = 8.0;
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      let cell = ip + vec2<f32>(f32(dx), f32(dy));
      let jitter = hash22(cell);
      let offset = vec2<f32>(f32(dx), f32(dy)) + jitter - fp;
      let d = dot(offset, offset);
      if (d < d1) { d2 = d1; d1 = d; }
      else if (d < d2) { d2 = d; }
    }
  }
  return vec2<f32>(sqrt(d1), sqrt(d2));
}

// FBM Worley layering
fn foamField(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var amp = 0.5;
  var pp = p;
  for (var i = 0u; i < 4u; i++) {
    let w = worley(pp + vec2<f32>(t * 0.07, t * 0.05) * amp);
    v += amp * (w.y - w.x);  // border distance
    pp *= 2.1;
    amp *= 0.5;
  }
  return v;
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

  let density    = mix(1.5, 8.0,  u.zoom_params.x) * (1.0 + bass * 0.3);
  let bubbleSize = mix(0.4, 1.8,  u.zoom_params.y);
  let chroma     = mix(0.1, 1.0,  u.zoom_params.z);
  let speed      = mix(0.05, 0.4, u.zoom_params.w);

  let aspect = u.config.z / max(u.config.w, 1.0);
  let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0) * density;

  // Compute foam field at different scales / offsets for chromatic layers
  let foam0 = foamField(p * bubbleSize, t * speed);
  let foam1 = foamField(p * bubbleSize + vec2<f32>(3.7, 1.3), t * speed + 0.5);
  let foam2 = foamField(p * bubbleSize + vec2<f32>(-1.7, 4.1), t * speed + 1.0);

  // Map to color: each foam channel drives a spectral band
  let r = smoothstep(0.0, 0.5, foam0) * (0.6 + chroma * 0.4 + treble * 0.15);
  let g = smoothstep(0.0, 0.5, foam1) * (0.5 + chroma * 0.3 + mids   * 0.15);
  let b = smoothstep(0.0, 0.5, foam2) * (0.7 + chroma * 0.5 + bass   * 0.20);

  var col = vec3<f32>(r, g, b);

  // Add thin bright cell borders
  let border0 = exp(-foam0 * 20.0) * 1.5;
  let border1 = exp(-foam1 * 20.0) * 1.2;
  col += vec3<f32>(border0 * 0.3, border1 * 0.2, border0 * 0.4) * (1.0 + treble * 0.5);

  // Vacuum glow: dark background punctuated by plasma colors
  let vacuumHue = fract(t * 0.03 + mids * 0.1);
  let vacuum = vec3<f32>(
    0.02 + 0.05 * cos(6.2832 * vacuumHue),
    0.02 + 0.05 * cos(6.2832 * (vacuumHue + 0.33)),
    0.05 + 0.08 * cos(6.2832 * (vacuumHue + 0.67))
  );
  col = mix(vacuum, col, smoothstep(0.05, 0.3, foam0 + foam1 + foam2));

  // Virtual event flash on bass transient
  let flash = smoothstep(0.6, 1.0, bass) * hash31(vec3<f32>(uv, t)) * 0.3;
  col += flash;

  col = aces(col);

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.9 + border0 * 0.1, 0.0, 1.0);
  let depth = clamp(foam0 * 0.5 + 0.3, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
