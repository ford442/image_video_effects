// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, psychedelic, procedural
//  Complexity: Medium
//  Created: 2026-05-23
// ═══════════════════════════════════════════════════════════════════
//  Simulates a diffraction grating: multiple virtual slits produce
//  sinusoidal interference fringes whose spatial frequency, tilt
//  and phase are modulated by audio. Separate red/green/blue path
//  lengths create vivid spectral splitting. Rotational symmetry
//  applied 6-fold produces a kaleidoscopic star burst.

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

const TAU: f32 = 6.283185307179586;
const SLITS: i32 = 6;
const SYMMETRY: i32 = 6;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Apply k-fold rotational symmetry to a 2D point
fn applySymmetry(q: vec2<f32>, k: i32) -> vec2<f32> {
  let sectors = f32(k);
  let angle   = atan2(q.y, q.x);
  let r       = length(q);
  let secAngle = TAU / sectors;
  let sector   = floor(angle / secAngle);
  let localA   = angle - sector * secAngle;
  // Mirror alternate sectors
  let foldA = select(localA, secAngle - localA, localA > secAngle * 0.5);
  return vec2<f32>(cos(foldA), sin(foldA)) * r;
}

// Diffraction from a single slit at position slitPos on axis axisDir
fn slitIntensity(p: vec2<f32>, slitPos: f32, axisDir: vec2<f32>, freq: f32, phase: f32, lambda: f32) -> f32 {
  let proj   = dot(p, axisDir) - slitPos;
  let wave   = 0.5 + 0.5 * cos(proj * freq * TAU + phase);
  // Envelope: sinc-like falloff from slit center
  let dist   = abs(dot(p, vec2<f32>(-axisDir.y, axisDir.x)));
  let envArg = dist * freq * 0.5 * lambda;
  let sinc   = select(1.0, sin(envArg) / envArg, abs(envArg) > 0.001);
  return wave * sinc * sinc;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let speed    = mix(0.2,  2.5, u.zoom_params.x);
  let freq     = mix(4.0, 22.0, u.zoom_params.y);
  let chromAb  = mix(0.8,  2.2, u.zoom_params.z); // wavelength spread
  let brightness = mix(0.6, 2.0, u.zoom_params.w);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = applySymmetry(p, SYMMETRY);

  // Wavelengths for R G B (relative)
  let lambdaR = 1.0 * chromAb;
  let lambdaG = 0.82 * chromAb;
  let lambdaB = 0.68 * chromAb;

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  for (var si: i32 = 0; si < SLITS; si = si + 1) {
    let sf      = f32(si);
    let slitAngle = sf / f32(SLITS) * TAU + time * speed * 0.05;
    let axis    = vec2<f32>(cos(slitAngle), sin(slitAngle));
    let slitPos = (sf - f32(SLITS) * 0.5) * 0.18;
    let phase   = time * speed * (0.6 + sf * 0.23) + bass * TAU * 0.4;

    r = r + slitIntensity(p, slitPos, axis, freq * lambdaR, phase, lambdaR);
    g = g + slitIntensity(p, slitPos, axis, freq * lambdaG, phase + 0.3, lambdaG);
    b = b + slitIntensity(p, slitPos, axis, freq * lambdaB, phase + 0.6, lambdaB);
  }

  // Normalize and boost
  let norm    = 1.0 / max(f32(SLITS) * 0.6, 1.0);
  var color   = vec3<f32>(r, g, b) * norm * brightness * (1.0 + mids * 0.4);

  // Add a global hue shimmer
  let shimHue = fract(time * speed * 0.04 + treble * 0.2);
  let shimRgb = hsv2rgb(vec3<f32>(shimHue, 0.4, 1.0));
  color = color + shimRgb * 0.08;

  // Vignette
  let vign  = 1.0 - smoothstep(0.6, 1.2, length(p * 0.5));
  color = color * vign;
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(3.0));

  let depth = clamp((r + g + b) * norm * 0.4, 0.0, 1.0);
  let alpha = clamp(length(color) * 0.6, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(color, alpha));
}
