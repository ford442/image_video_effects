// ═══════════════════════════════════════════════════════════════════
//  Bio-Luminescent Jelly
//  Category: generative
//  Features: jellyfish, bioluminescence, sdf-tentacles, audio-pulse, mouse-current, depth-glow, organic-motion, upgraded-rgba
//  Complexity: High
//  Updated: 2026-05-31
//  By: Grok (visual flourish pass — richer pulsing, color, and atmospheric underwater light)
//  Upgraded: 2026-10-19
//  Ideas: jet propulsion (contraction wave stretches tentacles, drift-lag streaming); anatomy (radial canals, margin ring canal, horseshoe gonad, notched lappets); jelly-lit marine snow; oral arms; bell muscle striations;
//         Beer–Lambert mesoglea (§12.2F: chord transmission + milky in-scatter); shed vortex rings with shear-lit dinoflagellates stirring the snow (§12.1 T2)
//  A packing: raw pulsePhase in A.r (identical at every pixel, read back from C.r), A.g/A.b = 0, A.a = semantic alpha (0.86 water + 0.14 x body coverage); writeTexture = ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=PulseSpeed, y=TentacleLength, z=GlowIntensity, w=DriftSpeed

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

fn rot_j(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, s, -s, c);
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

// ── IDEA 3: marine snow, stateless sinking specks lit by the jelly's own glow ──
fn marine_snow(p: vec2<f32>, t: f32, scale: f32, fall: f32, seed: f32, radius: f32, jelly: vec2<f32>, pulse: f32) -> f32 {
  let off = vec2<f32>(0.0, t * fall);
  let q = p * scale - off;                 // pattern sinks toward +y
  let cell = floor(q);
  let cs = cell + vec2<f32>(seed, seed * 0.37);
  let h1 = hash2_j(cs);
  let h2 = hash2_j(cs + vec2<f32>(17.3, 5.1));
  let h3 = hash2_j(cs + vec2<f32>(41.9, 9.7));
  let present = step(0.45, h3);
  let c = vec2<f32>(0.3 + 0.4 * h1 + 0.1 * sin(t * 0.6 + h2 * 40.0), 0.3 + 0.4 * h2);
  let sp = (cell + c + off) / scale;       // speck position in p space
  let d = length(p - sp);
  let dj = length(sp - jelly);
  let lit = (0.55 + 0.45 * pulse) / (1.0 + dj * dj * 14.0);
  let core = exp(-d * d / (radius * radius));
  let halo = exp(-d * d / (radius * radius * 12.0));
  let twinkle = 0.75 + 0.25 * sin(t * 1.7 + h1 * 50.0);
  return present * twinkle * (core * lit + halo * lit * lit * 1.5);
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
    // IDEA 2 (lappets): 8 rounded lobes with V-notches along the flat margin
    let lappet = 0.014 * sqrt(abs(sin(bellP.x / bellRadius * 12.566)));
    dBell = max(dBell, bellP.y - bellRadius * 0.3 - lappet);
  }

  // ── Tentacles (line segment SDFs) ───────────────────────────────
  let numTentacles = 8;
  var dTentacles = 1000.0;
  var tentacleGlow = 0.0;

  // IDEA 1 (jet propulsion): analytic drift velocity (jellyPos = 0.85*drift + 0.15*mouse)
  // and a contraction wave that reaches each segment slightly later than the last.
  let driftVel = 0.85 * vec2<f32>(
    0.03 * driftSpeed * cos(time * 0.2 * driftSpeed),
    -0.015 * driftSpeed * sin(time * 0.15 * driftSpeed) + 0.01 * cos(time * 0.5)
  );
  let lagVel = -driftVel * 3.5;
  var thr: array<f32, 5>;
  for (var k = 0; k < 5; k++) {
    thr[k] = max(0.0, -cos(pulseSpeed * (time - 0.09 * f32(k + 1))));
  }

  for (var i = 0; i < numTentacles; i++) {
    let fi = f32(i);
    let angle = fi / f32(numTentacles) * 6.28318 + hash_j(fi * 3.7) * 0.3;
    // Margin ring seen edge-on: x spreads with cos, back tentacles sit slightly higher.
    let baseOffset = vec2<f32>(cos(angle) * bellRadius * 0.85, bellRadius * (0.28 + 0.06 * sin(angle)));
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

      // IDEA 1: thrust straightens + stretches the segment; drift lag streams it backward
      let thrust = thr[s - 1];
      let lag = lagVel * (tNorm / f32(segments));
      let swayX = sin(wavePhase + fs * 0.5) * waveAmp * (1.0 - 0.4 * thrust) * tNorm + lag.x;
      let swayY = segLen * (1.0 + 0.25 * thrust) + sin(wavePhase * 0.7 + fs * 0.3) * waveAmp * 0.3 * tNorm + lag.y;

      let nextPoint = prevPoint + vec2<f32>(swayX, swayY);
      let dSeg = sdSegment(p, prevPoint, nextPoint);
      let segThickness = 0.008 * (1.0 - tNorm * 0.5);
      dTentacles = smin_j(dTentacles, dSeg - segThickness, 0.02);

      // Glow along tentacles
      tentacleGlow += glow(dSeg, 1100.0 * glowIntensity) * (1.0 - tNorm * 0.3);

      prevPoint = nextPoint;
    }
  }

  // Oral arms — four short frilled arms under the bell, shorter than the tentacles.
  var armGlow = 0.0;
  for (var a = 0; a < 4; a = a + 1) {
    let af = f32(a);
    let ang = af * 1.570796 + time * 0.15;
    let base = jellyPos + vec2<f32>(cos(ang), 0.04) * bellRadius * 0.35 + vec2<f32>(0.0, bellRadius * 0.15);
    let frill = sin(af * 3.0 + time * pulseSpeed) * 0.04;
    let tip = base + vec2<f32>(frill, tentacleLen * 0.28);
    armGlow += glow(sdSegment(p, base, tip), 800.0 * glowIntensity) * 0.7;
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
  let pulseGlow = glow(dBell, 700.0 * glowIntensity * (0.5 + pulse * 0.5));

  // ── Shockwave on click ──────────────────────────────────────────
  var shockwave = 0.0;
  if (mouseDown) {
    let swDist = length(p - mPos);
    let swRadius = fract(time * 2.0) * 0.5;
    let swThickness = 0.03;
    shockwave = glow(abs(swDist - swRadius), 1.0 / (swThickness * swThickness)) * 0.5;
  }

  // ── IDEA 2: anatomy (canals, margin ring canal, horseshoe gonad) ─
  var anatomy = vec3<f32>(0.0);
  var anatomyLum = 0.0;
  if (dBell < 0.0) {
    let depth = -dBell;
    let rad = length(bellPScaled) / bellRadius;
    let ang = atan2(bellPScaled.x, -bellPScaled.y);          // 0 = dome apex
    let sector = abs(fract(ang * 1.27324) - 0.5);            // 4 canals at half-octants
    let arcD = sector * 0.7854 * rad * bellRadius;
    let canalFade = smoothstep(0.1, 0.3, rad) * smoothstep(0.008, 0.02, depth);
    let travel = 0.65 + 0.35 * sin(rad * 10.0 - time * pulseSpeed * 2.0);
    let canal = exp(-arcD * arcD * 40000.0) * canalFade * travel;
    let ringD = depth - 0.014;
    let ring = exp(-ringD * ringD * 30000.0);
    let gr = rad - (0.34 + 0.03 * pulsePhase);
    let gonadOpen = 1.0 - smoothstep(2.3, 2.9, abs(ang));
    let gonad = exp(-gr * gr * 400.0) * gonadOpen * (0.8 + 0.2 * cos(ang * 6.0));
    let canalLum = canal * 0.5 + ring * 0.35;
    let gonadLum = gonad * 0.55 * (0.6 + 0.4 * pulse);
    let muscle = abs(fract(ang * 6.0) - 0.5);
    let stria = exp(-muscle * 22.0) * smoothstep(0.2, 0.85, rad) * (0.3 + pulsePhase * 0.7);
    anatomy = vec3<f32>(0.35, 0.85, 1.0) * canalLum + vec3<f32>(1.0, 0.5, 0.4) * gonadLum;
    anatomy += vec3<f32>(0.7, 0.95, 1.0) * stria * 0.22;
    anatomyLum = canalLum + gonadLum;
  }

  // ── Idea 7: shed vortex rings ───────────────────────────────────
  // Each contraction peak (pulseSpeed·t = π mod 2π, where thr[] peaks) sheds a ring from the
  // margin. Its cross-section is two counter-rotating cores that sink below the bell and decay.
  var snowP = p;
  var ringSpark = 0.0;
  let cyc = floor((time * pulseSpeed - 3.14159) / 6.28318);
  for (var k = 0; k < 2; k = k + 1) {
    let tBirth = (3.14159 + 6.28318 * (cyc - f32(k))) / pulseSpeed;
    let age = max(time - tBirth, 0.0);
    let circ = smoothstep(0.0, 0.25, age) * exp(-age * 0.55) * (1.0 + bassSmooth * 0.6);
    let sink = 0.16 * (1.0 - exp(-age / 1.3));
    let spread = bellRadius * (0.8 + 0.12 * age);
    let ringY = jellyPos.y + bellRadius * 0.32 + sink;
    for (var sgn = -1; sgn <= 1; sgn = sgn + 2) {
      let side = f32(sgn);
      let core = vec2<f32>(jellyPos.x + side * spread, ringY);
      // Fluid runs down through the ring centre: left core turns one way, right core the other.
      let spin = -side;
      let rs = snowP - core;
      let swirl = spin * circ * 0.011 / (dot(rs, rs) + 0.0018);
      snowP = core + rot_j(swirl) * rs;
      // Shear in the core trips dinoflagellate flashes: spiral arms of sparks around a hollow core.
      let rel = p - core;
      let r = length(rel);
      let a = atan2(rel.y, rel.x);
      let arms = max(sin(2.0 * a * spin + r * 70.0 - time * 5.0), 0.0);
      let shell = exp(-r * r / 0.0022) * (1.0 - exp(-r * r / 0.00025));
      let grains = smoothstep(0.62, 0.9, vnoise_j(rot_j(spin * age * 2.5) * rel * 220.0 + vec2<f32>(f32(k) * 13.0 + side * 5.0, cyc * 3.7)));
      ringSpark += circ * shell * arms * (0.6 + 2.2 * grains);
    }
  }

  // ── Color composition ───────────────────────────────────────────
  // Water colour (named bellColor at HEAD: it fills the whole frame)
  let bellColor = vec3<f32>(0.05, 0.15, 0.25) * (0.6 + pulsePhase * 0.4);

  // Bioluminescent glow color
  let glowHue = fract(time * 0.03 + bassSmooth * 0.1 + 0.6);
  let glowCol = 0.5 + 0.5 * cos(vec3<f32>(glowHue * 6.28318) + vec3<f32>(0.0, 2.094, 4.189));
  let bioGlow = glowCol * pulseGlow * glowIntensity * (1.0 + bassSmooth * 2.0);

  // Tentacle color
  let tentacleColor = vec3<f32>(0.1, 0.3, 0.4) * tentacleGlow + vec3<f32>(0.45, 0.85, 0.7) * armGlow;

  // ── Idea 6: Beer–Lambert mesoglea ───────────────────────────────
  // Chord through the dome L = 2·sqrt(R² − r²); red is absorbed first. What lies behind the
  // bell (water, marine snow) is transmitted by T; the gel in-scatters ambient + its own glow.
  let inBell = smoothstep(0.004, -0.004, dBell);
  let rr = length(bellPScaled);
  let chord = 2.0 * sqrt(max(bellRadius * bellRadius - rr * rr, 0.0));
  let trans = mix(vec3<f32>(1.0), exp(-vec3<f32>(3.3, 1.5, 0.9) * chord * 2.6), inBell);
  let inScatter = vec3<f32>(0.34, 0.48, 0.56) * (0.75 + 0.4 * pulsePhase) + glowCol * 0.25 * pulse * glowIntensity;

  var col = bellColor * trans + inScatter * (vec3<f32>(1.0) - trans);
  col += tentacleColor;
  col += bioGlow;
  col += glowCol * sparkle * trebleSmooth * 3.0;
  col += glowCol * shockwave * 2.0;

  // Inner organs glow: diffuse mesoglea shell centred inside the bell + IDEA 2 anatomy on top
  let innerGlow = glow(dBell + bellRadius * 0.3, 90.0 * glowIntensity) * inBell * pulse * 0.55;
  col += vec3<f32>(0.2, 0.6, 0.8) * innerGlow;
  col += anatomy * glowIntensity * 0.6;

  // IDEA 3: marine snow lit by the jelly (two parallax layers), seen through the mesoglea;
  // Idea 7 stirs it — sampled through the vortex-ring swirl.
  let snow = marine_snow(snowP, time, 9.0, 0.02, 0.0, 0.004, jellyPos, pulse)
           + 0.7 * marine_snow(snowP, time, 15.0, 0.035, 31.0, 0.0028, jellyPos, pulse);
  let snowCol = mix(vec3<f32>(0.75, 0.95, 1.0), glowCol, 0.45);
  col += snowCol * snow * glowIntensity * 0.4 * trans;
  col += vec3<f32>(0.3, 0.75, 1.0) * ringSpark * glowIntensity * 1.6;

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.25;
  col *= vignette;

  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ── Alpha encoding ──────────────────────────────────────────────
  // Coverage = body + tentacles + glow; the water itself is a near-opaque medium.
  let densityAlpha = smoothstep(0.02, -0.02, dBell) * 0.7;
  let tentacleAlpha = smoothstep(0.005, -0.005, dTentacles) * 0.5;
  let glowAlpha = (pulseGlow + tentacleGlow * 0.3 + innerGlow * 0.5 + anatomyLum * 0.5) * 0.4;

  var cov = densityAlpha + tentacleAlpha;
  // Glow reduces density alpha for translucency effect
  cov = mix(cov, glowAlpha, smoothstep(0.0, 0.5, glowAlpha));
  cov += sparkle * trebleSmooth * 0.3;
  cov += shockwave * 0.2;
  cov += snow * 0.1 + ringSpark * 0.3;
  cov = clamp(cov, 0.0, 0.92);
  let alpha = 0.86 + 0.14 * cov / 0.92;

  let outCol = vec4<f32>(acesToneMap(max(col, vec3<f32>(0.0)) * 1.1), alpha);
  textureStore(writeTexture, gid.xy, outCol);
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(pulsePhase, 0.0, 0.0, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(cov, 0.0, 0.0, 0.0));
}
