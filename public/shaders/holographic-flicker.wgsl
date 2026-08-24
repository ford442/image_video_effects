// ═══════════════════════════════════════════════════════════════════
//  Holographic Flicker — Laser Diode Instability & Phosphor Decay
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-flicker,
//            depth-rainbow, chromatic-ghosting, interference-fringes,
//            scanline-jitter, temporal-rgb-offset, upgraded-rgba
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn rot2D(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn sdfHexagon(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
  var p2 = abs(p);
  p2 = p2 - 2.0 * min(dot(k.xy, p2), 0.0) * k.xy;
  p2 = p2 - vec2<f32>(clamp(p2.x, -k.z * r, k.z * r), r);
  return length(p2) * sign(p2.y);
}

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
  let centeredUV = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  // Sliders: exact parameter contracts
  let flickerSpeed = u.zoom_params.x;     // 0..1, default 0.5
  let glitchAmt = u.zoom_params.y;        // 0..1, default 0.5
  let hologramIntensity = u.zoom_params.z;// 0..1, default 0.5
  let ghostAmt = u.zoom_params.w;         // 0..1, default 0.5

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Spring cursor in extraBuffer[133..138]
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

  // Aspect-corrected mouse interaction
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let pointerEffect = smoothstep(0.4, 0.0, mouseDist);

  // Click ripple shocks
  var rippleEffect = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
    rippleEffect += wave * 0.6;
  }

  // Hexagonal laser projection geometry
  var geo = 0.0;
  var gUv = centeredUV * rot2D(time * 0.4 + pointerEffect * 1.2) * (1.0 - rippleEffect * 0.1);
  for (var i = 0.0; i < 3.0; i += 1.0) {
    gUv = gUv * (1.45 + bass * 0.15);
    let d = sdfHexagon(gUv, 0.3 + 0.12 * sin(time * 2.0 + i + mids * 1.5));
    geo += smoothstep(0.02, 0.0, abs(d)) * (1.0 - i * 0.25);
  }

  // Scanline raster jitter and line tear
  let scanRate = time * (15.0 + flickerSpeed * 80.0);
  let glitchLine = floor(uv.y * resolution.y * 0.25 + scanRate);
  let jitter = (hash21(vec2<f32>(glitchLine, floor(time * 24.0))) - 0.5) * glitchAmt * (mids * 0.6 + 0.15) * 0.06;
  let jitteredUV = clamp(uv + vec2<f32>(jitter, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic RGB separation
  let chromaOffset = (glitchAmt + ghostAmt * 0.5) * 0.015 * (1.0 + treble * 0.8);
  let rRead = textureSampleLevel(readTexture, u_sampler, clamp(jitteredUV + vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gRead = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).g;
  let bRead = textureSampleLevel(readTexture, u_sampler, clamp(jitteredUV - vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let aRead = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).a;
  let rgb = vec3<f32>(rRead, gRead, bRead);

  // Exact dataTextureC temporal chromatic ghosting (channel shifted loads)
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let shiftX = i32((ghostAmt * 12.0 + rippleEffect * 8.0) * (1.0 + bass * 0.5));
  let rCoord = clamp(pixel + vec2<i32>(shiftX, 0), vec2<i32>(0), maxCoord);
  let bCoord = clamp(pixel - vec2<i32>(shiftX, 0), vec2<i32>(0), maxCoord);

  let prevCenter = textureLoad(dataTextureC, pixel, 0);
  let rGhost = textureLoad(dataTextureC, rCoord, 0).r;
  let bGhost = textureLoad(dataTextureC, bCoord, 0).b;
  let ghostColor = vec3<f32>(rGhost, prevCenter.g, bGhost) * ghostAmt * 0.85;

  // Prismatic depth rainbow
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let hue = fract(depth + time * (0.15 + flickerSpeed * 0.2) + bass * 0.2 + pointerEffect * 0.1);
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  let rainbow = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

  // Audio-reactive power flicker / blackout
  let flickerHash = hash21(vec2<f32>(floor(time * (10.0 + flickerSpeed * 50.0)), floor(uv.y * 30.0)));
  let blackout = step(1.0 - bass * 0.35, flickerHash) * (0.35 + glitchAmt * 0.45);

  let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let geoColor = rainbow * (geo * hologramIntensity * 1.6);

  var finalRGB = rgb + ghostColor + geoColor + (rainbow * (abs(rippleEffect) * 0.75));
  finalRGB = mix(finalRGB, vec3<f32>(0.02, 0.05, 0.1) * luma, blackout);

  // ACES Tonemapping
  finalRGB = aces(finalRGB);

  // Semantic alpha: source opacity + hologram emission + depth
  let alpha = clamp(aRead * 0.8 + luma * 0.25 + geo * 0.4 + abs(rippleEffect) * 0.2 + pointerEffect * 0.15, 0.25, 1.0);
  let outColor = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, outColor);
  textureStore(dataTextureA, pixel, outColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
