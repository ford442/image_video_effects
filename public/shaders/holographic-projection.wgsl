// ═══════════════════════════════════════════════════════════════════
//  Holo Projector — Premium Volumetric Hologram
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal,
//            holographic-scan, speckle-interference, depth-aware
//  Complexity: High
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

const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn holoPalette(t: f32, hueShift: f32) -> vec3<f32> {
  let a = vec3<f32>(0.35, 0.65, 0.75);
  let b = vec3<f32>(0.45, 0.55, 0.65);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(hueShift, hueShift + 0.33, hueShift + 0.67);
  return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  // Sliders
  let scanSpeed = u.zoom_params.x * 2.0 + 0.5;
  let glitchAmt = u.zoom_params.y;
  let holoHue = u.zoom_params.z;
  let focusStrength = u.zoom_params.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binVal = plasmaBuffer[(u32(uv.x * 7.0) % 8u) + 1u].x;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 36.0;
    let damping = 12.0;
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

  // Exact previous frame from dataTextureC
  let prev = textureLoad(dataTextureC, pixel, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Aspect-corrected mouse distance & focus
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let focusRegion = (1.0 - smoothstep(0.0, 0.45, mouseDist)) * focusStrength * (0.6 + held * 0.4);

  // Scanline raster & Bessel interference fringe
  let scanPhase = fract(uv.y * (160.0 + bass * 30.0) - time * scanSpeed * (1.0 + bass * 0.4));
  let scanLine = smoothstep(0.03, 0.0, abs(scanPhase - 0.5)) * 0.45;
  let refreshWave = sin(uv.y * 35.0 - time * (scanSpeed * 1.5) + mids * 2.0);

  // Glitch displacement & chromatic splitting
  let glitchBlock = hash12(floor(uv * vec2<f32>(30.0, 8.0)) + floor(time * (4.0 + glitchAmt * 12.0)));
  let glitchActive = step(1.0 - glitchAmt * 0.35 * (1.0 - focusRegion * 0.7), glitchBlock);
  let jitterOffset = (hash12(uv + time) - 0.5) * glitchAmt * (0.015 + treble * 0.02) * glitchActive;

  let rUV = clamp(uv + vec2<f32>(jitterOffset + 0.004 * glitchAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + vec2<f32>(jitterOffset * 0.2, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - vec2<f32>(jitterOffset + 0.004 * glitchAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let srcR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let srcG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let srcB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let holoBase = vec3<f32>(srcR, srcG, srcB);

  // Volumetric quantum speckle & interference
  let speckle = (hash12(uv * 500.0 + time) - 0.5) * (0.15 + treble * 0.25) * (1.0 - focusRegion * 0.5);
  let fringeAngle = (uv.x * aspect + uv.y) * 90.0 + refreshWave * 2.5 + binVal * 4.0;
  let interference = 0.5 + 0.5 * cos(fringeAngle);

  // Holographic tinting & depth slicing
  let tint = holoPalette(holoHue + depth * 0.25 + time * 0.04, holoHue);
  var color = holoBase * (0.65 + interference * 0.4) + tint * (scanLine * 0.8 + 0.15 * refreshWave);
  color = color + vec3<f32>(speckle);

  // Focus stabilization & color enrichment
  color = mix(color, holoBase * 1.25 + tint * 0.2, focusRegion);

  // Bounded click ripple excitation
  var clickFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let ringRadius = age * 0.6;
    let ringBand = exp(-abs(rDist - ringRadius) * 45.0) * exp(-age * 1.8);
    clickFlash += ringBand;
  }
  color += tint * (clickFlash * 0.85);

  // Temporal persistence blend with dataTextureC
  let persistFactor = mix(0.18, 0.04, focusRegion);
  color = mix(color, prev.rgb, persistFactor);

  // ACES Tonemap
  let finalRGB = aces(color * (1.0 + bass * 0.2));

  // Semantic alpha: blend source alpha with emission luminance & depth
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(srcA, 0.4 + luma * 0.6, 0.75) + focusRegion * 0.15 + clickFlash * 0.1, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
