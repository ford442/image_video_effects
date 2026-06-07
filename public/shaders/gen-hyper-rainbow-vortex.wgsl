// ═══════════════════════════════════════════════════════════════════
//  Hyper Rainbow Vortex
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  By: Kimi Agent
// ═══════════════════════════════════════════════════════════════════
//  Wolfram Rankine Vortex Enrichment:
//  Solid-body rotation inside core: v(r) = Ωr  (r < a)
//  Irrotational flow outside:      v(r) = Ωa²/r (r > a)
//  Core radius a = 0.2 + bass*0.1, angular velocity Ω = 2.0 + mids*3.0
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530;

// Canonical ACES Filmic Tone Mapping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Neon-saturated rainbow palette
fn neonRainbow(t: f32) -> vec3<f32> {
  let p = abs(fract(t + vec3<f32>(0.0, 0.333, 0.667)) * 6.0 - vec3<f32>(3.0));
  return pow(clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.7)) * 2.5;
}

// Smooth HSV to RGB with extra saturation boost
fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let rgb = clamp(abs((c.x * 6.0 + vec3<f32>(0.0, 4.0, 2.0)) % 6.0 - 3.0) - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
  return c.z * mix(vec3<f32>(1.0), rgb, c.y);
}

// Spiral arm intensity (uses supplied angle directly)
fn spiralArm(uv: vec2<f32>, angle: f32, tightness: f32, offset: f32) -> f32 {
  let r = length(uv);
  let spiral = sin(angle * tightness + r * 12.0 + offset);
  let envelope = exp(-r * 3.0) * (0.5 + 0.5 * sin(r * 8.0 - offset));
  return pow(abs(spiral), 0.3) * envelope;
}

// Vortex twist distortion
fn vortexDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
  let r = length(uv);
  let a = atan2(uv.y, uv.x);
  let twist = strength / (r + 0.1);
  let newA = a + twist;
  return vec2<f32>(r * cos(newA), r * sin(newA));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let aspect = res.x / res.y;

  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  // ── Audio reads ──
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let fragCoord = vec2<f32>(pixel);
  let uv = fragCoord / res;
  let centered = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

  let time = u.config.x;
  let mouseNorm = u.zoom_config.yz / res;
  let mouseCentered = (mouseNorm - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scale = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // Vortex center influenced by mouse
  let vortexCenter = mouseCentered * 0.6;
  let pullStrength = 2.0 + intensity * 4.0 + length(mouseCentered) * 2.0;

  // Local coordinates relative to vortex center
  let local = centered - vortexCenter;
  let r = length(local);
  let a = atan2(local.y, local.x);

  // ── Rankine Vortex (Wolfram enrichment) ──
  let coreR = 0.2 + bass * 0.1;
  let omega = 2.0 + mids * 3.0;
  let swirl = select(omega * r, omega * coreR * coreR / max(r, 0.001), r > coreR);
  let vorticityMag = abs(swirl);

  // Secondary vortex from mouse position
  let mouseOffset = mouseCentered * 0.5;
  let mouseVortexR = length(local - mouseOffset);
  let mouseOmega = 1.5 * length(mouseCentered);
  let mouseCoreR = 0.15;
  let mouseSwirl = select(
    mouseOmega * mouseVortexR,
    mouseOmega * mouseCoreR * mouseCoreR / max(mouseVortexR, 0.001),
    mouseVortexR > mouseCoreR
  );
  let totalSwirl = swirl + mouseSwirl * 0.5;
  let swirlAngle = a + totalSwirl * time * 0.15;

  // Layer 1: Primary counter-clockwise spiral
  let t1 = time * speed * 1.0;
  let spiral1 = spiralArm(local, swirlAngle, 3.0 + scale * 4.0, t1);
  let color1 = neonRainbow(r * 3.0 - t1 * 0.3 + colorShift + vorticityMag * 0.05);

  // Layer 2: Secondary clockwise spiral (counter-rotating)
  let t2 = time * speed * -1.5;
  let local2 = vortexDistort(local, -pullStrength * 0.3);
  let spiral2 = spiralArm(local2, swirlAngle + PI, 5.0 + scale * 3.0, t2);
  let color2 = neonRainbow(r * 4.0 + t2 * 0.2 + colorShift + 0.5);

  // Layer 3: Tertiary fast spiral
  let t3 = time * speed * 2.5;
  let spiral3 = spiralArm(local * 1.5, swirlAngle, 7.0 + scale * 5.0, t3);
  let sat3 = clamp(vorticityMag * 0.25, 0.6, 1.0);
  let color3 = hsv2rgb(vec3<f32>(fract(swirlAngle / TAU + t3 * 0.1 + colorShift), sat3, 1.0));

  // Layer 4: Fine interference pattern (treble-reactive)
  let t4 = time * speed * 0.7;
  let fine = sin(a * 12.0 + r * 20.0 + t4) * cos(a * 8.0 - r * 15.0 - t4 * 1.3) * (1.0 + treble);
  let fineColor = neonRainbow(r * 5.0 + fine * 0.3 + colorShift + 0.25);

  // Combine layers with different weights
  var color = color1 * spiral1 * 1.2;
  color += color2 * spiral2 * 0.9;
  color += color3 * spiral3 * 0.7;
  color += fineColor * pow(abs(fine), 0.5) * 0.5;

  // Central glow / singularity (hue from swirlAngle, sat from vorticity)
  let coreGlow = exp(-r * r * 25.0) * (2.0 + intensity * 3.0);
  let coreSat = clamp(vorticityMag * 0.3, 0.7, 1.0);
  let coreColor = hsv2rgb(vec3<f32>(fract(swirlAngle / TAU + time * speed * 0.1 + colorShift), coreSat, 1.0));
  color += coreColor * coreGlow;

  // Radial color bands
  let bands = sin(r * 30.0 * (0.5 + scale) - time * speed * 3.0) * 0.5 + 0.5;
  let bandColor = neonRainbow(r * 6.0 + time * speed * 0.5 + colorShift);
  color += bandColor * bands * exp(-r * 2.0) * 0.4;

  // Pull distortion effect based on mouse
  let pullDist = sin(r * 15.0 - time * speed * 4.0) * exp(-r * 1.5);
  let pullColor = neonRainbow(pullDist + colorShift + 0.75);
  color += pullColor * abs(pullDist) * intensity * 0.6;

  // Hot center pulse
  let pulse = sin(time * speed * 5.0) * 0.5 + 0.5;
  let hotCenter = exp(-r * r * 10.0) * pulse * intensity;
  color += vec3<f32>(1.0, 0.9, 0.7) * hotCenter * 1.5;

  // Additive interference at spiral crossings
  let interference = spiral1 * spiral2 * spiral3 * 2.0;
  color += vec3<f32>(1.0, 1.0, 1.0) * interference * 0.3;

  // Brightness boost
  color *= 1.0 + intensity * 1.5;
  color = max(color, vec3<f32>(0.0));

  // ── Temporal feedback ──
  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(prev.rgb * 0.96, color, 0.25);
  textureStore(dataTextureA, pixel, vec4<f32>(color, 1.0));

  // ── Chromatic aberration ──
  let caStr = 0.003 * (1.0 + bass);
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // ── ACES tone mapping + semantic alpha ──
  color = acesToneMap(color * 1.1);
  let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
}
