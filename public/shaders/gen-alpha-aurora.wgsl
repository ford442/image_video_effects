// ═══════════════════════════════════════════════════════════════════
//  Alpha Aurora
//  Category: generative
//  Features: aurora, spectral-bands, curl-noise-flow, audio-reactive, mouse-wind, density-alpha, atmospheric
//  Complexity: High
//  Chunks From: previous aurora work + improved spectral layering
//  Created: 2026-05-23
//  Upgraded: 2026-06-06
//  Updated: 2026-05-31
//  By: Grok (visual flourish pass — richer color, motion, and atmospheric depth)
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

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: value noise 3D ═══
fn vnoise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let h = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 0.0)), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), f.x),
      f.y
    ),
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.0, 1.0)), f.x),
      f.y
    ),
    f.z
  );
}

// ═══ CHUNK: fbm 3D ═══
fn fbm3(p: vec3<f32>) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0u; i < 5u; i = i + 1u) {
    val = val + amp * vnoise3(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return val;
}

// ═══ CHUNK: domain warped fbm ═══
fn dwfbm3(p: vec3<f32>, t: f32) -> f32 {
  let q = vec3<f32>(
    fbm3(p + vec3<f32>(0.0, 0.0, 0.0)),
    fbm3(p + vec3<f32>(5.2, 1.3, 2.8)),
    fbm3(p + vec3<f32>(1.7, 9.2, 3.1))
  );
  return fbm3(p + 1.5 * q + vec3<f32>(t * 0.1, t * 0.05, 0.0));
}

// ═══ CHUNK: curl noise approximation ═══
fn curlNoise(p: vec3<f32>, t: f32) -> vec3<f32> {
  let eps = 0.01;
  let n1 = dwfbm3(p + vec3<f32>(eps, 0.0, 0.0), t);
  let n2 = dwfbm3(p - vec3<f32>(eps, 0.0, 0.0), t);
  let n3 = dwfbm3(p + vec3<f32>(0.0, eps, 0.0), t);
  let n4 = dwfbm3(p - vec3<f32>(0.0, eps, 0.0), t);
  let n5 = dwfbm3(p + vec3<f32>(0.0, 0.0, eps), t);
  let n6 = dwfbm3(p - vec3<f32>(0.0, 0.0, eps), t);
  let dx = (n1 - n2) / (2.0 * eps);
  let dy = (n3 - n4) / (2.0 * eps);
  let dz = (n5 - n6) / (2.0 * eps);
  return normalize(vec3<f32>(dy - dz, dz - dx, dx - dy));
}

// ═══ CHUNK: spectral color mapping (enhanced visual richness) ═══
fn spectralColor(t: f32, temp: f32, audio: vec3<f32>) -> vec3<f32> {
  // t: 0-1 spectral band position
  // temp: 0-1 color temperature shift
  // audio: bass, mids, treble for dynamic color modulation
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let hue = fract(t * 0.7 + temp * 0.15 + 0.55 + treble * 0.08);
  let h6 = hue * 6.0;
  let c = 1.0;
  let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var col: vec3<f32>;
  if (h6 < 1.0) { col = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { col = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { col = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { col = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { col = vec3<f32>(x, 0.0, c); }
  else { col = vec3<f32>(c, 0.0, x); }

  // Richer aurora palette with audio influence
  col = mix(col, vec3<f32>(0.15, 0.85, 0.7), 0.35 + mids * 0.15);
  col = mix(col, vec3<f32>(0.6, 0.3, 0.9), treble * 0.2);

  // Temperature + bass for dynamic color temperature
  let cool = vec3<f32>(0.1, 0.45, 0.95);
  let warm = vec3<f32>(0.95, 0.35, 0.55);
  col = mix(col, mix(cool, warm, temp + bass * 0.2), 0.4);

  return col;
}

// ═══ CHUNK: bass envelope smoothing ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
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
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let time = u.config.x;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;
  let audio = vec3<f32>(bass, mids, treble);

  // Parameters
  let bandSpeed = mix(0.1, 0.8, u.zoom_params.x);
  let colorTemp = u.zoom_params.y; // 0=cool, 1=warm
  let densityParam = mix(0.3, 1.0, u.zoom_params.z);
  let glowParam = mix(0.2, 1.2, u.zoom_params.w);

  // Mouse: Y controls aurora altitude, X controls color temperature offset
  let mousePos = u.zoom_config.yz;
  let altitudeShift = (mousePos.y - 0.5) * 0.4;
  let tempShift = mousePos.x * 0.2;

  // Smooth bass for audio reactivity
  var prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.15, 0.02);
  extraBuffer[0] = smoothBass;

  // Temporal feedback: read previous frame state
  let prevState = textureLoad(dataTextureC, coord, 0);

  // ═══ AURORA BAND GENERATION ═══
  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDensity = 0.0;
  var accumulatedAlpha = 0.0;

  // Multiple spectral bands with different altitudes and speeds
  let bandCount = 4;
  for (var b = 0; b < bandCount; b = b + 1) {
    let bandT = f32(b) / f32(bandCount - 1);

    // Band base altitude varies with index
    let baseAltitude = 0.45 + bandT * 0.25 + altitudeShift;

    // Each band has distinct horizontal movement
    let speedOffset = bandT * 0.3 + 0.2;
    let motionX = time * bandSpeed * speedOffset * (1.0 + smoothBass * 0.5);
    let motionY = time * bandSpeed * 0.15 * (1.0 + smoothBass * 0.3);

    // Sample position for curl noise
    let samplePos = vec3<f32>(
      uv.x * 3.0 + motionX + f32(b) * 7.3,
      uv.y * 2.0 + motionY,
      time * 0.1 + f32(b) * 1.7
    );

    // Curl noise drives band deformation
    let curl = curlNoise(samplePos, time);
    let deform = curl.x * 0.15 + curl.y * 0.08;

    // Band vertical profile: Gaussian-ish with domain warping
    let bandY = uv.y - baseAltitude - deform;
    let bandWidth = mix(0.06, 0.14, bandT + smoothBass * 0.2);
    let bandProfile = exp(-(bandY * bandY) / (bandWidth * bandWidth));

    // FBM detail adds fine structure within bands
    let detailNoise = dwfbm3(
      vec3<f32>(uv.x * 6.0 + motionX * 2.0, uv.y * 4.0, time * 0.2 + f32(b)),
      time
    );
    let detailMask = smoothstep(0.35, 0.65, detailNoise);

    // Band intensity modulated by audio
    let audioBoost = 1.0 + smoothBass * 0.6 + mids * 0.3 * bandT;
    var bandIntensity = bandProfile * detailMask * audioBoost * densityParam;

    // Exponential falloff toward top and bottom of screen for atmospheric perspective
    let atmoFalloff = exp(-abs(uv.y - 0.5) * 2.5);
    bandIntensity = bandIntensity * atmoFalloff;

    // Ripple interaction: aurora intensifies near ripples
    var rippleBoost = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r = r + 1u) {
      let ripple = u.ripples[r];
      let rAge = time - ripple.z;
      if (rAge < 0.0 || rAge > 3.0) { continue; }
      let rDist = length(uv - ripple.xy);
      let rInfluence = smoothstep(0.25, 0.0, rDist) * exp(-rAge * 1.5);
      rippleBoost = rippleBoost + rInfluence * 0.4;
    }
    bandIntensity = bandIntensity + rippleBoost * bandProfile;

    // Spectral color for this band
    let bandColor = spectralColor(bandT, colorTemp + tempShift, audio);

    // Accumulate with density-weighted blending
    let bandDensity = clamp(bandIntensity, 0.0, 1.0);
    let bandAlpha = bandDensity * (0.4 + bandT * 0.3);

    accumulatedColor = accumulatedColor + bandColor * bandDensity * glowParam;
    accumulatedDensity = accumulatedDensity + bandDensity;
    accumulatedAlpha = accumulatedAlpha + bandAlpha;
  }

  // Normalize accumulated density
  accumulatedDensity = clamp(accumulatedDensity, 0.0, 1.0);
  accumulatedAlpha = clamp(accumulatedAlpha, 0.0, 1.0);

  // Add atmospheric glow based on total density
  let glowColor = spectralColor(0.5, colorTemp + tempShift, audio) * 0.3;
  accumulatedColor = accumulatedColor + glowColor * accumulatedDensity * accumulatedDensity * glowParam;

  // Star field background (subtle)
  let starNoise = hash12(uv * 437.0 + vec2<f32>(13.37, 71.73));
  let starMask = step(0.997, starNoise) * (1.0 - accumulatedDensity * 0.8);
  let starColor = vec3<f32>(0.8, 0.9, 1.0) * starMask * (0.5 + treble * 0.5);
  accumulatedColor = accumulatedColor + starColor;

  // Temporal feedback: blend with previous frame for smooth persistence
  let persistence = mix(0.75, 0.92, 1.0 - bandSpeed);
  let prevColor = prevState.rgb;
  let prevAlpha = prevState.a;

  var finalColor = mix(accumulatedColor, prevColor, persistence * 0.15);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(2.0));

  // Soft tone mapping
  finalColor = finalColor / (1.0 + finalColor * 0.4);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha encodes aurora band density for smooth translucency blending
  // Thicker bands = more opaque, thin atmosphere = transparent
  let finalAlpha = clamp(accumulatedAlpha * 0.8 + prevAlpha * 0.1, 0.0, 1.0);

  // Depth for chromatic + pass-through
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Store state for temporal feedback
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));

  finalColor = acesToneMap(finalColor * 1.1);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
