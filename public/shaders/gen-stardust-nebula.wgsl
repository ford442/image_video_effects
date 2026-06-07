// ═══════════════════════════════════════════════════════════════════
//  Stardust Nebula
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
//  Clouds of stellar nursery gas lit from within: emission nebula
//  colours, dark absorption pillars, and nascent star sparkle.
//  Bass swells the pillars, treble ignites proto-star flares.
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
  zoom_params: vec4<f32>,  // x=Density, y=Emission, z=StarField, w=Drift
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec3<f32>(p.x, p.y, p.x);
  var q2 = fract(q * vec3<f32>(0.1031, 0.1030, 0.0973));
  q2 += dot(q2, q2.yzx + 33.33);
  return fract((q2.xx + q2.yz) * q2.zy);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

// Curl noise for gas drift
fn curlNoise(p: vec2<f32>, t: f32, speed: f32) -> vec2<f32> {
  let eps = 0.01;
  let n0 = noise2(p + vec2<f32>(t * speed * 0.04, 0.0));
  let nx = noise2(p + vec2<f32>(eps, 0.0) + vec2<f32>(t * speed * 0.04, 0.0));
  let ny = noise2(p + vec2<f32>(0.0, eps) + vec2<f32>(t * speed * 0.04, 0.0));
  return vec2<f32>(ny - n0, n0 - nx) / eps * 0.02;
}

fn fbm5(p: vec2<f32>, t: f32, speed: f32) -> f32 {
  var v = 0.0; var amp = 0.5; var pp = p;
  pp += curlNoise(pp, t, speed) * 5.0;
  for (var i = 0u; i < 6u; i++) {
    v += amp * noise2(pp);
    pp = pp * 2.0 + curlNoise(pp, t + f32(i), speed) * 2.0;
    amp *= 0.48;
  }
  return v;
}

// Proto-star field: discrete bright points
fn starField(uv: vec2<f32>, density: f32, treble: f32) -> f32 {
  let cell = floor(uv * density);
  let local = fract(uv * density);
  let h = hash22(cell);
  let starPos = h * 0.8 + 0.1;
  let d = length(local - starPos);
  let size = 0.04 * (1.0 + treble * 0.6) * (0.5 + h.x * 0.5);
  return exp(-d * d / (size * size)) * (0.4 + h.y * 0.6);
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

  let density   = mix(1.0, 5.0, u.zoom_params.x) * (1.0 + bass * 0.3);
  let emission  = mix(0.3, 2.0, u.zoom_params.y);
  let starDens  = mix(4.0, 16.0, u.zoom_params.z);
  let drift     = mix(0.1, 1.0, u.zoom_params.w);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.3 * u.zoom_config.w;

  // Nebula gas density
  let gas = fbm5(p * density * 0.5, t, drift);

  // Pillar of creation: dense vertical absorption column driven by bass
  let pillarX = 0.15 * (1.0 + bass * 0.5);
  let pillar = smoothstep(pillarX, 0.0, abs(p.x + mids * 0.1)) * fbm5(p * 2.0, t * 0.3, 0.3);

  // Emission nebula colours (HII region palette: magenta H-alpha, cyan OIII, blue SII)
  let halpha = smoothstep(0.3, 0.8, gas) * (1.0 - pillar * 0.7);
  let oiii   = smoothstep(0.2, 0.7, fbm5(p * density * 0.6 + vec2<f32>(3.1, 1.7), t * 0.8, drift));
  let sii    = smoothstep(0.25, 0.75, fbm5(p * density * 0.4 + vec2<f32>(-2.3, 0.8), t * 0.6, drift));

  var col = vec3<f32>(
    halpha * 0.9 + sii * 0.4,     // red-magenta (H-alpha + SII)
    oiii * 0.6 + halpha * 0.1,    // green-cyan (OIII)
    oiii * 0.9 + sii * 0.1        // blue (OIII / SII blend)
  ) * emission * (1.0 + mids * 0.2);

  // Absorption pillars darken the gas
  col *= 1.0 - pillar * 0.85;

  // Proto-star sparkle on treble
  let stars = starField(uv, starDens, treble);
  col += vec3<f32>(1.0, 0.95, 0.85) * stars * (1.0 + treble * 0.5);

  // Deep space background
  let bgStars = starField(uv * 3.7 + vec2<f32>(13.3, 7.1), 20.0, 0.0) * 0.15;
  let spaceCol = vec3<f32>(0.01, 0.01, 0.04);
  col = mix(spaceCol + bgStars, col, smoothstep(0.0, 0.25, gas + oiii * 0.3));

  col = aces(col);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.85 + stars * 0.1, 0.0, 1.0);
  let depth = clamp(gas * 0.7 + 0.1, 0.0, 1.0);

  let finalColor = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
