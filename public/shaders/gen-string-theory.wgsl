// ═══════════════════════════════════════════════════════════════════
//  String Theory - Vibrating string visualizations with harmonics
//  Category: generative
//  Features: procedural, wave equation, interference patterns,
//    chromatic-aberration, audio-reactive, temporal-feedback, depth-aware
//  Created: 2026-03-22
//  Updated: 2026-06-01
//  By: Agent 4A
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Evaluate all strings at a given position, returning color + total intensity in alpha
fn evalStrings(p: vec2<f32>, t: f32, fundamental: f32, harmonicRichness: i32, damping: f32, excitement: f32, bass: f32, aspect: f32, depth: f32) -> vec4<f32> {
  var col = vec3<f32>(0.0);
  var totalIntensity = 0.0;
  for (var s: i32 = 0; s < 5; s++) {
    let angle = f32(s) * 0.314 + t * 0.02;
    let cA = cos(angle);
    let sA = sin(angle);
    let sc = vec2<f32>(aspect * 0.5, 0.5 + f32(s - 2) * 0.15);
    let local = p - sc;
    let sX = local.x * cA + local.y * sA;
    let sY = -local.x * sA + local.y * cA;
    let inStr = step(abs(sX), 1.5);
    let x = (sX + 1.5) / 3.0;
    var y = 0.0;
    var sCol = vec3<f32>(0.0);
    for (var h: i32 = 1; h <= harmonicRichness; h++) {
      let n = f32(h);
      let amp = 0.1 * (1.0 + bass * excitement) / n;
      let damp = pow(damping, n);
      let k = fundamental * n * 6.28318;
      let w = fundamental * n * 3.14159;
      y += 2.0 * amp * damp * sin(k * x) * cos(w * t);
      let hue = fract(n * 0.15 + t * 0.05);
      let c = 0.48;
      let hx = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
      let m = 0.36;
      let hi = clamp(i32(hue * 6.0), 0, 5);
      let rgb_table = array<vec3<f32>, 6>(
        vec3<f32>(c, hx, 0.0), vec3<f32>(hx, c, 0.0), vec3<f32>(0.0, c, hx),
        vec3<f32>(0.0, hx, c), vec3<f32>(hx, 0.0, c), vec3<f32>(c, 0.0, hx)
      );
      sCol += (rgb_table[hi] + vec3<f32>(m)) / n;
    }
    let travelAmp = 0.05 * excitement * (1.0 + bass * 2.0);
    y += travelAmp * sin(x * fundamental * 12.56636 - t * fundamental * 12.56636);
    let dist = abs(sY - y);
    let thick = (0.003 + 0.002 * excitement) * (0.6 + 0.4 * depth);
    let intensity = smoothstep(thick * 3.0, 0.0, dist);
    let core = smoothstep(thick, 0.0, dist);
    let glowFalloff = 50.0 * (0.4 + 0.6 * depth);
    let glow = exp(-dist * glowFalloff) * 0.3;
    col += (sCol * (intensity + glow) + vec3<f32>(1.0) * core * 0.5) * inStr;
    totalIntensity += intensity * inStr;
    col += sCol * (sin(dist * 200.0 + t * 2.0) * 0.5 + 0.5) * intensity * 0.2 * inStr;
  }
  return vec4<f32>(col, totalIntensity);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  let uv = vec2<f32>(pixel) / resolution;
  let t = u.config.x;
  let fundamental = mix(0.5, 3.0, u.zoom_params.x);
  let harmonicRichness = i32(mix(1.0, 10.0, u.zoom_params.y));
  let damping = mix(0.8, 0.99, u.zoom_params.z);
  let excitement = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let aspect = resolution.x / resolution.y;

  // Chromatic aberration offset scaled by aspect
  let caStrength = 0.003 * (1.0 + bass) / aspect;
  let rResult = evalStrings(vec2<f32>((uv.x + caStrength) * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, depth);
  let gResult = evalStrings(vec2<f32>(uv.x * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, depth);
  let bResult = evalStrings(vec2<f32>((uv.x - caStrength) * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, depth);
  var col = vec3<f32>(rResult.r, gResult.g, bResult.b);

  // Background acoustic resonance field
  let p = vec2<f32>(uv.x * aspect, uv.y);
  let resField = sin(p.x * 15.0 + t * 1.5) * sin(p.y * 12.0 - t) * 0.02 * (1.0 + bass);
  col += vec3<f32>(0.2, 0.15, 0.3) * abs(resField) * depth;

  // Sympathetic resonance: all strings respond to bass
  let resonance = sin(p.x * 8.0 + t * 6.0) * bass * 0.05 * exp(-abs(p.y - 0.5) * 2.0);
  col += vec3<f32>(0.7, 0.6, 0.9) * abs(resonance) * depth;

  // Interference between strings
  let interference = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
  col += vec3<f32>(0.5, 0.3, 0.7) * interference * 0.05 * (1.0 + bass * excitement);

  // Energy glow
  let energyGlow = exp(-gResult.w * 2.0) * (1.0 + bass * excitement);
  col += vec3<f32>(0.8, 0.6, 0.3) * energyGlow * 0.3;

  // Spectral bass bloom
  let bassBloom = exp(-length(uv - 0.5) * 3.0) * bass * 0.15;
  col += vec3<f32>(0.9, 0.5, 0.2) * bassBloom;

  // Harmonic overtones traveling wave (audio-excited)
  let overtoneWave = 0.03 * bass * sin(p.x * 40.0 - t * 8.0) * exp(-abs(p.y - 0.5));
  col += vec3<f32>(0.6, 0.8, 1.0) * abs(overtoneWave) * depth;

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.6;
  col *= vignette;

  // String cross-talk: nearby strings influence each other
  let crossTalk = sin(p.x * 12.0 + t * 3.0) * cos(p.y * 8.0 - t * 2.0) * 0.02 * bass;
  col += vec3<f32>(0.4, 0.5, 0.7) * abs(crossTalk) * depth;

  // Higher-mode resonance visualization
  let modeResonance = sin(p.x * 30.0 - t * 5.0) * exp(-abs(p.y - 0.5) * 3.0) * 0.03 * bass;
  col += vec3<f32>(0.5, 0.8, 0.9) * abs(modeResonance) * depth;

  // Harmonic decay trail visualization
  let decayTrail = exp(-gResult.w * 4.0) * 0.15 * (1.0 + bass * 0.5);
  col += vec3<f32>(0.9, 0.7, 0.4) * decayTrail * depth;

  // Phase-locked amplitude modulation
  let phaseMod = sin(t * 0.7) * 0.5 + 0.5;
  col *= 0.9 + phaseMod * 0.1;

  // Bass-driven chromatic pulse
  let chromaPulse = 1.0 + bass * sin(t * 10.0) * 0.05;
  col *= chromaPulse;

  // Temporal feedback with decay
  let persistence = 0.92 - bass * 0.05;
  let temporal = prev * persistence;
  col = max(col, temporal * 0.4);

  // Depth falloff and tone mapping
  col *= 0.5 + 0.5 * depth;
  col = acesToneMap(col * 1.2);

  let alpha = clamp(gResult.w * length(gResult.rgb) * depth, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(gResult.w, 0.0, 0.0, 0.0));
}
