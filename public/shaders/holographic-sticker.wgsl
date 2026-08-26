// ═══════════════════════════════════════════════════════════════════
//  Holographic Sticker — Rainbow Diffraction Foil
//  Category: visual-effects
//  Features: advanced-alpha, depth-aware, mouse-driven, audio-reactive,
//            chromatic-view-angle, temporal-foil-shimmer, audio-sticker-pulse,
//            depth-layered-alpha, spring-glide-center, click-foil-flashes
//  Complexity: Medium
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

const TAU: f32 = 6.28318530717958647692;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let radius = u.zoom_params.x;       // 0..1, default 0.5
  let intensity = u.zoom_params.y;    // 0..1, default 0.5
  let rainbowSpeed = u.zoom_params.z; // 0..1, default 0.5
  let depthWeight = u.zoom_params.w;  // 0..1, default 0.5

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let hasState = (arrayLength(&extraBuffer) > 138u);
  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 49.0;
    let damping = 14.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Aspect-corrected sticker distance
  let dM_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dM = length(dM_vec);

  // Audio-driven sticker pulse: bass modulates sticker radius slightly
  let effectiveRadius = radius * (0.95 + bass * 0.15 * sin(time * 3.0) + held * 0.08);
  let inCircle = smoothstep(effectiveRadius, effectiveRadius * 0.88, dM);

  // Iridescent hue from angle around the spring-smoothed center
  let viewAngle = atan2(dM_vec.y, dM_vec.x);
  let grating = sin(dM * 320.0 + viewAngle * 8.0) * 0.15;
  let hue = fract(viewAngle / TAU + time * rainbowSpeed * 0.4 + depth * 0.15 + bass * 0.08 + grating);

  // HSV foil construction
  let saturation = 0.88 + treble * 0.12;
  let value = 0.85 + mids * 0.25;
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(vec3<f32>(hue) + k.xyz) * 6.0 - k.www);
  var foil = value * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);

  // Audio spectrum modulation
  let palIdx = u32(clamp(hue * 7.0, 0.0, 7.0));
  let palette = plasmaBuffer[(palIdx % 8u) + 1u].rgb;
  foil = mix(foil, foil * (0.7 + palette * 0.6), 0.35 + held * 0.2);

  // Click foil flashes
  var flash = vec3<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 1.8) { continue; }
    let ringRadius = age * 0.6;
    let ringDist = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - ringRadius);
    let ringWidth = 0.018 + age * 0.035;
    let ringMask = smoothstep(ringWidth, 0.0, ringDist);
    let decay = max(1.0 - age / 1.8, 0.0);
    let ringHue = fract(hue + age * 0.8 + f32(i) * 0.19);
    let rp = abs(fract(vec3<f32>(ringHue) + k.xyz) * 6.0 - k.www);
    let ringColor = mix(k.xxx, clamp(rp - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);
    flash += ringColor * ringMask * (decay * decay);
  }
  foil += flash * (0.4 + intensity * 0.8);

  // Sticker rim specular & bevel highlight
  let rimGlow = smoothstep(effectiveRadius * 1.08, effectiveRadius, dM) * (1.0 - smoothstep(effectiveRadius, effectiveRadius * 0.94, dM));
  foil = foil + vec3<f32>(1.0, 0.95, 0.9) * (rimGlow * 1.5);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = mix(baseColor.rgb, baseColor.rgb * 0.35 + foil * intensity, inCircle);

  // Click flashes bleed across boundaries
  finalColor += flash * 0.25;

  // Temporal shimmer via exact dataTextureC load
  let prevFoil = textureLoad(dataTextureC, pixel, 0).rgb;
  let shimmer = mix(finalColor, prevFoil * 0.96, 0.05 + mids * 0.02);
  finalColor = mix(finalColor, shimmer, 0.35);

  // ACES tonemapping
  let finalRGB = aces(finalColor);

  // Semantic alpha: depth layer + sticker foil presence + base alpha
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let depthAlpha = mix(0.4, 1.0, depth);
  let lumaAlpha = mix(0.5, 1.0, luma);
  let blendedAlpha = mix(lumaAlpha, depthAlpha, depthWeight);
  let stickerAlpha = mix(baseColor.a, 1.0, inCircle * 0.85);
  let finalAlpha = clamp(mix(blendedAlpha, stickerAlpha, inCircle * 0.6) + rimGlow * 0.2, 0.3, 1.0);

  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
