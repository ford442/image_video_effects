// ═══════════════════════════════════════════════════════════════════
//  Holographic Projection GPT52 — Bragg Diffraction Volume Hologram
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware, semantic-alpha,
//            bragg-diffraction, thin-film-interference, upgraded-rgba
//  Complexity: High
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Wavelengths normalized for RGB channels
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  let sm = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, sm.x), mix(c, d, sm.x), sm.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
  let phase = TAU * opticalPath / wavelength;
  let targetPhase = (order + 0.5) * TAU;
  let phaseDiff = phase - targetPhase;
  let c = cos(phaseDiff);
  return c * c;
}

// Volume Bragg diffraction efficiency
fn braggDiffraction(angle: f32, wavelength: f32, braggAngle: f32) -> f32 {
  let angleDiff = angle - braggAngle;
  let kappa = PI / wavelength;
  let sinc_arg = kappa * angleDiff * 8.0;
  let sinc_val = sin(sinc_arg) / max(abs(sinc_arg), 0.001);
  return sinc_val * sinc_val;
}

fn braggInterference(uv: vec2<f32>, angle: f32, dist: f32, time: f32, hue: f32) -> vec3<f32> {
  let braggAngle = sin(uv.x * 3.0 + time * 0.25) * 0.5;
  let opticalPath = 0.43 + sin(angle + dist * 2.5) * 0.08;
  
  let effR = braggDiffraction(angle, LAMBDA_R, braggAngle + hue * 0.15);
  let effG = braggDiffraction(angle, LAMBDA_G, braggAngle);
  let effB = braggDiffraction(angle, LAMBDA_B, braggAngle - hue * 0.15);
  
  let intR = thinFilmInterference(opticalPath, LAMBDA_R, 1.0) * effR;
  let intG = thinFilmInterference(opticalPath, LAMBDA_G, 1.0) * effG;
  let intB = thinFilmInterference(opticalPath, LAMBDA_B, 1.0) * effB;
  
  return vec3<f32>(intR, intG, intB);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  // Sliders: exact parameter contracts
  let scanSpeed = u.zoom_params.x; // 0..5, default 1.2
  let glitch = u.zoom_params.y;    // 0..1, default 0.35
  let hue = u.zoom_params.z;       // 0..1, default 0.15
  let focus = u.zoom_params.w;     // 0..1, default 0.85

  // Audio channels
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 36.0;
    let damping = 12.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let angle = atan2(distVec.y, distVec.x);
  let stabilize = mix(1.0, smoothstep(0.0, 0.45, dist), focus * (1.0 - held * 0.3));

  // Volume Bragg interference spectrum
  let interference = braggInterference(uv, angle, dist, time, hue);

  // Holographic scan with line jitter
  let scanRate = 6.0 + scanSpeed * 4.0 + bass * 2.0;
  let scan = sin(uv.y * (800.0 + bass * 100.0) + time * scanRate) * 0.14;
  let slowScan = sin(uv.y * 18.0 - time * (1.0 + scanSpeed) + mids * 3.0) * 0.22;
  let lineNoise = noise(vec2<f32>(uv.y * 70.0, time * 4.0));
  let jitter = (lineNoise - 0.5) * glitch * 0.035 * stabilize * (1.0 + treble * 0.5);
  let wobble = sin(uv.y * 45.0 + time * 2.5) * 0.004 * stabilize;
  let sampleOffset = vec2<f32>(jitter + wobble, 0.0);

  // Chromatic aberration modulated by Bragg interference
  let aberr = (glitch * 0.018 + 0.003) * (1.0 + treble * 0.4);
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + sampleOffset + vec2<f32>(aberr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + sampleOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + sampleOffset - vec2<f32>(aberr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

  var color = vec3<f32>(rSample, gSample, bSample);

  // Prismatic spectral tint
  let tint = vec3<f32>(
    0.6 + 0.4 * sin(hue * TAU + 0.0 + mids * 0.5),
    0.7 + 0.3 * sin(hue * TAU + 2.094),
    0.6 + 0.4 * sin(hue * TAU + 4.188 - mids * 0.5)
  );

  color = color * tint * 1.35;
  color += (scan + slowScan);
  color = mix(color, color + interference * 1.6, glitch * 0.5 + 0.15);

  // 60Hz laser diode flicker
  let f60 = sin(time * 377.0) * 0.05;
  let flicker = 0.92 + 0.08 * noise(vec2<f32>(time * 5.0, uv.y * 4.0)) + f60;
  color *= flicker;

  // Volumetric Pepper's ghost reflection
  let ghost_uv = clamp(uv + vec2<f32>(0.003, 0.003) * (1.0 + glitch * 0.6), vec2<f32>(0.0), vec2<f32>(1.0));
  let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
  color = mix(color, ghost * 1.4, 0.15 + held * 0.1);

  // Click ripple bursts
  var clickPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = exp(-abs(rDist - age * 0.55) * 40.0) * exp(-age * 1.5);
    clickPulse += wave;
  }
  color += tint * (clickPulse * 0.6);

  // Exact previous frame load from dataTextureC
  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.12 * (1.0 - stabilize * 0.5));

  // ACES Tonemap
  let finalRGB = aces(color * (1.0 + bass * 0.15));

  // Semantic alpha: Bragg diffraction efficiency + transmission + depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let diffractionEff = (interference.r + interference.g + interference.b) * 0.333;
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(srcA, 0.35 + diffractionEff * 0.4 + luma * 0.3, 0.7) + clickPulse * 0.1 + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
