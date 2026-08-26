// ═══════════════════════════════════════════════════════════════════
//  Infinite Zoom Lens — Droste Spiral Recursion & Chromatic Dispersion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, droste-recursion, chromatic-dispersion,
//            temporal-feedback, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=ZoomStrength, y=LensRadius, z=FeedbackPersistence, w=Twist
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn drosteUV(uv: vec2<f32>, center: vec2<f32>, spiralZoom: f32, twist: f32) -> vec2<f32> {
  let offset = uv - center;
  let r = length(offset);
  let theta = atan2(offset.y, offset.x);
  let logR = log(max(r, 1e-5));
  let spiralAngle = logR * twist + spiralZoom;
  let newR = exp(logR * 0.72);
  let newTheta = theta + spiralAngle;
  let rotated = vec2<f32>(cos(newTheta), sin(newTheta)) * newR;
  return center + rotated;
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

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
  let zoomSpeed = mix(0.3, 2.5, u.zoom_params.x) * (1.0 + bass * 0.35);
  let radius = mix(0.06, 0.55, u.zoom_params.y);
  let persistence = mix(0.4, 0.95, u.zoom_params.z);
  let twistAmt = (u.zoom_params.w - 0.5) * 2.2 + bass * 0.35 + held * 0.15;
  let recursionDepth = i32(mix(2.0, 7.0, depth));

  let centered = (uv - mouse) * vec2<f32>(dims.x / max(dims.y, 1.0), 1.0);
  let dist = length(centered);
  let lensMask = 1.0 - smoothstep(radius, radius + 0.03, dist);

  var accum = vec3<f32>(0.0);
  var totalW = 0.0;
  var recursionConfidence = 0.0;

  for (var i: i32 = 0; i < recursionDepth; i = i + 1) {
    let fi = f32(i);
    let scale = pow(0.78, fi) * (1.0 + bass * 0.12);
    let angle = time * zoomSpeed * 0.15 + fi * twistAmt * 0.4;
    let spiralCenter = mouse + vec2<f32>(sin(time * 0.2 + fi * 1.3) * 0.02, cos(time * 0.17 + fi * 1.1) * 0.02);
    var sampleUV = drosteUV(uv, spiralCenter, angle, twistAmt * 0.6);
    sampleUV = (sampleUV - spiralCenter) / scale + spiralCenter;
    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let w = pow(persistence, fi);
    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let histPixel = clamp(vec2<i32>(sampleUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let hist = textureLoad(dataTextureC, histPixel, 0);
    let mixed = mix(src.rgb, hist.rgb, persistence * 0.55);

    let armShift = (sampleUV - spiralCenter) * 0.025 * (1.0 + fi * 0.3) * lensMask * (1.0 + treble * 0.4);
    let chromaR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + armShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let chromaB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - armShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let chroma = vec3<f32>(chromaR, mixed.g, chromaB);

    accum += chroma * w;
    totalW += w;
    recursionConfidence += w * (1.0 - abs(scale - 1.0));
  }

  var finalColor = accum / max(totalW, 1e-4);
  let axial = smoothstep(0.07, 0.0, abs(fract(dist * 6.0 - time * (2.5 + mids)) - 0.5));
  let runner = smoothstep(0.05, 0.0, abs(fract(atan2(centered.y, centered.x) / TAU * 14.0 + time * 1.8) - 0.5));
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(dist * 8.0 - time * 0.5) + vec3<f32>(0.0, 0.333, 0.667)));
  let focalBloom = pow(max(0.0, 1.0 - dist / radius), 4.0) * (0.15 + bass * 0.2);
  finalColor = finalColor + oilSlick * (axial * 0.2 + runner * 0.15) * lensMask;
  finalColor = finalColor + oilSlick * focalBloom;

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.5) {
      let d = length((uv - rp.xy) * vec2<f32>(dims.x / max(dims.y, 1.0), 1.0));
      clickRing = max(clickRing, exp(-abs(d - age * 0.45) * 45.0) * (1.0 - age / 1.5));
    }
  }
  finalColor += vec3<f32>(0.4, 0.9, 1.0) * clickRing * 0.35;

  finalColor = acesToneMap(finalColor * 1.1);
  finalColor += vec3<f32>((ign(uv) - 0.5) / 255.0);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  finalColor = mix(current.rgb, finalColor, lensMask);
  let spiralIntensity = smoothstep(0.1, 0.5, abs(twistAmt));
  let finalAlpha = clamp(recursionConfidence * 0.08 * spiralIntensity * depth + lensMask * 0.55 + current.a * 0.2 + held * 0.15, 0.04, 0.98);
  let outDepth = clamp(mix(depth, 0.15 + lensMask * 0.7, 0.25), 0.0, 1.0);

  let outPixel = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, pixel, outPixel);
  textureStore(dataTextureA, pixel, outPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
