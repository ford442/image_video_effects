// ═══════════════════════════════════════════════════════════════════
//  Neon Lotus
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-30
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
  zoom_params: vec4<f32>,  // x=Param1(petalCount), y=Param2(bloom), z=Param3(speed), w=Param4(glow)
  ripples: array<vec4<f32>, 50>,
};

// ACES filmic tonemap
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// Lotus petal SDF: teardrop shape in polar coords
fn petalSdf(r: f32, theta: f32, phase: f32, bloom: f32) -> f32 {
  // petal: r ~ cos(theta/2) * bloom
  let petalR = bloom * 0.5 * max(0.0, cos(theta * 0.5 + phase));
  return r - petalR;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  // Audio
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let nPetals   = mix(4.0, 16.0, u.zoom_params.x);
  let bloomAmt  = mix(0.3, 1.0, u.zoom_params.y) * (1.0 + bass * 0.35);
  let speed     = mix(0.1, 0.8, u.zoom_params.z);
  let glowScale = mix(0.5, 2.5, u.zoom_params.w) * (1.0 + mids * 0.25);

  // Mouse: shift center
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.4 * u.zoom_config.w;

  let r = length(p);
  let theta = atan2(p.y, p.x);

  // Layered lotus: multiple rings of petals
  var col = vec3<f32>(0.0);
  var totalGlow = 0.0;

  let nLayers = 3u;
  for (var layer = 0u; layer < nLayers; layer++) {
    let lf = f32(layer);
    let layerScale = 1.0 - lf * 0.3;
    let layerR = r / layerScale;
    let layerT = theta + lf * 0.4 + t * speed * (1.0 - lf * 0.2);
    let nP = nPetals + lf * 4.0;
    let petalAngle = 6.28318 / nP;
    // Find nearest petal
    let sector = floor(layerT / petalAngle + 0.5);
    let localTheta = layerT - sector * petalAngle;
    let phase = sector * 0.1;
    let bloom = bloomAmt * layerScale * (0.8 + 0.2 * sin(t * 0.5 + lf));
    let sdf = petalSdf(layerR, localTheta, phase, bloom);
    let petalMask = smoothstep(0.02, -0.02, sdf);
    // Neon hue per layer
    let hue = fract(lf * 0.33 + t * 0.05 + bass * 0.15 + sector * 0.07);
    let petalColor = vec3<f32>(
      0.5 + 0.5 * cos(6.2832 * hue),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
    );
    // Edge glow (neon effect)
    let edgeGlow = exp(-abs(sdf) * 30.0) * glowScale * (1.0 + treble * 0.4);
    col += petalColor * (petalMask * 0.7 + edgeGlow * 0.8);
    totalGlow += edgeGlow;
  }

  // Stamens at center
  let centerDist = smoothstep(0.08, 0.0, r) * (1.0 + bass * 0.5);
  let centerHue = fract(t * 0.1 + mids * 0.2);
  let centerColor = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * centerHue),
    0.5 + 0.5 * cos(6.2832 * (centerHue + 0.33)),
    0.5 + 0.5 * cos(6.2832 * (centerHue + 0.67))
  );
  col += centerColor * centerDist * 1.5;

  // Fine noise shimmer on treble
  let shimmer = noise2d(p * 40.0 + vec2<f32>(t * 0.5)) * treble * 0.08;
  col += shimmer;

  // Vignette
  col *= 1.0 - smoothstep(0.8, 1.5, r);

  // Tonemap
  col = aces(col);

  // Alpha: luminance-driven, rich from center
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.85 + centerDist * 0.15, 0.0, 1.0);

  // Depth
  let depth = clamp(1.0 - r * 0.6, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
