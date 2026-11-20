// ═══════════════════════════════════════════════════════════════════
//  distortion-gravitational-prismatic — Gravitational Lensing & Cauchy Dispersion
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            gravitational-lensing, spectral-dispersion, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-20
//  Ideas: dense energy-normalised Cauchy spectrum (7 bands, per-channel weights; §12.2F Cauchy dispersion); spectral Einstein ring (per-band ring radius from deflectScale)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=LensStrength, y=MassCount, z=DiskIntensity, w=CauchyDispersion

const PI: f32 = 3.14159265359;

struct Mass {
  pos: vec2<f32>,
  mass: f32,
  radius: f32,
};

fn deflectionAngle(rayPos: vec2<f32>, mass: Mass) -> vec2<f32> {
  let delta = rayPos - mass.pos;
  let dist2 = dot(delta, delta);
  let dist = sqrt(dist2);
  if (dist < mass.radius * 0.1) {
    return vec2<f32>(0.0);
  }
  let deflectionMagnitude = mass.mass * mass.radius / (dist + 0.001);
  return -normalize(delta) * deflectionMagnitude;
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn accretionDiskColor(radius: f32, innerRadius: f32) -> vec3<f32> {
  let temp = pow(innerRadius / radius, 0.75);
  var color: vec3<f32>;
  if (temp > 0.8) {
    color = vec3<f32>(1.0, 0.9, 0.8);
  } else if (temp > 0.6) {
    color = vec3<f32>(1.0, 0.6, 0.3);
  } else if (temp > 0.4) {
    color = vec3<f32>(0.8, 0.2, 0.1);
  } else {
    color = vec3<f32>(0.3, 0.05, 0.05);
  }
  return color * temp * temp;
}

fn einsteinRadius(mass: f32, distance: f32) -> f32 {
  return sqrt(mass) * distance * 0.1;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, isMouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let lensStrength = (0.5 + u.zoom_params.x) * (1.0 + bass * 0.3);
  let numMasses = i32(u.zoom_params.y * 4.0) + 1;
  let diskIntensity = u.zoom_params.z * (1.0 + mids * 0.25);
  let cauchyB = mix(0.01, 0.08, u.zoom_params.w) * (1.0 + treble * 0.35);

  var masses: array<Mass, 5>;
  masses[0] = Mass(mouse, 2.0 + held * 1.5, 0.02 * lensStrength);
  for (var i: i32 = 1; i < 5; i = i + 1) {
    if (i < numMasses) {
      let fi = f32(i);
      let angle = time * 0.2 + fi * (2.0 * PI / f32(numMasses - 1));
      let radius = 0.2 + fi * 0.1;
      masses[i] = Mass(
        vec2<f32>(mouse.x + cos(angle) * radius, mouse.y + sin(angle) * radius),
        0.5,
        0.01 * lensStrength
      );
    }
  }

  var rayPos = uv;
  var totalDeflection = vec2<f32>(0.0);
  for (var i: i32 = 0; i < numMasses; i = i + 1) {
    totalDeflection += deflectionAngle(rayPos, masses[i]);
  }

  // Click ripples create extra deflection waves
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let delta = uv - r.xy;
      let rDist = length(delta * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 30.0) * exp(-rDist * 5.0) * exp(-age * 1.5);
      totalDeflection += normalize(delta + vec2<f32>(1e-5)) * wave * 0.04;
    }
  }

  // Primary-mass geometry (hoisted: the spectral ring below needs it per band)
  let toPrimary = uv - masses[0].pos;
  let distPrimary = length(toPrimary * vec2<f32>(aspect, 1.0));
  // Rescue: HEAD passed `distPrimary` as the lens-plane distance, so
  // |dist − 0.14·dist| < 0.02 held only inside dist ≈ 0.025 — the "Einstein
  // ring" was a dot on the mass. θE of this file's own deflection law is
  // sqrt(½·mass·radius) = 0.1·sqrt(mass·lensStrength): pass sqrt(lensStrength).
  let einsteinR = einsteinRadius(masses[0].mass, sqrt(lensStrength));

  // ── Idea 1: dense, energy-normalised Cauchy spectrum (§12.2F) ───────────
  // HEAD sampled four wavelengths (450/520/600/680, kept) and summed
  // wl·dot(sample, wl) without normalising: a neutral source came out ×3 red
  // (flat 0.6 grey → sRGB 229,182,178) and strong dispersion showed four
  // coloured ghost copies. Three interleaved bands (485/560/640) smooth the
  // ghosts into a continuous spectrum, and each channel is now the
  // band-tint-weighted mean of its own samples (weights sum to 1 per channel),
  // so white stays white and zero dispersion reproduces the plain lens image.
  let WAVELENGTHS = array<f32, 7>(450.0, 485.0, 520.0, 560.0, 600.0, 640.0, 680.0);
  var finalColor = vec3<f32>(0.0);
  var weightSum = vec3<f32>(0.0);
  var ringAcc = vec3<f32>(0.0);
  let ringHue = 550.0 + sin(time * 2.0) * 100.0;   // HEAD's time-cycled ring hue, now a band emphasis

  for (var w: i32 = 0; w < 7; w = w + 1) {
    let lam = WAVELENGTHS[w];
    let wl = wavelengthToRGB(lam);
    let ior = cauchyIOR(lam, 1.5, cauchyB);
    let deflectScale = 1.0 + (ior - 1.5) * 2.0;
    let sourcePos = clamp(rayPos - totalDeflection * 0.5 * deflectScale, vec2<f32>(0.001), vec2<f32>(0.999));
    let sample = textureSampleLevel(readTexture, u_sampler, sourcePos, 0.0);
    finalColor += wl * sample.rgb;
    weightSum += wl;

    // ── Idea 2: spectral Einstein ring (§12.2F) ──────────────────────────
    // θE² ∝ deflection, and deflectScale is this band's deflection factor, so
    // the band's ring sits at θE·sqrt(deflectScale): blue outside, red inside —
    // a rainbow annulus instead of one ring in one colour.
    let ringBand = smoothstep(0.014, 0.0, abs(distPrimary - einsteinR * sqrt(deflectScale)));
    let hueD = (lam - ringHue) / 90.0;
    ringAcc += wl * (ringBand * (0.4 + 0.6 * exp(-hueD * hueD)));
  }
  finalColor = finalColor / max(weightSum, vec3<f32>(1e-3));
  let ringSpectrum = ringAcc / max(weightSum, vec3<f32>(1e-3));

  // Accretion disk
  let innerDisk = masses[0].radius * 3.0;
  let outerDisk = masses[0].radius * 15.0;
  if (distPrimary > innerDisk && distPrimary < outerDisk) {
    let diskTemp = accretionDiskColor(distPrimary, innerDisk);
    let diskPattern = sin(atan2(toPrimary.y, toPrimary.x) * 20.0 + time * 2.0);
    let diskGlow = smoothstep(outerDisk, innerDisk, distPrimary) * (0.7 + diskPattern * 0.3);
    let diskColor = diskTemp * diskGlow * diskIntensity * (1.0 + bass * 0.4);
    finalColor += diskColor;
  }

  // Einstein ring (spectral — accumulated per band above)
  let ringGlow = clamp(dot(ringSpectrum, vec3<f32>(0.3333)) * 3.0, 0.0, 1.0) * lensStrength;
  finalColor += ringSpectrum * (1.3 * lensStrength);

  // Gravitational redshift
  let redshift = smoothstep(masses[0].radius * 10.0, masses[0].radius, distPrimary);
  finalColor = vec3<f32>(finalColor.r * (1.0 + redshift * 0.3), finalColor.g, finalColor.b * max(1.0 - redshift * 0.2, 0.0));

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, coord, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08);

  let finalRGB = aces(finalColor);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.35 + length(totalDeflection) * 12.0 + ringGlow * 0.3 + held * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
