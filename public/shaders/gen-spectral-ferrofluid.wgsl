// ═══════════════════════════════════════════════════════════════════
//  Spectral Ferrofluid
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: Archimedean flux spirals from the four poles' stream functions woven across the iso-|B| bands; Cotton-Mouton birefringence (Michel-Levy tint + Maltese-cross isogyres from fieldDir); pole meniscus mounds with analytic specular normals
//  A packing: raw field state (fMag*0.25, fieldDir.x, fieldDir.y, alpha) — C read as fields
//  Description: Magnetic ferrofluid simulation with field-strength alpha
//    translucency. Field lines react to mouse as a magnetic source while
//    audio-reactive spikes and temporal feedback create organic fluid memory.
//    Secondary orbiting dipoles, FBM spike generation, and smooth specular
//    normals produce a living magnetic fluid aesthetic.
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
  zoom_params: vec4<f32>,  // x=FieldStrength, y=Viscosity, z=SpikeHeight, w=Turbulence
  ripples: array<vec4<f32>, 50>,
};

// ── Noise helpers ─────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  for (var i = 0; i < 5; i++) {
    v += a * vnoise(pp);
    pp = rot * pp * 2.0 + vec2<f32>(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

fn fbm3oct(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 3; i++) {
    v += a * vnoise(pp);
    pp = pp * 2.3 + vec2<f32>(4.1, 2.3);
    a *= 0.5;
  }
  return v;
}

// ── Magnetic dipole field ─────────────────────────────────────────
fn magneticField(uv: vec2<f32>, pole: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = uv - pole;
  let r2 = dot(d, d);
  let r = sqrt(r2);
  let r3 = max(r2 * r, 0.0001);
  // Dipole field: radial + angular components
  let radial = d / r3 * strength;
  let angular = vec2<f32>(-d.y, d.x) / (r2 + 0.01) * strength * 0.5;
  return radial + angular;
}

// ── Audio smoothing ───────────────────────────────────────────────
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// ── Palette ───────────────────────────────────────────────────────
fn ferroPalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 0.8);
  let d = vec3<f32>(0.0, 0.33, 0.67);
  return a + b * cos(6.28318 * (c * t + d));
}

fn spikePalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.6, 0.4, 0.3);
  let b = vec3<f32>(0.4, 0.4, 0.4);
  let c = vec3<f32>(1.0, 0.9, 0.7);
  let d = vec3<f32>(0.1, 0.2, 0.5);
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 1: per-pole Archimedean stream function ──────────────────
// magneticField() has radial |F| ~ s/r^2 and angular |F| ~ 0.5 s/r, so the
// exact single-pole streamline obeys d(theta)/dr = 0.5  ->  theta - 0.5 r = const.
// Weight w must make 10*w an integer so the atan2 seam is invisible in sin(10*psi).
fn poleStream(p: vec2<f32>, pole: vec2<f32>, w: f32) -> f32 {
  let d = p - pole;
  return w * (atan2(d.y, d.x) - 0.5 * length(d));
}

// ── Idea 3: Lorentzian meniscus mound over a pole (height + analytic grad) ──
// Returns (h, dh/dx, dh/dy); ferrofluid heaps where |B|^2 is large.
fn poleMound(p: vec2<f32>, pole: vec2<f32>, w: f32) -> vec3<f32> {
  let sig2 = 0.0144; // (0.12)^2
  let d = p - pole;
  let q = 1.0 + dot(d, d) / sig2;
  let h = w / q;
  let g = -w * 2.0 * d / (sig2 * q * q);
  return vec3<f32>(h, g);
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
  // Bug fix: plasmaBuffer[0].w is always uploaded as 0 — derive rms from xyz
  // (identical to HEAD at audio = 0, live with audio).
  let rms = (bass + mids + treble) / 3.0;

  // Mouse as magnetic source
  let mouse = u.zoom_config.yz;
  let mPos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDown = u.zoom_config.w > 0.5;
  let clickInvert = select(1.0, -1.0, mouseDown);

  // Parameters
  let fieldStrength = u.zoom_params.x * 3.0 + 0.5;
  let viscosity = u.zoom_params.y;
  let spikeHeight = u.zoom_params.z * 2.0 + 0.2;
  let turbulence = u.zoom_params.w;

  // Audio-reactive modulation
  let bassSmooth = bass_env(0.5, bass, 0.1, 0.05);
  let rmsSmooth = bass_env(0.3, rms, 0.08, 0.04);
  let trebleSmooth = bass_env(0.2, treble, 0.12, 0.06);

  // ── Fluid memory from temporal feedback ─────────────────────────
  let prevField = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  let prevStrength = prevField.r;
  let prevFieldDir = vec2<f32>(prevField.g, prevField.b);

  // ── Magnetic field computation ──────────────────────────────────
  // Primary dipole at mouse
  var field = magneticField(p, mPos, fieldStrength * clickInvert);

  // Secondary dipoles orbiting mouse
  let orbitSpeed = time * 0.3 * (1.0 + rmsSmooth * 2.0);
  let sec1 = mPos + vec2<f32>(cos(orbitSpeed), sin(orbitSpeed)) * 0.3;
  let sec2 = mPos + vec2<f32>(cos(orbitSpeed * 1.3 + 2.0), sin(orbitSpeed * 1.1 + 1.0)) * 0.25;
  let sec3 = mPos + vec2<f32>(cos(orbitSpeed * 0.7 + 4.0), sin(orbitSpeed * 0.9 + 3.0)) * 0.35;
  field += magneticField(p, sec1, fieldStrength * 0.4 * clickInvert);
  field += magneticField(p, sec2, fieldStrength * 0.3 * clickInvert);
  field += magneticField(p, sec3, fieldStrength * 0.2 * clickInvert);

  // Field magnitude
  var fMag = length(field);

  // Spike generation via FBM aligned to field direction
  var fieldDir = normalize(field + vec2<f32>(0.0001));
  let spikeUV = vec2<f32>(dot(p, fieldDir), dot(p, vec2<f32>(-fieldDir.y, fieldDir.x)));
  let spikeNoise = fbm2(spikeUV * 4.0 + time * 0.5);
  let spikes = pow(spikeNoise, 2.0) * spikeHeight * (1.0 + bassSmooth * 2.0);

  // Secondary spike layer for finer detail
  let fineSpike = fbm3oct(spikeUV * 8.0 - time * 0.3) * spikeHeight * 0.5;
  fMag += fineSpike * (1.0 + trebleSmooth);

  // Turbulence injection
  let turbNoise = fbm2(p * 6.0 - time * vec2<f32>(0.2, 0.15) * (1.0 + rmsSmooth * 3.0));
  let turbNoise2 = fbm3oct(p * 12.0 + time * vec2<f32>(0.1, 0.25));
  fMag += turbNoise * turbulence * (1.0 + rmsSmooth);
  fMag += turbNoise2 * turbulence * 0.3 * mids;

  // Temporal fluid memory - blend with previous frame
  let memoryBlend = viscosity * 0.3;
  fMag = mix(fMag, prevStrength * 4.0, memoryBlend);

  // Field direction continuity from temporal data
  fieldDir = normalize(mix(fieldDir, prevFieldDir, memoryBlend * 0.5) + vec2<f32>(0.0001));

  // ── Visual rendering ────────────────────────────────────────────
  // Field line tracing pattern
  let linePattern = sin(fMag * 12.0 - spikes * 8.0 + time * 0.5);
  let lineSharp = smoothstep(0.2, 0.6, linePattern);
  let lineDetail = sin(fMag * 24.0 + fineSpike * 16.0 - time * 0.8);
  let lineDetailSharp = smoothstep(0.3, 0.7, lineDetail) * 0.3;

  // Spectral coloring based on field strength
  let spectralT = fMag * 0.3 + trebleSmooth * 0.2 + time * 0.03;
  var col = ferroPalette(spectralT) * (0.3 + lineSharp * 0.7);
  col += spikePalette(spectralT + 0.5) * lineDetailSharp;

  // ── Idea 2: Cotton-Mouton birefringence (Michel-Levy tint + isogyres) ──
  // Field-induced delta-n ~ B^2 (Langevin-saturated) -> optical path difference.
  // Between crossed polarizers: I = sin^2(2*alpha) * sin^2(pi*OPD/lambda).
  let cmSat = 1.0 - exp(-0.05 * fMag * fMag);
  let opd = 2.4 * cmSat;                                  // microns
  let lambdaRGB = vec3<f32>(0.65, 0.55, 0.45);            // microns
  let retard = sin(3.14159265 * opd / lambdaRGB);
  let mlTint = retard * retard;                           // Michel-Levy interference colour
  let polAngle = time * 0.05;                             // slowly turning polarizer
  let polDir = vec2<f32>(cos(polAngle), sin(polAngle));
  let cosA = dot(fieldDir, polDir);
  let sinA = fieldDir.x * polDir.y - fieldDir.y * polDir.x;
  let sin2A = 2.0 * sinA * cosA;
  let isogyre = sin2A * sin2A;                            // 0 on the Maltese-cross brushes
  col = col * (0.6 + 0.4 * isogyre) + mlTint * isogyre * (0.25 + 0.35 * lineSharp);

  // ── Idea 1: Archimedean flux spirals woven across the iso-|B| bands ──
  // Weights x20 = 20/8/6/4 integer windings -> seamless atan2.
  let psi = poleStream(p, mPos, 1.0) + poleStream(p, sec1, 0.4)
          + poleStream(p, sec2, 0.3) + poleStream(p, sec3, 0.2);
  let fluxPhase = 20.0 * psi - time * 0.4 + turbNoise * turbulence * 1.5;
  let invR = 1.0 / max(length(p - mPos), 0.001)
           + 0.4 / max(length(p - sec1), 0.001)
           + 0.3 / max(length(p - sec2), 0.001)
           + 0.2 / max(length(p - sec3), 0.001);
  let phasePerPx = 20.0 * invR / res.y;                   // phase change per pixel
  let fluxFade = 1.0 - smoothstep(0.35, 0.9, phasePerPx); // tubes merge into glow at the poles
  let tubeD = abs(sin(fluxPhase));
  let tube = (1.0 - smoothstep(0.06, 0.06 + 1.5 * phasePerPx, tubeD)) * fluxFade;
  // inked groove in the fluid; glints where a flux tube crosses a contour band
  col = col * (1.0 - 0.45 * tube) + spikePalette(spectralT + 0.25) * tube * lineSharp * 0.35;

  // Specular spike highlights
  let highlight = pow(spikes, 3.0) * (1.0 + bassSmooth);
  let highlight2 = pow(fineSpike, 4.0) * trebleSmooth * 2.0;
  col += vec3<f32>(1.0, 0.9, 0.7) * highlight * 0.8;
  col += vec3<f32>(0.9, 0.95, 1.0) * highlight2 * 0.6;

  // Mouse proximity glow
  let mouseDist = length(p - mPos);
  let mouseGlow = exp(-mouseDist * 4.0) * 0.5 * (1.0 + bassSmooth);
  col += ferroPalette(time * 0.1 + 0.5) * mouseGlow;

  // Ripple-driven magnetic disturbances
  // Bug fix: config.y is the lifetime click count — clamp to the 50-slot array.
  let ripCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < ripCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age < 0.0 || age > 3.0) { continue; }
    let rp = (r.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let rd = length(p - rp);
    let rippleMag = exp(-rd * rd * 8.0) * exp(-age * 1.5) * 0.3;
    col += ferroPalette(age + fMag) * rippleMag;
  }

  // ── Idea 3: pole meniscus mounds (analytic specular normals) ──
  // Fluid heaps over every pole (|B|^2 pull, so held-mouse inversion keeps it).
  let mound = poleMound(p, mPos, 1.0) + poleMound(p, sec1, 0.4)
            + poleMound(p, sec2, 0.3) + poleMound(p, sec3, 0.2);
  let moundSlope = fieldStrength * 0.12;
  let nrm = normalize(vec3<f32>(-mound.yz * moundSlope, 1.0));
  let lightDir = normalize(vec3<f32>(-0.45, 0.55, 0.7));
  let halfV = normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0));
  let moundSpec = pow(max(dot(nrm, halfV), 0.0), 64.0) * (0.7 + 0.6 * spikeNoise);
  let moundFres = pow(max(1.0 - nrm.z, 0.0), 2.0);
  let moundMask = smoothstep(0.05, 0.6, mound.x);
  col = col * (1.0 - 0.35 * moundMask)                     // glossy black body
      + vec3<f32>(1.0, 0.96, 0.9) * moundSpec * 1.2        // shoulder ring glint
      + ferroPalette(spectralT + 0.15) * moundFres * 1.5;  // Fresnel rim

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.4;
  col *= vignette;

  // Subtle chromatic aberration at field edges
  let caStrength = smoothstep(0.1, 0.4, fMag) * 0.03;
  col = vec3<f32>(
    col.r + caStrength * fieldDir.x,
    col.g,
    col.b - caStrength * fieldDir.x
  );

  // Gamma correction
  col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

  // ── Alpha encoding ──────────────────────────────────────────────
  // Alpha = magnetic field strength: strong fields = opaque spikes,
  // weak fields = transparent gaps. Modulated by glow intensity.
  let glowAlpha = highlight * 0.6 + mouseGlow * 0.4 + highlight2 * 0.3;
  var alpha = clamp(fMag * 0.4 + glowAlpha + lineSharp * 0.3, 0.0, 1.0);
  // Areas far from field lines become translucent
  alpha = mix(alpha * 0.3, alpha, smoothstep(0.0, 0.15, fMag));
  // Temporal memory slightly increases alpha consistency
  alpha = mix(alpha, clamp(prevField.a * 1.1, 0.0, 1.0), memoryBlend * 0.2);
  // Idea 3: heaped fluid over the poles is opaque; glints read as solid
  alpha = clamp(max(alpha, moundMask * 0.85) + moundSpec * 0.3, 0.0, 1.0);

  let outCol = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture, gid.xy, outCol);
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(fMag * 0.25, fieldDir.x, fieldDir.y, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(fMag * 0.1, 0.0, 0.0, 0.0));
}
