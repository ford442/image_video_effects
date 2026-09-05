// ═══════════════════════════════════════════════════════════════════
//  multi-fractal-compositor-lens — Multi-Layer Fractal & Gravitational Lens
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fractal-compositor, gravitational-lens, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=LensMass, y=RingGlow, z=RippleMass, w=ChromaBoost
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn gravitationalBend(uv: vec2<f32>, massPos: vec2<f32>, mass: f32) -> vec2<f32> {
  let toMass = massPos - uv;
  let dist = length(toMass);
  let deflection = mass * toMass / (dist * dist + 0.001);
  return uv + deflection * 0.01;
}

fn pingPong(v: vec2<f32>) -> vec2<f32> {
  return 1.0 - abs(fract(v * 0.5) * 2.0 - 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let zoom_time = u.zoom_config.x;
  let zoom_center = u.zoom_config.yz;

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
  let lensMass = mix(0.5, 5.0, u.zoom_params.x) * (1.0 + bass * 0.35);
  let ringGlowStrength = mix(0.0, 1.0, u.zoom_params.y);
  let rippleMass = mix(0.5, 3.0, u.zoom_params.z);
  let chromaBoost = mix(0.01, 0.07, u.zoom_params.w) * (1.0 + treble * 0.4);

  // Gravitational bending
  var bentUV = gravitationalBend(uv, mouse, lensMass);

  // Ripple masses
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 3.0) {
      let decay = exp(-elapsed * 0.8);
      let rippleBend = gravitationalBend(uv, ripple.xy, rippleMass * decay);
      bentUV += (rippleBend - uv) * decay;
    }
  }

  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let layerDepth = f32(i) / 3.0;
    let layerSpeed = mix(0.2, 0.8, layerDepth);
    let layerZoom = 1.0 + fract(zoom_time * layerSpeed + time * 0.05) * 3.0;

    let lensedToCenter = (bentUV - zoom_center) * vec2<f32>(aspect, 1.0);
    let dist = length(lensedToCenter);
    let spinAngle = (0.2 * held / (dist + 0.1)) * layerDepth * (1.0 - layerDepth);
    let cosS = cos(spinAngle);
    let sinS = sin(spinAngle);
    let rotated = vec2<f32>(
      (cosS * lensedToCenter.x - sinS * lensedToCenter.y) / aspect,
      sinS * lensedToCenter.x + cosS * lensedToCenter.y
    ) + zoom_center;

    let flowUV = rotated + vec2<f32>(
      noise(rotated * 6.0 + vec2<f32>(time * 0.15, 0.0)),
      noise(rotated * 6.0 + vec2<f32>(0.0, time * 0.15))
    ) * 0.015 * layerDepth;

    let transformed = (flowUV - zoom_center) / layerZoom + zoom_center;
    let pingUV = pingPong(transformed);

    let sampleColor = textureSampleLevel(readTexture, u_sampler, pingUV, 0.0).rgb;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pingUV, 0.0).r;

    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5);
    accumulatedColor += sampleColor * weight;
    accumulatedDepth += sampleDepth * weight;
    totalWeight += weight;
  }

  let baseColor = accumulatedColor / max(totalWeight, 0.0001);
  let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

  // Chromatic aberration from lens distortion
  let effectiveChroma = chromaBoost * (1.0 + baseDepth * 0.5);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(effectiveChroma, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g = baseColor.g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(effectiveChroma, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  var color = mix(baseColor, vec3<f32>(r, g, b), 0.7);

  // Einstein ring glow
  let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let einsteinRadius = sqrt(lensMass * 0.015);
  let ringGlow = smoothstep(0.06, 0.0, abs(mouseDist - einsteinRadius)) * ringGlowStrength;
  color += vec3<f32>(0.9, 0.8, 0.6) * ringGlow * (1.0 + mids * 0.3);

  // Core glow
  let coreGlow = exp(-mouseDist * mouseDist * 300.0) * lensMass * 0.25;
  color += vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.08);

  let finalRGB = aces(color);
  let alpha = clamp(0.35 + ringGlow * 0.3 + coreGlow * 0.4 + held * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
