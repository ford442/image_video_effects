// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, psychedelic, procedural, temporal, chromatic, depth-aware
//  Complexity: High
//  Upgraded: 2026-07-13
// ═══════════════════════════════════════════════════════════════════
//  Simulates a multi-slit diffraction grating with separate red/green/blue
//  wavelength interference. Six-fold rotational symmetry produces a vivid
//  spectral starburst. This upgraded version adds ACES tone mapping with HDR
//  headroom, volumetric light cones along each slit axis, Fresnel glints at
//  bright fringe overlaps, dynamic color-temperature shifts driven by audio
//  bands, a radial bloom/glow approximation, and spectral-to-sRGB mixing
//  derived from dominant wavelength peaks rather than naive channel offsets.

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
const SPECTRAL_STEPS: i32 = 7;

// ── Color helpers ─────────────────────────────────────────────────

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Approximate CIE 1931 XYZ response for a dominant wavelength (nm).
fn wavelengthToXyz(lambda_nm: f32) -> vec3<f32> {
  let t = (lambda_nm - 450.0) / 320.0;
  let x = 1.065 * exp(-0.5 * pow((lambda_nm - 595.8) / 33.33, 2.0))
        + 0.366 * exp(-0.5 * pow((lambda_nm - 446.8) / 19.44, 2.0));
  let y = 1.0 * exp(-0.5 * pow((lambda_nm - 555.0) / 40.0, 2.0));
  let z = 1.781 * exp(-0.5 * pow((lambda_nm - 449.8) / 23.01, 2.0));
  return vec3<f32>(x, y, z);
}

// Simplified sRGB matrix from CIE XYZ (D65) for the visible range.
fn xyzToRgb(xyz: vec3<f32>) -> vec3<f32> {
  let m = mat3x3<f32>(
     3.2404542, -0.9692660,  0.0556434,
    -1.5371385,  1.8760108, -0.2040259,
    -0.4985314,  0.0415560,  1.0572252
  );
  return xyz * m;
}

// Build an RGB triplet from a peak wavelength. The result is unbounded to
// preserve HDR headroom before tone mapping.
fn spectralPeakToRgb(lambda_nm: f32) -> vec3<f32> {
  let rgb = xyzToRgb(wavelengthToXyz(lambda_nm));
  return max(rgb, vec3<f32>(0.0));
}

// ── ACES Filmic tone mapping (simplified fit) ─────────────────────

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Geometry helpers ──────────────────────────────────────────────

fn applySymmetry(q: vec2<f32>, k: i32) -> vec2<f32> {
  let sectors = f32(k);
  let angle   = atan2(q.y, q.x);
  let r       = length(q);
  let secAngle = TAU / sectors;
  let sector   = floor(angle / secAngle);
  let localA   = angle - sector * secAngle;
  // Mirror alternate sectors for kaleidoscopic closure.
  let foldA = select(localA, secAngle - localA, localA > secAngle * 0.5);
  return vec2<f32>(cos(foldA), sin(foldA)) * r;
}

// Diffraction from a single virtual slit.
fn slitIntensity(p: vec2<f32>, slitPos: f32, axisDir: vec2<f32>, freq: f32, phase: f32, lambda: f32) -> f32 {
  let proj   = dot(p, axisDir) - slitPos;
  let wave   = 0.5 + 0.5 * cos(proj * freq * TAU + phase);
  // Sinc-like envelope perpendicular to the slit axis.
  let dist   = abs(dot(p, vec2<f32>(-axisDir.y, axisDir.x)));
  let envArg = dist * freq * 0.5 * lambda;
  let sinc   = select(1.0, sin(envArg) / envArg, abs(envArg) > 0.001);
  return wave * sinc * sinc;
}

// Volumetric light cone: soft Mie-like glow along the slit axis.
fn volumetricCone(p: vec2<f32>, axisDir: vec2<f32>, intensity: f32, thickness: f32) -> f32 {
  let along = dot(p, axisDir);
  let across = abs(dot(p, vec2<f32>(-axisDir.y, axisDir.x)));
  let radialFalloff = exp(-across * 8.0 / thickness);
  let axialFalloff  = exp(-abs(along) * 1.5);
  return intensity * radialFalloff * axialFalloff;
}

// Fresnel-like glint where fringes are brightest.
fn fresnelGlint(p: vec2<f32>, n: vec2<f32>, strength: f32) -> f32 {
  let viewDir = normalize(-p);
  let ndotv = max(dot(n, viewDir), 0.0);
  return pow(1.0 - ndotv, 3.0) * strength;
}

// ── Main kernel ───────────────────────────────────────────────────

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
  let volume = plasmaBuffer[0].w;

  // Parameters from JSON: speed, frequency, chromatic spread, brightness.
  let speed      = mix(0.2,  2.5, u.zoom_params.x);
  let freq       = mix(4.0, 24.0, u.zoom_params.y);
  let chromAb    = mix(0.8,  2.4, u.zoom_params.z);
  let brightness = mix(0.6,  2.2, u.zoom_params.w);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = applySymmetry(p, SYMMETRY);

  // Spectral peaks for RGB channels, centred in the visible spectrum.
  let lambdaR = mix(620.0, 700.0, 0.5 + (bass - 0.5) * 0.1);
  let lambdaG = mix(520.0, 560.0, 0.5 + (mids  - 0.5) * 0.1);
  let lambdaB = mix(440.0, 490.0, 0.5 + (treble - 0.5) * 0.1);

  let baseSpectral = 0.55 * chromAb;
  let rSpectrum = spectralPeakToRgb(lambdaR) * baseSpectral;
  let gSpectrum = spectralPeakToRgb(lambdaG) * baseSpectral;
  let bSpectrum = spectralPeakToRgb(lambdaB) * baseSpectral;

  // Audio-modulated chromatic offsets.
  let chromOffsetR = vec2<f32>(bass * 0.025, 0.0);
  let chromOffsetG = vec2<f32>(0.0, mids * 0.025);
  let chromOffsetB = vec2<f32>(-treble * 0.025, treble * 0.025);

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  var volumetric = vec3<f32>(0.0);

  for (var si: i32 = 0; si < SLITS; si = si + 1) {
    let sf = f32(si);
    let slitAngle = sf / f32(SLITS) * TAU + time * speed * 0.05;
    let axis = vec2<f32>(cos(slitAngle), sin(slitAngle));
    let slitPos = (sf - f32(SLITS) * 0.5) * 0.18;
    let phase = time * speed * (0.6 + sf * 0.23) + bass * TAU * 0.4;

    // Diffraction fringes.
    let iR = slitIntensity(p + chromOffsetR, slitPos, axis, freq, phase, lambdaR * 0.01);
    let iG = slitIntensity(p + chromOffsetG, slitPos, axis, freq, phase + 0.3, lambdaG * 0.01);
    let iB = slitIntensity(p + chromOffsetB, slitPos, axis, freq, phase + 0.6, lambdaB * 0.01);

    r = r + iR;
    g = g + iG;
    b = b + iB;

    // Light cones along each slit axis, pulsing with bass.
    let cone = volumetricCone(p, axis, 0.35 + bass * 0.35, 0.6 + mids * 0.5);
    let coneColor = spectralPeakToRgb(mix(lambdaR, lambdaB, sf / f32(SLITS)));
    volumetric = volumetric + cone * coneColor * (0.6 + treble * 0.8);
  }

  // Map fringe amplitudes through spectral peak tints.
  let norm = 1.0 / max(f32(SLITS) * 0.55, 1.0);
  var color = vec3<f32>(r, g, b) * norm * brightness * (1.0 + mids * 0.5);
  color = color * mat3x3<f32>(
    rSpectrum.x, gSpectrum.x, bSpectrum.x,
    rSpectrum.y, gSpectrum.y, bSpectrum.y,
    rSpectrum.z, gSpectrum.z, bSpectrum.z
  );

  // Add volumetric cones (unbounded for HDR).
  color = color + volumetric * norm * brightness;

  // Dynamic color temperature: warm when bass dominates, cool when treble dominates.
  let tempBalance = clamp((treble - bass) * 0.5 + 0.5, 0.0, 1.0);
  let warmK = vec3<f32>(1.12, 0.96, 0.78);
  let coolK = vec3<f32>(0.78, 0.94, 1.12);
  color = color * mix(warmK, coolK, tempBalance);

  // Fresnel glint at bright overlap regions.
  let fringeMask = smoothstep(0.3, 0.9, color.r + color.g + color.b);
  let glint = fresnelGlint(p, normalize(p + 0.001), 0.35 + volume * 0.5);
  color = color + vec3<f32>(glint * fringeMask * (1.0 + treble));

  // Bloom / glow approximation: small radial blur on bright fringes.
  var bloom = vec3<f32>(0.0);
  let bloomSamples = 8;
  let bloomRadius = 0.012 + mids * 0.008;
  for (var bi: i32 = 0; bi < bloomSamples; bi = bi + 1) {
    let bf = f32(bi);
    let ba = bf / f32(bloomSamples) * TAU;
    let bo = vec2<f32>(cos(ba), sin(ba)) * bloomRadius * (1.0 + bass * 0.5);
    let bUv = clamp(uv + bo, vec2<f32>(0.0), vec2<f32>(1.0));
    let bSample = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).rgb;
    bloom = bloom + max(bSample, vec3<f32>(0.0));
  }
  bloom = bloom / f32(bloomSamples);
  // Only add bloom to very bright areas.
  let bloomMask = smoothstep(0.5, 1.2, length(color));
  color = color + bloom * bloomMask * (0.25 + treble * 0.25);

  // Hue shimmer tied to treble and time.
  let shimHue = fract(time * speed * 0.04 + treble * 0.25);
  let shimRgb = hsv2rgb(vec3<f32>(shimHue, 0.45, 1.0));
  color = color + shimRgb * 0.06 * (1.0 + volume);

  // Vignette before tone map to preserve HDR contrast.
  let vign = 1.0 - smoothstep(0.55, 1.25, length(p * 0.5));
  color = color * vign;

  // ACES tone mapping with HDR headroom.
  let hdrHeadroom = 1.0 + bass * 0.6 + mids * 0.4;
  color = acesToneMap(color * hdrHeadroom);

  // Temporal feedback using previous frame.
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.02 + bass * 0.01);

  let depth = clamp((r + g + b) * norm * 0.4, 0.0, 1.0);
  let alpha = clamp(length(color) * 0.7, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(color, alpha));
}
