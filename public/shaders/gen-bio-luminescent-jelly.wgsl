// ═══════════════════════════════════════════════════════════════════
//  Bio-Luminescent Jelly
//  Category: generative
//  Features: jellyfish, bioluminescence, sdf-tentacles, audio-pulse, mouse-current, depth-glow, organic-motion
//  Complexity: High
//  Updated: 2026-05-31
//  By: Grok (visual flourish pass — richer pulsing, color, and atmospheric underwater light)
// ═══════════════════════════════════════════════════════════════════
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
  zoom_params: vec4<f32>,  // x=PulseSpeed, y=TentacleLength, z=GlowIntensity, w=DriftSpeed
  ripples: array<vec4<f32>, 50>,
};

// ── Noise & hash ──────────────────────────────────────────────────
fn hash_j(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn hash2_j(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn vnoise_j(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2_j(i + vec2<f32>(0.0, 0.0)), hash2_j(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2_j(i + vec2<f32>(0.0, 1.0)), hash2_j(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// ── SDF helpers ───────────────────────────────────────────────────
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn smin_j(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ── Audio smoothing ───────────────────────────────────────────────
fn env_j(prev: f32, val: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, val > prev);
  return mix(prev, val, k);
}

// ── Exponential glow ──────────────────────────────────────────────
fn glow(d: f32, intensity: f32) -> f32 {
  return exp(-d * d * intensity);
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
  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Mouse as attraction point
  let mouse = u.zoom_config.yz;
  let mPos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDown = u.zoom_config.w > 0.5;

  // Parameters
  let pulseSpeed = u.zoom_params.x * 3.0 + 0.5;
  let tentacleLen = u.zoom_params.y * 0.4 + 0.1;
  let glowIntensity = u.zoom_params.z * 2.0 + 0.3;
  let driftSpeed = u.zoom_params.w;

  // Audio smoothing
  let bassSmooth = env_j(0.5, bass, 0.1, 0.06);
  let trebleSmooth = env_j(0.3, treble, 0.12, 0.07);

  // ── Temporal feedback for pulse phase ───────────────────────────
  let prevState = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  var pulsePhase = prevState.r;
  pulsePhase = env_j(pulsePhase, sin(time * pulseSpeed) * 0.5 + 0.5, 0.05, 0.02);

  // ── Jellyfish position & drift ──────────────────────────────────
  let drift = vec2<f32>(
    sin(time * 0.2 * driftSpeed) * 0.15,
    cos(time * 0.15 * driftSpeed) * 0.1 + sin(time * 0.5) * 0.02
  );
  // Mouse attraction
  let attraction = (mPos - drift) * 0.15;
  let jellyPos = drift + attraction;

  // ── Bell body (SDF) ─────────────────────────────────────────────
  let bellRadius = 0.18 + pulsePhase * 0.04 * (1.0 + bassSmooth);
  let bellP = p - jellyPos;
  let bellPScaled = vec2<f32>(bellP.x, bellP.y * 1.3);
  var dBell = sdCircle(bellPScaled, bellRadius);

  // Bell dome shape - flatten bottom
  if (bellP.y > 0.0) {
    dBell = max(dBell, bellP.y - bellRadius * 0.3);
  }

  // ── Tentacles (line segment SDFs) ───────────────────────────────
  let numTentacles = 8;
  var dTentacles = 1000.0;
  var tentacleGlow = 0.0;

  for (var i = 0; i < numTentacles; i++) {
    let fi = f32(i);
    let angle = fi / f32(numTentacles) * 6.28318 + hash_j(fi * 3.7) * 0.3;
    let baseOffset = vec2<f32>(cos(angle), sin(angle)) * bellRadius * 0.7;
    let base = jellyPos + baseOffset;

    // Sine wave propagation for tentacle movement
    let wavePhase = time * pulseSpeed + fi * 0.8;
    let waveAmp = 0.06 * (1.0 + bassSmooth * 0.5) * (fi / f32(numTentacles) + 0.5);

    // Segments per tentacle
    let segments = 5;
    var prevPoint = base;
    for (var s = 1; s <= segments; s++) {
      let fs = f32(s);
      let tNorm = fs / f32(segments);
      let segLen = tentacleLen / f32(segments);

      let swayX = sin(wavePhase + fs * 0.5) * waveAmp * tNorm;
      let swayY = -segLen + sin(wavePhase * 0.7 + fs * 0.3) * waveAmp * 0.3 * tNorm;

      let nextPoint = prevPoint + vec2<f32>(swayX, swayY);
      let dSeg = sdSegment(p, prevPoint, nextPoint);
      let segThickness = 0.008 * (1.0 - tNorm * 0.5);
      dTentacles = smin_j(dTentacles, dSeg - segThickness, 0.02);

      // Glow along tentacles
      tentacleGlow += glow(dSeg, 80.0 * glowIntensity) * (1.0 - tNorm * 0.3);

      prevPoint = nextPoint;
    }
  }

  // ── Sparkle particles (treble-driven) ───────────────────────────
  var sparkle = 0.0;
  let numSparkles = i32(trebleSmooth * 20.0 + 5.0);
  for (var i = 0; i < 15; i++) {
    if (i >= numSparkles) { break; }
    let fi = f32(i);
    let spTime = time * 2.0 + fi * 3.1;
    let spPos = jellyPos + vec2<f32>(
      sin(spTime * 0.7 + fi) * bellRadius * 1.5,
      cos(spTime * 0.5 + fi * 1.3) * bellRadius * 1.2 - 0.1
    );
    let dSp = length(p - spPos);
    let spSize = 0.005 + trebleSmooth * 0.01;
    let spFlash = step(dSp, spSize) * (0.5 + 0.5 * sin(spTime * 8.0));
    sparkle += spFlash;
  }

  // ── Bioluminescent pulse ────────────────────────────────────────
  let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 2.0 + bassSmooth * 3.14159);
  let pulseGlow = glow(dBell, 30.0 * glowIntensity * (0.5 + pulse * 0.5));

  // ── Shockwave on click ──────────────────────────────────────────
  var shockwave = 0.0;
  if (mouseDown) {
    let swDist = length(p - mPos);
    let swRadius = fract(time * 2.0) * 0.5;
    let swThickness = 0.03;
    shockwave = glow(abs(swDist - swRadius), 1.0 / (swThickness * swThickness)) * 0.5;
  }

  // ── Color composition ───────────────────────────────────────────
  // Bell color - deep sea translucent
  let bellColor = vec3<f32>(0.05, 0.15, 0.25) * (0.6 + pulsePhase * 0.4);

  // Bioluminescent glow color
  let glowHue = fract(time * 0.03 + bassSmooth * 0.1 + 0.6);
  let glowCol = 0.5 + 0.5 * cos(vec3<f32>(glowHue * 6.28318) + vec3<f32>(0.0, 2.094, 4.189));
  let bioGlow = glowCol * pulseGlow * glowIntensity * (1.0 + bassSmooth * 2.0);

  // Tentacle color
  let tentacleColor = vec3<f32>(0.1, 0.3, 0.4) * tentacleGlow;

  // Combine
  var col = bellColor;
  col += tentacleColor;
  col += bioGlow;
  col += glowCol * sparkle * trebleSmooth * 3.0;
  col += glowCol * shockwave * 2.0;

  // Inner organs glow
  let innerGlow = glow(dBell - bellRadius * 0.3, 20.0 * glowIntensity) * pulse;
  col += vec3<f32>(0.2, 0.6, 0.8) * innerGlow;

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.25;
  col *= vignette;

  col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ── Alpha encoding ──────────────────────────────────────────────
  // Alpha = glow intensity + tentacle density.
  // Glowing parts are translucent (lower alpha), dense body is more opaque.
  let densityAlpha = smoothstep(0.02, -0.02, dBell) * 0.7;
  let tentacleAlpha = smoothstep(0.005, -0.005, dTentacles) * 0.5;
  let glowAlpha = (pulseGlow + tentacleGlow * 0.3 + innerGlow * 0.5) * 0.4;

  var alpha = densityAlpha + tentacleAlpha;
  // Glow reduces density alpha for translucency effect
  alpha = mix(alpha, glowAlpha, smoothstep(0.0, 0.5, glowAlpha));
  alpha += sparkle * trebleSmooth * 0.3;
  alpha += shockwave * 0.2;
  alpha = clamp(alpha, 0.0, 0.92);

  let outCol = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture, gid.xy, outCol);
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(pulsePhase, 0.0, 0.0, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(alpha, 0.0, 0.0, 0.0));
}
