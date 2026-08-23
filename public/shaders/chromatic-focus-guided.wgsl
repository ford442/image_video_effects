// ═══════════════════════════════════════════════════════════════════
//  chromatic-focus-guided — Depth-Guided 7-Band Chromatic Dispersion
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            chromatic-focus, guided-filter-depth, semantic-alpha, ACES
//  Complexity: Very High
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=AberrationIntensity, y=FocusRadius, z=SpectralSpread, w=AnimationSpeed
  ripples: array<vec4<f32>, 50>,
};

const SPECTRAL_RED:     f32 = 0.65;
const SPECTRAL_ORANGE:  f32 = 0.59;
const SPECTRAL_YELLOW:  f32 = 0.57;
const SPECTRAL_GREEN:   f32 = 0.52;
const SPECTRAL_BLUE:    f32 = 0.45;
const SPECTRAL_INDIGO:  f32 = 0.40;
const SPECTRAL_VIOLET:  f32 = 0.38;

const CAUCHY_A: f32 = 1.5;
const CAUCHY_B: f32 = 0.01;

const RED_W:    vec3<f32> = vec3<f32>(0.95, 0.25, 0.01);
const ORANGE_W: vec3<f32> = vec3<f32>(0.85, 0.45, 0.02);
const YELLOW_W: vec3<f32> = vec3<f32>(0.75, 0.70, 0.05);
const GREEN_W:  vec3<f32> = vec3<f32>(0.15, 0.95, 0.15);
const BLUE_W:   vec3<f32> = vec3<f32>(0.05, 0.35, 0.85);
const INDIGO_W: vec3<f32> = vec3<f32>(0.10, 0.25, 0.75);
const VIOLET_W: vec3<f32> = vec3<f32>(0.35, 0.15, 0.65);

fn cauchyRefractiveIndex(wavelength: f32) -> f32 {
  return CAUCHY_A + CAUCHY_B / (wavelength * wavelength);
}

fn sampleSpectralBand(uv: vec2<f32>, direction: vec2<f32>, wavelength: f32, baseStrength: f32, spectralSpread: f32) -> f32 {
  let n = cauchyRefractiveIndex(wavelength);
  let dispersionStrength = (n - 1.0) * baseStrength * spectralSpread;
  let displacedUV = clamp(uv + direction * dispersionStrength, vec2<f32>(0.001), vec2<f32>(0.999));
  let sample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  return dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (gid.x == 0u && gid.y == 0u);
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
  let aberIntensity = u.zoom_params.x * 0.08 * (1.0 + bass * 0.35);
  let focusRadius = u.zoom_params.y * 0.4 + 0.05;
  let spectralSpread = (u.zoom_params.z * 2.0 + 0.5) * (1.0 + treble * 0.3);
  let animSpeed = u.zoom_params.w * 3.0;
  let animationOffset = time * animSpeed;

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let focusFactor = smoothstep(focusRadius, focusRadius + 0.4, dist);
  let effectiveStrength = aberIntensity * focusFactor;

  let angle = atan2(distVec.y, distVec.x) + sin(animationOffset) * 0.2;
  let radialDir = vec2<f32>(cos(angle), sin(angle));
  let angularDispersion = vec2<f32>(cos(angle + 1.5707963), sin(angle + 1.5707963)) * 0.3;
  let dispersionDir = normalize(radialDir + angularDispersion);

  // Guided filter using depth to prevent cross-edge dispersion bleeding
  let maxRadius = 3;
  var sumGuide = 0.0;
  var sumInput = vec3<f32>(0.0);
  var sumGuideInput = vec3<f32>(0.0);
  var sumGuide2 = 0.0;
  var count = 0.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
      let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
      let inputVal = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      sumGuide += guideVal;
      sumInput += inputVal;
      sumGuideInput += inputVal * guideVal;
      sumGuide2 += guideVal * guideVal;
      count += 1.0;
    }
  }

  let meanGuide = sumGuide / max(count, 1.0);
  let meanInput = sumInput / max(count, 1.0);
  let meanGI = sumGuideInput / max(count, 1.0);
  let meanGuide2 = sumGuide2 / max(count, 1.0);
  let varGuide = max(meanGuide2 - meanGuide * meanGuide, 0.00001);
  let epsilon = 0.005;
  let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
  let b = meanInput - a * meanGuide;
  let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let guidedResult = a * guide + b;

  // Sample 7 spectral bands
  let redSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_RED, effectiveStrength, spectralSpread);
  let orangeSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_ORANGE, effectiveStrength, spectralSpread);
  let yellowSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_YELLOW, effectiveStrength, spectralSpread);
  let greenSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_GREEN, effectiveStrength, spectralSpread);
  let blueSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_BLUE, effectiveStrength, spectralSpread);
  let indigoSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_INDIGO, effectiveStrength, spectralSpread);
  let violetSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_VIOLET, effectiveStrength, spectralSpread);

  var spectralColor = vec3<f32>(0.0);
  spectralColor += RED_W * redSample;
  spectralColor += ORANGE_W * orangeSample;
  spectralColor += YELLOW_W * yellowSample;
  spectralColor += GREEN_W * greenSample;
  spectralColor += BLUE_W * blueSample;
  spectralColor += INDIGO_W * indigoSample;
  spectralColor += VIOLET_W * violetSample;
  spectralColor /= vec3<f32>(3.2, 3.1, 2.58);

  let sharpColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let sharpWeight = 1.0 - focusFactor;
  var finalColor = mix(spectralColor, sharpColor, sharpWeight * 0.45);
  finalColor = mix(finalColor, guidedResult, 0.35 + mids * 0.2);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-abs(rDist - age * 0.5) * 15.0) * (1.0 - age * 0.5);
      finalColor += vec3<f32>(0.2, 0.4, 0.8) * wave * 0.4;
    }
  }

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08);

  let finalRGB = aces(finalColor);
  let alpha = clamp(0.3 + focusFactor * 0.5 + held * 0.2, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(guide, 0.0, 0.0, 0.0));
}
