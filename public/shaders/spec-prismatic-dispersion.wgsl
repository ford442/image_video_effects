// ═══════════════════════════════════════════════════════════════════
//  Prismatic Dispersion
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06
//  Ideas: internal double-refraction caustic rings; anti-reflective purplish-amber lens sheen; astigmatic chromatic radial streaks
//  A packing: ACES display RGBA
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
  zoom_params: vec4<f32>,  // x=GlassCurvature, y=CauchyB, z=GlassThickness, w=SpectralSaturation
  ripples: array<vec4<f32>, 50>,
};

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

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
  let toCenter = uv - center;
  let dist = length(toCenter);
  let lensStrength = curvature * 0.4;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
  return uv + offset;
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
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, isMouseDown);

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
  let glassCurvature = mix(0.1, 1.2, u.zoom_params.x) * (1.0 + bass * 0.25);
  let cauchyB = mix(0.01, 0.08, u.zoom_params.y) * (1.0 + treble * 0.3);
  let glassThickness = mix(0.3, 1.5, u.zoom_params.z);
  let spectralSat = mix(0.3, 1.2, u.zoom_params.w) * (1.0 + mids * 0.2);

  // Dynamic lens center: mouse
  let lensCenter = mouse;

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleOffset = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleOffset += rDir * wave * 0.03;
    }
  }

  let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
  var finalColor = vec3<f32>(0.0);

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
    let refractedUV = refractThroughSurface(uv + rippleOffset, lensCenter, ior, glassCurvature);

    let wrappedUV = clamp(refractedUV, vec2<f32>(0.001), vec2<f32>(0.999));
    let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);

    let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
    let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
    finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
  }

  // ─── Native Idea 1: Internal Double-Refraction Caustic Rings ───
  let distToLens = length((uv - lensCenter) * vec2<f32>(aspect, 1.0));
  let causticRingDist = abs(distToLens - 0.28 * glassCurvature);
  let causticRing = exp(-pow(causticRingDist * 28.0, 2.0)) * (0.35 + bass * 0.45);
  let causticColor = vec3<f32>(1.0, 0.96, 0.82) * causticRing * spectralSat;
  finalColor += causticColor;

  // ─── Native Idea 2: Anti-Reflective Lens Coating Purplish-Amber Sheen ───
  let viewAngle = acos(clamp(1.0 - distToLens * 0.75, 0.0, 1.0));
  let arFresnel = pow(sin(viewAngle), 3.2);
  let arSheen = mix(vec3<f32>(0.28, 0.12, 0.65), vec3<f32>(0.65, 0.38, 0.12), sin(viewAngle * 3.5) * 0.5 + 0.5) * arFresnel * 0.42;
  finalColor += arSheen;

  // ─── Native Idea 3: Astigmatic Chromatic Radial Streaks ───
  let radDir = normalize((uv - lensCenter) * vec2<f32>(aspect, 1.0) + vec2<f32>(1e-4));
  let streakOffset = radDir * 0.012 * glassCurvature * (1.0 + treble * 0.5);
  let streakSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + streakOffset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let streakHighlight = max(streakSample - vec3<f32>(0.62), vec3<f32>(0.0)) * 1.6;
  finalColor += streakHighlight * spectralSat * 0.32;

  // Chromatic glow
  let glowRadius = glassCurvature * 0.02;
  var glowColor = vec3<f32>(0.0);
  let glowSamples = 8;
  for (var j: i32 = 0; j < glowSamples; j = j + 1) {
    let angle = f32(j) * 0.785398 + time * 0.5;
    let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
    let gSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    glowColor += gSample.rgb;
  }
  glowColor /= f32(glowSamples);
  finalColor += glowColor * 0.08 * glassCurvature;

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08);

  let finalRGB = aces(finalColor);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.4 + glassThickness * 0.3 + exp(-distToLens * 4.0) * 0.25 + causticRing * 0.2 + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
