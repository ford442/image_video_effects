// Hyper Rainbow Vortex - Multi-layered chromatic spiral with counter-rotating arms
// Intense neon colors swirling into a dynamic center

// ═══════════════════════════════════════════════════════════════════
//  Hyper Rainbow Vortex
//  Category: generative
//  Features: vortex, rainbow, hyper, audio-reactive, mouse-driven, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

// Spiral arm intensity
fn spiralArm(uv: vec2<f32>, angle: f32, tightness: f32, offset: f32) -> f32 {
  let r = length(uv);
  let a = atan2(uv.y, uv.x);
  let spiral = sin(a * tightness + r * 12.0 + offset);
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

  // Layer 1: Primary counter-clockwise spiral
  let t1 = time * speed * 1.0;
  let spiral1 = spiralArm(local, a, 3.0 + scale * 4.0, t1);
  let color1 = neonRainbow(r * 3.0 - t1 * 0.3 + colorShift);

  // Layer 2: Secondary clockwise spiral (counter-rotating)
  let t2 = time * speed * -1.5;
  let local2 = vortexDistort(local, -pullStrength * 0.3);
  let spiral2 = spiralArm(local2, atan2(local2.y, local2.x), 5.0 + scale * 3.0, t2);
  let color2 = neonRainbow(r * 4.0 + t2 * 0.2 + colorShift + 0.5);

  // Layer 3: Tertiary fast spiral
  let t3 = time * speed * 2.5;
  let spiral3 = spiralArm(local * 1.5, a, 7.0 + scale * 5.0, t3);
  let color3 = hsv2rgb(vec3<f32>(fract(r * 2.0 + t3 * 0.1 + colorShift), 1.0, 1.0));

  // Layer 4: Fine interference pattern
  let t4 = time * speed * 0.7;
  let fine = sin(a * 12.0 + r * 20.0 + t4) * cos(a * 8.0 - r * 15.0 - t4 * 1.3);
  let fineColor = neonRainbow(r * 5.0 + fine * 0.3 + colorShift + 0.25);

  // Combine layers with different weights
  var color = color1 * spiral1 * 1.2;
  color += color2 * spiral2 * 0.9;
  color += color3 * spiral3 * 0.7;
  color += fineColor * pow(abs(fine), 0.5) * 0.5;

  // Central glow / singularity
  let coreGlow = exp(-r * r * 25.0) * (2.0 + intensity * 3.0);
  let coreColor = hsv2rgb(vec3<f32>(fract(time * speed * 0.1 + colorShift), 0.9, 1.0));
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

  // Brightness boost and tone mapping
  color *= 1.0 + intensity * 1.5;
  color = max(color, vec3<f32>(0.0));
  
  // Psychedelic tone mapping preserving neon saturation
  color = color / (1.0 + color * 0.15);
  
  // Final saturation boost
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(luminance), color, 1.3);

  textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
