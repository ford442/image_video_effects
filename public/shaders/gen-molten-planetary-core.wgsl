// ═══════════════════════════════════════════════════════════════════
//  Molten Planetary Core
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba, sphere-projection
//  Complexity: High
//  Created: 2026-05-30
//  The iron-nickel heart of a rocky world: convection cells churn
//  in slow loops, bass erupts mantle plumes, treble cracks the crust.
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
  zoom_params: vec4<f32>,  // x=Convection, y=Plume, z=CrustThick, w=Glow
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

fn hash31(p3i: vec3<f32>) -> f32 {
  var p3 = fract(p3i * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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

fn fbm3(p: vec2<f32>) -> f32 {
  var v = 0.0; var amp = 0.5; var pp = p;
  for (var i = 0u; i < 6u; i++) {
    v += amp * noise2(pp); pp *= 2.1; amp *= 0.48;
  }
  return v;
}

// Convection cell pattern: slow Benard rolls
fn convectionCell(p: vec2<f32>, t: f32, speed: f32) -> f32 {
  let q = vec2<f32>(
    p.x + fbm3(p + vec2<f32>(0.0, t * speed * 0.07)) * 0.6,
    p.y + fbm3(p + vec2<f32>(5.2, t * speed * 0.05)) * 0.6
  );
  return fbm3(q + vec2<f32>(t * speed * 0.03, 0.0));
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

  let convSpeed  = mix(0.1, 1.5, u.zoom_params.x) * (1.0 + bass * 0.4);
  let plumeAmt   = mix(0.0, 1.0, u.zoom_params.y) * (1.0 + bass * 0.6);
  let crustThick = mix(0.05, 0.3, u.zoom_params.z);
  let glowPow    = mix(0.5, 2.5, u.zoom_params.w) * (1.0 + mids * 0.2);

  // Mouse tilts the 3-D view axis
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.2 * u.zoom_config.w;

  let r = length(p);
  let theta = atan2(p.y, p.x);

  // Sphere mask
  let sphereR = 0.9;
  let onSphere = smoothstep(sphereR + 0.02, sphereR - 0.02, r);

  // Fake sphere normal from position
  let nz = sqrt(max(0.0, sphereR * sphereR - r * r)) / sphereR;
  let normal = vec3<f32>(p / sphereR, nz);

  // Spherical UV (for noise sampling)
  let sUV = vec2<f32>(atan2(normal.y, normal.x) / 6.28318, acos(normal.z) / 3.14159);

  // Convection field
  let conv = convectionCell(sUV * 3.0, t, convSpeed);

  // Temperature map (core = hot white, surface cooler)
  let temp = conv * (1.0 - r * 0.6);

  // Colour: blackbody ramp from black→red→orange→yellow→white
  let t0 = clamp(temp * 2.0, 0.0, 1.0);
  let t1 = clamp(temp * 2.0 - 1.0, 0.0, 1.0);
  var moltenCol = vec3<f32>(
    t0,                              // red builds first
    t0 * t0 * 0.7 + t1 * 0.3,       // orange-yellow
    t1 * t1 * 0.5                    // white-hot core
  ) * glowPow;

  // Mantle plumes: hot upwellings triggered by bass
  let plumeField = noise2(sUV * 6.0 + vec2<f32>(t * 0.04, 0.0));
  let plume = smoothstep(0.6, 1.0, plumeField) * plumeAmt;
  moltenCol += vec3<f32>(1.0, 0.5, 0.1) * plume * (1.0 + bass * 0.8);

  // Crust cracks on treble
  let crackNoise = noise2(sUV * 20.0 + vec2<f32>(0.0, t * 0.02));
  let crack = smoothstep(crustThick, 0.0, crackNoise) * (1.0 - smoothstep(0.0, 0.05, plume));
  let crackGlow = crack * treble * vec3<f32>(1.0, 0.3, 0.05) * 2.0;
  moltenCol = mix(moltenCol, moltenCol + crackGlow, crack * 0.5);

  // Dark crust where not cracking
  let crustMask = smoothstep(0.0, crustThick * 2.0, crackNoise) * (1.0 - plume);
  let crustCol  = vec3<f32>(0.05, 0.04, 0.03) * crustMask;
  moltenCol = mix(moltenCol, crustCol, crustMask * 0.4);

  // Apply sphere mask (outside = space black)
  var col = moltenCol * onSphere;

  // Atmospheric rim glow
  let rim = smoothstep(sphereR - 0.05, sphereR + 0.0, r) * smoothstep(sphereR + 0.12, sphereR - 0.0, r);
  col += vec3<f32>(0.9, 0.3, 0.1) * rim * (1.0 + bass * 0.4);

  col = aces(col);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(onSphere * 0.9 + rim * 0.1, 0.0, 1.0);
  let depth = clamp(nz * onSphere, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
