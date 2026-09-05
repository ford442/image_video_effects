// ═══════════════════════════════════════════════════════════════════
//  PP Sharpen
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: interactive clarity lens + traveling sharpness wavefronts
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
  zoom_params: vec4<f32>,  // x=Amount, y=Radius, z=EdgeThreshold, w=Mode
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let invRes = 1.0 / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[3].x;

  // Single-writer spring cursor in extraBuffer[133..138]
  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 14.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.0), vec2<f32>(4.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  // Four saved controls preserved
  let amountParam = u.zoom_params.x;
  let radiusParam = u.zoom_params.y;
  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.z);
  let mode = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  // Proximity to spring inspection lens
  let distMouse = length((uv - spring) * aspectVec);
  let lensInfluence = smoothstep(0.40, 0.04, distMouse) * select(1.0, 1.5, held);

  // Click ripple wavefronts that trigger traveling clarity surges
  var rippleSurge = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.48) * 36.0) * exp(-age * 1.5);
      rippleSurge += ring;
    }
  }

  // Effective sharpen amount boosted by lens, ripples, and treble
  let effectiveAmount = mix(0.2, 2.8, amountParam) * (1.0 + lensInfluence * 0.65 + rippleSurge * 0.8 + treble * 0.45);
  let effectiveRadius = (0.5 + radiusParam * 2.0) * invRes * depthScale;

  // Center sample
  let centerCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let centerLuma = getLuma(centerCol);

  // 8-tap Gaussian / Bilateral blur kernel
  let offsets = array<vec2<f32>, 8>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
    vec2<f32>(-1.0,  0.0),                       vec2<f32>(1.0,  0.0),
    vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
  );
  let spatialWeights = array<f32, 8>(
    0.075, 0.15, 0.075,
    0.15,        0.15,
    0.075, 0.15, 0.075
  );

  var blurCol = vec3<f32>(0.0);
  var totalWeight = 0.0;
  var maxGradient = 0.0;

  for (var k = 0; k < 8; k = k + 1) {
    let tapUV = clamp(uv + offsets[k] * effectiveRadius, vec2<f32>(0.0), vec2<f32>(1.0));
    let tapCol = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb;
    let tapLuma = getLuma(tapCol);
    let diff = abs(centerLuma - tapLuma);
    maxGradient = max(maxGradient, diff);

    // Range weight to prevent haloing around high-contrast edges
    let rangeWeight = exp(-diff * diff / (2.0 * edgeThreshold * edgeThreshold + 0.001));
    let w = spatialWeights[k] * rangeWeight;
    blurCol += tapCol * w;
    totalWeight += w;
  }
  blurCol = blurCol / max(totalWeight, 1e-4);

  // High-pass detail vector
  let highPass = centerCol - blurCol;
  let edgeStrength = maxGradient;
  let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold * 1.5, edgeStrength);

  var sharpened = centerCol;

  if (mode < 0.33) {
    // Mode 0: Film Unsharp Mask with soft-knee coring to suppress noise in flat areas
    let coring = smoothstep(0.005, 0.04, abs(getLuma(highPass)));
    sharpened = centerCol + highPass * effectiveAmount * coring;
  } else if (mode < 0.66) {
    // Mode 1: Anisotropic Edge Enhance - boost edges without flattening midtones
    let boost = edgeMask * effectiveAmount * (1.0 + mids * 0.4);
    sharpened = mix(centerCol, centerCol + highPass * (1.0 + boost), edgeMask);
  } else {
    // Mode 2: High-Frequency Laplacian Detail with holographic edge pop
    let pop = smoothstep(0.0, 0.25, length(highPass)) * highPass;
    let edgeNeon = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + time * 2.0 + binA * 3.0);
    sharpened = centerCol + pop * effectiveAmount * 2.0 + edgeNeon * edgeMask * rippleSurge * 0.35;
  }

  // Exact previous frame history load from dataTextureC for temporal anti-jitter
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.05, 0.22, clamp(1.0 - edgeMask + bass * 0.2, 0.0, 1.0));
  var hdr = mix(sharpened, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(0.85 + edgeMask * 0.12 + rippleSurge * 0.25, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + edgeMask * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
