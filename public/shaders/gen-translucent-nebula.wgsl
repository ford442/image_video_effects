// ═══════════════════════════════════════════════════════════════════
//  Translucent Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba, chromatic-aberration, distance-lod
//  Complexity: High
//  Description: Volumetric gas clouds with density-based alpha
//    translucency. FBM and Worley noise create nebula structure.
//    Dense cores are opaque while edges fade to transparent.
//    Star sparkle reacts to treble; nebula pulses with bass.
//  Upgraded: 2026-10-19
//  Ideas: Rayleigh-Taylor plume fingers; ionization-front shell bands; protostar accretion disks; supernova shockwave bow-shocks;
//         embedded stars light the gas (§12.2F soft inverse-square, blackbody star colours);
//         Rayleigh reflection haze + reddened starlight through the dust (§12.2F Rayleigh)
//  A packing: A.rgb = pre-ACES colour (x/(1+0.3x)), A.a = gas density alpha (history); writeTexture alpha = 0.85 + 0.15 density
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash functions ═══
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
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 0.0)), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), u.x),
      u.y
    ),
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.0, 1.0)), u.x),
      u.y
    ),
    u.z
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

// ═══ CHUNK: Worley noise (cellular) ═══
fn worley3(p: vec3<f32>) -> f32 {
  let n = floor(p);
  var dist1 = 1.0;
  for (var ix = -1; ix <= 1; ix = ix + 1) {
    for (var iy = -1; iy <= 1; iy = iy + 1) {
      for (var iz = -1; iz <= 1; iz = iz + 1) {
        let neighbor = n + vec3<f32>(f32(ix), f32(iy), f32(iz));
        let point = neighbor + hash13(neighbor + vec3<f32>(127.1, 311.7, 74.7));
        let d = length(p - point);
        dist1 = min(dist1, d);
      }
    }
  }
  return dist1;
}

// ═══ CHUNK: nebula density function ═══
fn nebulaDensity(p: vec3<f32>, t: f32, pulse: f32) -> f32 {
  // Large-scale FBM structure
  let large = fbm3(p * 0.8 + vec3<f32>(t * 0.02, t * 0.01, 0.0));
  // Medium detail
  let medium = fbm3(p * 2.0 + vec3<f32>(t * 0.03, -t * 0.02, 1.5));
  // Cellular/Worley for gas pockets
  let cells = worley3(p * 1.5 + vec3<f32>(t * 0.01, t * 0.015, 2.3));
  // Combine: large structure + medium detail * cell boundaries
  var density = large * 0.5 + medium * 0.3 + (1.0 - cells) * 0.4;
  // Idea 1: Rayleigh-Taylor plume fingers rising from dense cores.
  let plume = smoothstep(0.45, 0.82, large) * pow(max(0.5 + 0.5 * sin(p.y * 8.0 - t * 1.7 + p.x * 2.5), 0.0), 3.0);
  density += plume * (0.08 + pulse * 0.12);
  // Idea 2: ionization-front shell bands sweeping through the cloud.
  let shellCoord = abs(fract(length(p) * 1.45 - t * 0.16) - 0.5) * 2.0;
  let ionFront = smoothstep(0.24, 0.02, shellCoord) * smoothstep(0.3, 0.75, density);
  density += ionFront * (0.06 + pulse * 0.1);
  // Audio pulse expands the nebula
  density = density * (0.8 + pulse * 0.4);
  // Sharpen into cloud-like blobs
  density = smoothstep(0.35, 0.7, density);
  return density;
}

// ═══ CHUNK: nebula color palette ═══
fn nebulaColor(density: f32, depth: f32, hueShift: f32) -> vec3<f32> {
  // Core colors
  let coreColor = vec3<f32>(0.9, 0.3, 0.5);   // magenta-pink core
  let midColor = vec3<f32>(0.3, 0.4, 0.9);    // blue midtones
  let edgeColor = vec3<f32>(0.1, 0.8, 0.7);   // teal edges
  let darkColor = vec3<f32>(0.02, 0.03, 0.08);

  // Hue rotation (branchless)
  let hue = fract(density * 0.3 + depth * 0.1 + hueShift);
  let hueCol = hueToRGB(hue);

  var col = mix(darkColor, edgeColor, density * 0.5);
  col = mix(col, midColor, smoothstep(0.3, 0.6, density));
  col = mix(col, coreColor, smoothstep(0.6, 0.9, density));
  col = mix(col, hueCol * 0.7, density * 0.4);
  return col;
}

// ═══ CHUNK: branchless hue-to-RGB (replaces if/else cascade) ═══
fn hueToRGB(hue: f32) -> vec3<f32> {
  let h6 = hue * 6.0;
  let r = clamp(abs(h6 - 3.0) - 1.0, 0.0, 1.0);
  let g = clamp(2.0 - abs(h6 - 2.0), 0.0, 1.0);
  let b = clamp(2.0 - abs(h6 - 4.0), 0.0, 1.0);
  return vec3<f32>(r, g, b);
}

// ═══ CHUNK: star field ═══
fn starField(uv: vec2<f32>, seed: f32, treble: f32) -> vec3<f32> {
  var stars = vec3<f32>(0.0);
  let layers = 3;
  for (var l = 0; l < layers; l = l + 1) {
    let scale = 150.0 + f32(l) * 200.0;
    let starUV = uv * scale + vec2<f32>(seed * f32(l + 1), seed * f32(l + 3));
    let h = hash12(floor(starUV));
    let fracUV = fract(starUV) - 0.5;
    let d = length(fracUV);
    let brightness = step(0.995 - f32(l) * 0.002, h);
    let twinkle = 0.5 + 0.5 * sin(time * (1.0 + h * 3.0) + f32(l));
    let star = brightness * smoothstep(0.5, 0.0, d) * twinkle;
    let starCol = mix(vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(1.0, 0.9, 0.7), h);
    stars = stars + starCol * star * (0.3 + treble * 0.7);
  }
  return stars;
}

// ═══ CHUNK: blackbody star colour (Helland fit, kelvin → linear-ish RGB) ═══
fn starTint(kelvin: f32) -> vec3<f32> {
  let t = kelvin / 100.0;
  let hot = t > 66.0;
  let tw = max(t - 60.0, 1e-3);
  let r = select(1.0, clamp(1.292936 * pow(tw, -0.1332047), 0.0, 1.0), hot);
  let g = select(clamp(0.3900816 * log(max(t, 1.0)) - 0.6318414, 0.0, 1.0),
                 clamp(1.1298909 * pow(tw, -0.0755148), 0.0, 1.0), hot);
  let b = select(clamp(0.5432068 * log(max(t - 10.0, 1.0)) - 1.1962541, 0.0, 1.0), 1.0, t >= 66.0);
  return vec3<f32>(r, g, b);
}

// Rayleigh weights (650/λ)^4 at 650/550/450 nm, normalised to mean 1.
const RAYLEIGH_W = vec3<f32>(0.41, 0.80, 1.79);

// Idea 5: one embedded star's light on a gas sample. Soft inverse-square I/(r² + r₀²);
// hot stars (ionising ≈ 1) turn nearby gas into Hα/Hβ pink emission, the rest of the light
// is dust reflection, Rayleigh-blued (Idea 6). Returns emission rgb.
fn starOnGas(p: vec3<f32>, sp: vec3<f32>, col: vec3<f32>, intensity: f32, ionising: f32) -> vec3<f32> {
  let dv = p - sp;
  let fall = 1.0 / (dot(dv, dv) + 0.012);
  let lk = col * fall;
  let ionFrac = ionising * smoothstep(0.6, 3.0, fall * intensity * 10.0);
  return vec3<f32>(1.0, 0.28, 0.40) * dot(lk, vec3<f32>(0.33)) * ionFrac * 2.0
       + lk * RAYLEIGH_W * (1.0 - ionFrac);
}

// Idea 5/6: the star's own disc — soft inverse-square core + halo, dimmed and reddened by
// the gas in front of it: exp(−τ·w_λ), τ = −ln(transmittance).
fn starDisc(sd: vec2<f32>, tint: vec3<f32>, intensity: f32, trans: f32) -> vec3<f32> {
  let r2 = dot(sd, sd);
  let core = intensity * 0.0009 / (r2 + 0.00004);
  let halo = intensity * 0.06 / (r2 * 40.0 + 0.4);
  let tau = -log(max(trans, 0.02)) * 1.6;
  return tint * (core + halo) * exp(-tau * RAYLEIGH_W);
}

var<private> time: f32;

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
  time = u.config.x;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Parameters
  let densityParam = mix(0.4, 1.2, u.zoom_params.x);
  let cloudScale = mix(0.5, 2.0, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let starDensity = mix(0.3, 1.5, u.zoom_params.w);

  // Mouse: position controls nebula center drift
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let centerOffset = (mousePos - 0.5) * 0.5;

  // Bass for pulsing. HEAD kept an envelope in extraBuffer[1], which is re-uploaded every
  // frame (never persists) and raced across invocations; use the live band directly.
  let smoothBass = bass * 0.5;

  // ── Idea 5: embedded stars. Three stars sit inside the cloud at fixed screen positions
  // and depths (they ride the view; the gas flows past them). Spectral types O / B / K.
  let aspect = res.x / res.y;
  let drift = vec2<f32>(time * 0.01, time * 0.005);
  // Screen position, layer depth (zDepth units), intensity; O 32000 K, B 15000 K, K 4200 K.
  let s0UV = vec2<f32>(0.58, 0.44); let s0Z = 0.45; let s0I = 0.055;
  let s1UV = vec2<f32>(0.26, 0.70); let s1Z = 0.75; let s1I = 0.035;
  let s2UV = vec2<f32>(0.80, 0.24); let s2Z = 0.2;  let s2I = 0.02;
  let s0T = starTint(32000.0);
  let s1T = starTint(15000.0);
  let s2T = starTint(4200.0);
  let starPulse = 1.0 + smoothBass * 0.5;
  let s0P = vec3<f32>((s0UV - 0.5) * cloudScale + centerOffset + drift, s0Z * 2.0);
  let s1P = vec3<f32>((s1UV - 0.5) * cloudScale + centerOffset + drift, s1Z * 2.0);
  let s2P = vec3<f32>((s2UV - 0.5) * cloudScale + centerOffset + drift, s2Z * 2.0);
  var s0Tr = 1.0; var s1Tr = 1.0; var s2Tr = 1.0;

  // Temporal feedback
  let prevState = textureLoad(dataTextureC, coord, 0);

  // ═══ DENSITY RAY-MARCHING APPROXIMATION ═══
  // Sample multiple layers along Z to approximate volumetric density
  var accumDensity = 0.0;
  var accumColor = vec3<f32>(0.0);
  // ═══ CHUNK: distance-based layer LOD (perf) ═══
  // Peripheral pixels (far from screen center) need fewer volumetric
  // samples — the eye resolves less detail there, so we relax from
  // 8 layers at center to 5 toward the edges.
  let distFromCenter = length(uv - vec2<f32>(0.5));
  let layers = i32(mix(8.0, 5.0, smoothstep(0.25, 0.6, distFromCenter)));
  let zStep = 1.0 / f32(layers);

  for (var z = 0; z < layers; z = z + 1) {
    let zDepth = f32(z) * zStep;
    let p = vec3<f32>(
      (uv.x - 0.5) * cloudScale + centerOffset.x + time * 0.01,
      (uv.y - 0.5) * cloudScale + centerOffset.y + time * 0.005,
      zDepth * 2.0
    );

    let d = nebulaDensity(p, time, smoothBass) * densityParam;
    let layerAlpha = d * zStep * 2.5;
    var layerCol = nebulaColor(d, zDepth, colorShift);

    // ── Idea 5: soft inverse-square starlight, I/(r² + r₀²), received by this layer's gas.
    // Close to the hot O/B stars the gas is ionised and glows Hα/Hβ pink; further out the
    // dust only scatters, and ── Idea 6: Rayleigh scattering (λ⁻⁴) makes that reflection
    // light blue — the red-core / blue-halo split of a real star-forming region.
    let starGas = starOnGas(p, s0P, s0T * s0I * starPulse, s0I, 1.0)
                + starOnGas(p, s1P, s1T * s1I * starPulse, s1I, 0.6)
                + starOnGas(p, s2P, s2T * s2I * starPulse, s2I, 0.0);
    layerCol += starGas * (0.3 + 0.6 * d);
    // transmittance of the gas in front of each star (before this layer composites)
    s0Tr = select(s0Tr, 1.0 - accumDensity, zDepth <= s0Z);
    s1Tr = select(s1Tr, 1.0 - accumDensity, zDepth <= s1Z);
    s2Tr = select(s2Tr, 1.0 - accumDensity, zDepth <= s2Z);
    let plumeTint = smoothstep(0.55, 0.9, d) * pow(max(0.5 + 0.5 * sin(p.y * 7.5 - time * 1.3), 0.0), 2.0);
    let ionBand = smoothstep(0.2, 0.04, abs(fract(length(p) * 1.5 - time * 0.17) - 0.5) * 2.0);
    layerCol += vec3<f32>(0.35, 0.95, 0.75) * ionBand * 0.18;
    layerCol += vec3<f32>(0.95, 0.55, 0.35) * plumeTint * 0.12;

    // Front-to-back compositing
    accumColor = accumColor + layerCol * layerAlpha * (1.0 - accumDensity);
    accumDensity = accumDensity + layerAlpha * (1.0 - accumDensity);

    if (accumDensity >= 0.99) { break; }
  }

  accumDensity = clamp(accumDensity, 0.0, 1.0);

  // ═══ MOUSE GAS CONCENTRATIONS (via ripples) ═══
  var gasBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rAge = time - ripple.z;
    if (rAge < 0.0 || rAge > 4.0) { continue; }
    let rDist = length(uv - ripple.xy);
    let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-rAge * 0.8);
    gasBoost = gasBoost + rInfluence;
  }

  // Add gas concentration from mouse clicks
  let gasColor = vec3<f32>(0.6, 0.2, 0.8) * gasBoost;
  accumColor = accumColor + gasColor * (1.0 - accumDensity);
  accumDensity = clamp(accumDensity + gasBoost * 0.3, 0.0, 1.0);

  // ═══ STAR FIELD ═══
  // ── Idea 6: background stars are extinguished per channel through the gas column:
  // gray optical depth τ = −ln(T), reddened by the Rayleigh weights.
  let tauBg = -log(max(1.0 - accumDensity * 0.85, 0.02));
  let stars = starField(uv, 42.0, treble) * starDensity;
  accumColor = accumColor + stars * exp(-tauBg * RAYLEIGH_W);

  // ── Idea 5/6: the embedded stars themselves — soft inverse-square core + halo, seen
  // through the gas in front of them, which dims and reddens them (exp(−τ·w_λ)).
  let ar = vec2<f32>(aspect, 1.0);
  accumColor += (starDisc((uv - s0UV) * ar, s0T, s0I, s0Tr)
              + starDisc((uv - s1UV) * ar, s1T, s1I, s1Tr)
              + starDisc((uv - s2UV) * ar, s2T, s2I, s2Tr)) * (1.0 + smoothBass * 0.6);

  // Idea 1: protostar accretion disks — inclined disks with a lit centre, only where the
  // gas is dense enough to collapse (HEAD stamped screen-grid ring outlines over the void).
  let protoUV = uv * 30.0 + vec2<f32>(time * 0.1);
  let protoHash = hash12(floor(protoUV));
  let pf = fract(protoUV) - 0.5;
  let pa = protoHash * 40.0;
  let pr = vec2<f32>(pf.x * cos(pa) - pf.y * sin(pa), (pf.x * sin(pa) + pf.y * cos(pa)) * 2.6);
  let protoDist = length(pr);
  let protoRing = smoothstep(0.18, 0.28, protoDist) * smoothstep(0.42, 0.3, protoDist) + smoothstep(0.12, 0.0, length(pf)) * 0.8;
  let protoGate = smoothstep(0.35, 0.75, accumDensity);
  let protoStar = step(0.97, protoHash) * protoRing * protoGate * (0.6 + 0.4 * sin(time * 5.0 + protoHash * 10.0));
  accumColor += vec3<f32>(1.0, 0.5, 0.2) * protoStar * 1.4;
  
  // Idea 2: supernova shockwave bow-shocks (fast sweeping arc)
  let shockDist = length(uv - 0.5);
  let shockRadius = fract(time * 0.2) * 2.0;
  let bowShock = exp(-abs(shockDist - shockRadius) * 50.0) * smoothstep(0.8, 1.0, sin(atan2(uv.y - 0.5, uv.x - 0.5) + time));
  accumColor += vec3<f32>(0.2, 0.6, 1.0) * bowShock * (1.0 + bass);

  // ═══ AUDIO-REACTIVE SPARKLE ═══
  let sparkleNoise = hash12(uv * 1000.0 + time * 10.0);
  let sparkleThreshold = 0.997 - treble * 0.003;
  let sparkle = step(sparkleThreshold, sparkleNoise);
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.9) * sparkle * treble * 2.0;
  accumColor = accumColor + sparkleColor * (1.0 - accumDensity * 0.5);

  // Temporal smoothing for nebula motion
  let persistence = 0.12;
  let prevColor = prevState.rgb;
  var finalColor = mix(accumColor, prevColor, persistence);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.5));

  // Soft tone mapping
  finalColor = finalColor / (1.0 + finalColor * 0.3);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha encodes gas density: dense cores opaque, edges transparent
  // Also modulated by audio for breathing effect
  let breath = 1.0 + smoothBass * 0.15 + rms * 0.1;
  let finalAlpha = clamp(accumDensity * breath * 0.9 + prevState.a * 0.05, 0.0, 1.0);

  // Depth for chromatic + pass-through
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Store state for temporal feedback
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));

  finalColor = acesToneMap(finalColor * 1.1);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + smoothBass) + depthVal * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  // Display alpha: floor 0.85 so thin gas doesn't composite the page through as a wash;
  // the density semantics stay in A.a.
  textureStore(writeTexture, coord, vec4<f32>(finalColor, mix(0.85, 1.0, finalAlpha)));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
