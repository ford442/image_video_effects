// ═══ Supernova Core — Advanced Alpha Compositor Upgrade ═══
// Category: generative
// Features: generative, audio-reactive, sedov-taylor, rayleigh-taylor,
//   radioactive-decay, chromatic-aberration, upgraded-rgba,
//   blackbody-cooling, volumetric-fog, ign-dither, alpha-layered,
//   physical-transmittance, luminance-key, depth-layered,
//   spectrum-rays, click-sedov-rings, spring-companion
// Upgraded: 2026-10-19
// Ideas: dust light echoes beyond the shock; companion shadow cone carved in the
//   ejecta; inward reverse shock that ignites the RT fingers it crosses
// A packing: premultiplied ACES display RGBA (C unused)

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = pow(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 1.0 / 3.0);
  let m = pow(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 1.0 / 3.0);
  let s = pow(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 1.0 / 3.0);
  return vec3<f32>(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
  return vec3<f32>(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  return c * min(1.0, max_lum / max(dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)), 1e-4));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// Advanced alpha compositor helpers
fn luminanceKey(color: vec3<f32>, low: f32, high: f32) -> f32 {
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  return smoothstep(low, high, luma);
}

fn beerLambertAlpha(density: f32, thickness: f32) -> f32 {
  return 1.0 - exp(-density * thickness);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = vec2<f32>(pixel) / res; let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // ── Slider wiring (saved-preset contract: zoom_params.x/y/z/w) ──
  let expansion = u.zoom_params.x;                    // blast + ray reach scale
  let rayCount = 6 + i32(u.zoom_params.y * 18.0);     // spectrum ray count 6..24
  let shockwaves = u.zoom_params.z;                   // Sedov rate (main + click rings)
  let chromatic = u.zoom_params.w;                    // prism split on rays

  let aspect = res.x / res.y;
  let p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0); let dist = length(p); let angle = atan2(p.y, p.x);

  // ── Spring-damper companion star (persistent state) ─────────────
  // extraBuffer[133..134] = eased companion-star position (world space).
  // Position-only critically damped step (zeta = 1) so fast mouse moves
  // relax the ejecta asymmetry and rim light instead of snapping them.
  // Only invocation (0,0) integrates; every pixel reads the eased value.
  let mouseWorldRaw = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  var companion = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  if (global_id.x == 0u && global_id.y == 0u) {
    if (time < 0.1) {
      companion = mouseWorldRaw; // cold start: snap to avoid a startup swoop
    } else {
      let springK = 1.0 - exp(-(1.0 / 60.0) * 9.0);
      companion = mix(companion, mouseWorldRaw, springK);
    }
    extraBuffer[133] = companion.x;
    extraBuffer[134] = companion.y;
  }
  let mouseWorld = companion;
  let asymmetry = 1.0 + smoothstep(0.15, 0.0, length(p - mouseWorld)) * 0.6;

  // Sedov-Taylor main blast: r ~ t^0.4, driven by shockwaves + bass.
  let blastRadius = pow(time * 0.12 * (1.0 + shockwaves) * (1.0 + bass), 0.4) * 0.5 * (1.0 + expansion);

  // Radioactive decay luminosity: 56Ni -> 56Co -> 56Fe.
  let decayTime = fract(time * 0.08);
  let nickelMass = 1.0 - decayTime * 0.7;
  let cobaltLum = sin(decayTime * TAU) * 0.5 + 0.5;
  let flareTrigger = step(1.0 - treble * 0.15, hash21(vec2<f32>(floor(time * 5.0), 0.0))) * cobaltLum;

  // [idea 2] Companion shadow cone: the companion star blocks ejecta behind it
  // (as seen from the core), carving a widening conical hole downstream.
  let compLen = max(length(mouseWorld), 1e-3);
  let coneAxis = mouseWorld / compLen;
  let alongC = dot(p, coneAxis);
  let perpC = length(p - coneAxis * alongC);
  let coneHalf = 0.012 + max(alongC - compLen, 0.0) * 0.32;
  let shadowCone = smoothstep(coneHalf, coneHalf * 0.4, perpC) * smoothstep(compLen - 0.01, compLen + 0.03, alongC)
                 * smoothstep(0.02, 0.06, compLen);
  let ejectaPass = 1.0 - shadowCone * 0.85;

  var hdr = vec3<f32>(0.0);
  var ejectaDensity = 0.0;
  var shockTemp = 0.0;

  // ── Nickel core ─────────────────────────────────────────────────
  let coreTemp = 30000.0 * nickelMass * (1.0 + bass * 0.5);
  let core = smoothstep(0.025 * asymmetry, 0.0, dist) * (1.0 + flareTrigger * 2.0);
  hdr += blackbodyRGB(coreTemp) * 2.5 * core;
  shockTemp += core * coreTemp;
  ejectaDensity += core;

  // ── Cooling shock shells ────────────────────────────────────────
  for (var wi = 0; wi < 4; wi++) {
    let wf = f32(wi);
    let waveRadius = blastRadius * (0.25 + wf * 0.25);
    let waveWidth = 0.006 * (1.0 + treble * 0.5) * asymmetry;
    let wave = smoothstep(waveRadius + waveWidth, waveRadius, dist) * smoothstep(waveRadius - waveWidth, waveRadius, dist);
    let cooling = 1.0 - wf / 4.0 - dist * 0.8;
    let tempK = mix(15000.0, 2500.0, smoothstep(0.0, 1.0, cooling));
    let shell = mixOkLab(blackbodyRGB(tempK), blackbodyRGB(tempK * 0.6), wf / 4.0) * (1.2 + mids * 0.8);
    hdr += shell * wave * ejectaPass;
    shockTemp += wave * coreTemp * (1.0 - wf * 0.2) * ejectaPass;
    ejectaDensity += wave * 0.3 * ejectaPass;
  }

  // ── Rayleigh-Taylor instability fingers (iron emission) ─────────
  let rtCoord = vec2<f32>(angle * 3.0, dist * 8.0 - time * 0.5);
  let rtFingers = smoothstep(0.45, 0.65, fbm(rtCoord * vec2<f32>(1.0, 2.0 + mids * 2.0), 3)) * smoothstep(blastRadius + 0.05, blastRadius - 0.05, dist);
  let ironColor = mixOkLab(vec3<f32>(0.55, 0.75, 0.85), vec3<f32>(0.25, 0.45, 0.65), mids);
  hdr += ironColor * rtFingers * mids * 1.5 * ejectaPass;
  ejectaDensity += rtFingers * 0.2 * ejectaPass;

  // [idea 3] Reverse shock: a shell that sweeps inward through the ejecta each
  // cycle; where it crosses an RT finger the iron reheats to a hot white-blue.
  let rsPhase = fract(time * 0.07 * (1.0 + shockwaves));
  let rsRadius = blastRadius * mix(0.85, 0.2, rsPhase);
  let rsRing = exp(-pow((dist - rsRadius) * 70.0, 2.0)) * (1.0 - rsPhase) * ejectaPass;
  hdr += blackbodyRGB(mix(9000.0, 4000.0, rsPhase)) * rsRing * (0.25 + rtFingers * 2.2) * (1.0 + mids * 0.5);
  shockTemp += rsRing * coreTemp * 0.3;
  ejectaDensity += rsRing * 0.15;

  // [idea 1] Light echoes: flash light scattered by interstellar dust sheets
  // outside the shock, racing ahead of it; dust fbm makes the rings patchy.
  for (var ei = 0; ei < 3; ei++) {
    let ef = f32(ei);
    let echoR = blastRadius * (1.35 + ef * 0.5) + fract(time * 0.03 + ef * 0.33) * 0.06;
    let echoRing = exp(-pow((dist - echoR) * 85.0, 2.0));
    let dust = smoothstep(0.4, 0.75, fbm(p * 5.5 + vec2<f32>(ef * 3.1, ef * 1.7), 3));
    hdr += blackbodyRGB(mix(9000.0, 5000.0, ef / 2.0)) * echoRing * dust * (0.4 - ef * 0.1) * (1.0 + bass * 0.4);
    ejectaDensity += echoRing * dust * 0.05;
  }

  // ── Neutrino-driven convection cells ────────────────────────────
  let cellMask = smoothstep(0.08, 0.0, abs(dist - blastRadius * 0.6)) * fbm(p * 6.0 + vec2<f32>(cos(time * 0.3), sin(time * 0.25)) * 0.5, 3) * fbm(p * 13.8 + vec2<f32>(10.0, 20.0), 2);
  hdr += vec3<f32>(0.45, 0.25, 0.65) * cellMask * 0.45 * ejectaPass;

  // ── Companion-star rim light (uses eased spring position) ───────
  let toCompanion = normalize(mouseWorld - p + vec2<f32>(0.001));
  let normal = normalize(p + vec2<f32>(0.001));
  let rim = pow(max(0.0, 1.0 + dot(normal, toCompanion)), 3.0) * smoothstep(blastRadius + 0.04, blastRadius - 0.04, dist) * (1.0 + treble);
  hdr += blackbodyRGB(6500.0) * rim * 0.9;

  // ── Spectrum-driven rays ────────────────────────────────────────
  // Ray i reads FFT bin (i % 8) + 1 so the light echo decomposes into
  // the audio spectrum; the per-ray hash shimmer stays as the floor.
  for (var ri = 0; ri < rayCount; ri++) {
    let rf = f32(ri);
    let rayAngle = rf / f32(rayCount) * TAU + hash21(vec2<f32>(rf, 0.0)) * 0.35;
    let angleDiff = abs(fract((angle - rayAngle) / TAU + 0.5) - 0.5) * TAU;
    let rayWidth = 0.015 + hash21(vec2<f32>(rf, 1.0)) * 0.035;
    let binVal = plasmaBuffer[u32(ri % 8) + 1u].x;
    let shimmer = 0.3 + hash21(vec2<f32>(rf, time)) * 0.7;
    let spectral = 0.45 + binVal * 1.4;
    let ray = smoothstep(rayWidth, 0.0, angleDiff) * smoothstep(0.35 * (1.0 + expansion) * asymmetry, 0.0, dist) * shimmer * spectral;
    let cs = chromatic * 0.025 * dist * (1.0 + treble);
    let rayR = smoothstep(rayWidth * 1.3, 0.0, angleDiff + cs) * ray;
    let rayB = smoothstep(rayWidth * 1.3, 0.0, angleDiff - cs) * ray;
    let h = abs(fract(vec3<f32>(fract(rf / f32(rayCount) + bass * 0.12 + decayTime * 0.2)) + vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - vec3<f32>(3.0));
    hdr += clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * vec3<f32>(rayR, ray, rayB) * (1.0 + treble * 0.5);
    ejectaDensity += ray * 0.08;
  }

  // ── Click Sedov rings ───────────────────────────────────────────
  // Each click spawns a secondary blast wave whose radius follows the
  // Sedov-Taylor self-similar solution (r ~ t^0.4), cooling and fading
  // with age. Shockwave Speed slider scales their expansion rate.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ci: u32 = 0u; ci < rippleCount; ci = ci + 1u) {
    let click = u.ripples[ci];
    let clickAge = time - click.z;
    if (clickAge > 0.0 && clickAge < 6.0) {
      let clickWorld = (click.xy - 0.5) * vec2<f32>(aspect, 1.0);
      let clickDist = length(p - clickWorld);
      let ringRadius = pow(clickAge * 0.30 * (1.0 + shockwaves * 0.8), 0.4) * 0.6;
      let ringWidth = 0.008 + clickAge * 0.004;
      let ring = smoothstep(ringRadius + ringWidth, ringRadius, clickDist) * smoothstep(ringRadius - ringWidth, ringRadius, clickDist);
      let ringDecay = exp(-clickAge * 1.1);
      let ringTemp = mix(12000.0, 2800.0, clamp(clickAge / 5.0, 0.0, 1.0));
      hdr += blackbodyRGB(ringTemp) * ring * ringDecay * (1.0 + mids * 0.6);
      shockTemp += ring * ringTemp * ringDecay;
      ejectaDensity += ring * ringDecay * 0.35;
    }
  }

  // ── Cobalt flare + bass shock glint ─────────────────────────────
  hdr += blackbodyRGB(8000.0) * flareTrigger * core * 1.2;
  shockTemp += flareTrigger * coreTemp * 0.5;
  hdr += vec3<f32>(0.5, 0.55, 0.65) * smoothstep(0.02, 0.0, abs(dist - blastRadius)) * bass * 0.8;

  // ── Volumetric ejecta fog + depth light-echo tint ───────────────
  let fogDensity = ejectaDensity * 2.5;
  let fogAtten = exp(-fogDensity * dist * (1.0 + depth));
  let fogColor = mixOkLab(blackbodyRGB(4000.0), blackbodyRGB(12000.0), nickelMass);
  hdr = hdr * fogAtten + fogColor * (1.0 - fogAtten) * 0.4;
  hdr += vec3<f32>(0.25, 0.20, 0.35) * smoothstep(0.0, 0.5, depth) * 0.2 * (1.0 + bass * 0.2);

  hdr = hue_preserve_clamp(hdr, 8.0);
  let mapped = acesToneMap(hdr * 1.5); let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);
  let tempNorm = clamp(shockTemp / 30000.0, 0.0, 1.0);

  // ── Advanced Alpha Composition ─────────────────────────────────
  // 1. Luminance key: dark outer ejecta becomes transparent.
  let lumaAlpha = luminanceKey(color, 0.04, 0.32);
  // 2. Depth-layered: far depth planes reduce opacity for parallax light echoes.
  let depthAlpha = mix(0.22, 1.0, depth);
  // 3. Physical transmittance: denser ejecta blocks more background light.
  let physicalAlpha = beerLambertAlpha(ejectaDensity * (1.0 + tempNorm * 0.5), 1.6 * dist);
  // 4. Edge preserve: retain opacity at sharp shock fronts and ray boundaries.
  let edgeAlpha = smoothstep(0.0, 0.06, ejectaDensity + tempNorm * 0.25);
  // Blend modes: luma key + depth layered, then reinforced by physical density.
  var alpha = mix(lumaAlpha, depthAlpha, 0.3);
  alpha = mix(alpha, physicalAlpha, 0.45);
  alpha = alpha * edgeAlpha;
  alpha = clamp(alpha, 0.0, 1.0);
  // Pre-multiplied RGB for correct compositing in the 3-slot chain.
  let finalColor = color * alpha;

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(ejectaDensity * 0.5 + tempNorm * 0.3, 0.0, 0.0, 0.0));
}
