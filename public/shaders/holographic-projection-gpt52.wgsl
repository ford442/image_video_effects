// ═══════════════════════════════════════════════════════════════
//  Holographic Projection GPT52 - Advanced hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, Bragg diffraction, 60Hz flicker
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash(i + vec2<f32>(0.0, 0.0));
  var b = hash(i + vec2<f32>(1.0, 0.0));
  let c = hash(i + vec2<f32>(0.0, 1.0));
  let d = hash(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Bragg diffraction efficiency (volume holograms)
fn braggDiffraction(angle: f32, wavelength: f32, braggAngle: f32) -> f32 {
    let angleDiff = angle - braggAngle;
    // Efficiency peaks at Bragg angle, decreases with detuning
    let kappa = 3.14159 / wavelength; // Coupling coefficient
    let sinc_arg = kappa * angleDiff * 10.0;
    let sinc_val = sin(sinc_arg) / max(sinc_arg, 0.001);
    return sinc_val * sinc_val;
}

// Advanced interference spectrum with Bragg condition
fn braggInterference(uv: vec2<f32>, angle: f32, dist: f32, time: f32, hue: f32) -> vec3<f32> {
    // Bragg angle varies with position for volume hologram effect
    let braggAngle = sin(uv.x * 3.0 + time * 0.2) * 0.5;
    let opticalPath = 0.43 + sin(angle + dist * 2.0) * 0.06;
    
    let effR = braggDiffraction(angle, LAMBDA_R, braggAngle + hue * 0.1);
    let effG = braggDiffraction(angle, LAMBDA_G, braggAngle);
    let effB = braggDiffraction(angle, LAMBDA_B, braggAngle - hue * 0.1);
    
    let intR = thinFilmInterference(opticalPath, LAMBDA_R, 1.0) * effR;
    let intG = thinFilmInterference(opticalPath, LAMBDA_G, 1.0) * effG;
    let intB = thinFilmInterference(opticalPath, LAMBDA_B, 1.0) * effB;
    
    return vec3<f32>(intR, intG, intB);
}

// Holographic scan with jitter
fn jitteredScanline(uv: vec2<f32>, time: f32, scanSpeed: f32, glitch: f32) -> vec2<f32> {
    // Base scanline
    let scan = sin(uv.y * 900.0 + time * (6.0 + scanSpeed * 4.0)) * 0.12;
    let slowScan = sin(uv.y * 15.0 - time * (1.0 + scanSpeed)) * 0.2;
    
    // Jitter from line noise
    let lineNoise = noise(vec2<f32>(uv.y * 80.0, time * 3.0));
    let jitter = (lineNoise - 0.5) * glitch * 0.04;
    
    // Wobble
    let wobble = sin(uv.y * 40.0 + time * 2.0) * 0.003;
    
    return vec2<f32>(scan + slowScan, jitter + wobble);
}

// 60Hz flicker with harmonics
fn projectionFlicker(time: f32) -> f32 {
    let f60 = sin(time * 377.0); // 60Hz
    let f120 = sin(time * 754.0) * 0.05; // 120Hz harmonic
    return 0.9 + 0.1 * f60 + f120;
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let scanSpeed = u.zoom_params.x;
  let glitch = u.zoom_params.y;
  let hue = u.zoom_params.z;
  let focus = u.zoom_params.w;

  var mouse = u.zoom_config.yz;
  let dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let angle = atan2(uv.y - mouse.y, (uv.x - mouse.x) * aspect);
  let stabilize = mix(1.0, smoothstep(0.0, 0.5, dist), focus);

  // ═══════════════════════════════════════════════════════════════
  // Bragg Interference Physics
  // ═══════════════════════════════════════════════════════════════
  
  let interference = braggInterference(uv, angle, dist, time, hue);
  
  // Scan effects with jitter
  let scanEffects = jitteredScanline(uv, time, scanSpeed, glitch * stabilize);
  let scan = scanEffects.x;
  let offset = vec2<f32>(scanEffects.y, 0.0);
  
  let wobble = sin(uv.y * 40.0 + time * 2.0) * 0.003 * stabilize;
  let sampleOffset = vec2<f32>(scanEffects.y + wobble, 0.0);

  // Chromatic aberration with interference modulation
  let aberr = glitch * 0.015 + 0.003;
  let r = textureSampleLevel(readTexture, u_sampler, uv + sampleOffset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + sampleOffset, 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, uv + sampleOffset - vec2<f32>(aberr, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Interference-based tint
  let tint = vec3<f32>(
    0.6 + 0.4 * sin(hue * 6.28318 + 0.0),
    0.7 + 0.3 * sin(hue * 6.28318 + 2.1),
    0.6 + 0.4 * sin(hue * 6.28318 + 4.2)
  );

  color = color * tint * 1.4;
  color += scan;
  
  // Add interference rainbow
  color = mix(color, interference * 1.5, glitch * 0.4);

  let flicker = 0.9 + 0.1 * noise(vec2<f32>(time * 4.0, uv.y * 3.0));
  color *= flicker;

  // Grid with interference
  let grid = sin(uv.x * 120.0) * sin(uv.y * 120.0) * 0.02;
  color += vec3<f32>(grid) * (1.0 + interference.g);
  
  // ═══════════════════════════════════════════════════════════════
  // Alpha Calculation with Physics
  // ═══════════════════════════════════════════════════════════════
  
  // Base hologram transparency
  let base_alpha = 0.04;
  
  // Bragg diffraction efficiency
  let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
  
  // Alpha boosted at Bragg interference peaks
  var alpha = base_alpha + diffraction_efficiency * 0.35;
  
  // Focus stabilization affects alpha
  alpha *= mix(1.0, 0.7 + 0.3 * stabilize, focus);
  
  // Scanline alpha modulation
  let scanAlpha = 0.85 + sin(uv.y * 900.0 + time * 5.0) * 0.15;
  alpha *= scanAlpha;
  
  // Glitch causes alpha spikes
  let glitchSpike = 1.0 + glitch * 0.2 * step(0.9, noise(vec2<f32>(uv.y, time * 10.0)));
  alpha *= glitchSpike;
  
  // 60Hz flicker
  alpha *= projectionFlicker(time);
  
  // Grid lines have slightly higher alpha
  let gridLines = step(0.98, sin(uv.x * 120.0)) + step(0.98, sin(uv.y * 120.0));
  alpha += gridLines * 0.05;
  
  // Pepper's ghost reflection
  let ghost_uv = uv + vec2<f32>(0.002, 0.002) * (1.0 + glitch * 0.5);
  let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
  color = mix(color, ghost, PEPPER_GHOST_REFLECTION);
  
  // Speckle
  let speckle = noise(uv * 100.0 + time);
  alpha *= 0.93 + speckle * 0.14;
  
  // Cap alpha
  alpha = min(alpha, 0.5);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
