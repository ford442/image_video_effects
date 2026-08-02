// ================================================================
//  Knitted Fabric
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: knitted-fabric
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=StitchSize, y=PullStrength, z=PullRadius, w=TextureDepth
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let rawMouse = u.zoom_config.yz;

  // The fabric pull point trails the pointer with a soft, critically damped
  // spring. Persistent state uses only extraBuffer[133..138].
  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var mouse = rawMouse;
  if (hasSpringState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = mouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 6.0;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let stitchScale = 24.0 + u.zoom_params.x * 124.0;
  let pullStrength = u.zoom_params.y * 0.55 * (1.0 + u.zoom_config.w * 0.20);
  let pullRadius = 0.04 + u.zoom_params.z * 0.70;
  let textureDepth = u.zoom_params.w;

  let pullVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let pullDist = length(pullVec);
  let pullDir = select(vec2<f32>(0.0), pullVec / max(pullDist, 0.0001), pullDist > 0.0001);
  let pullMask = 1.0 - smoothstep(0.0, pullRadius, pullDist);
  // Clicks pluck the textile as expanding waves at normalized ripple positions.
  var clickWarp = vec2<f32>(0.0);
  var clickRidge = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(2.0, age));
    let rv = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
    let rd = length(rv);
    let ring = 1.0 - smoothstep(0.012, 0.045, abs(rd - safeAge * 0.27));
    let wave = ring * exp(-safeAge * 1.35) * live;
    let radial = select(vec2<f32>(0.0), rv / max(rd, 0.0001), rd > 0.0001);
    clickWarp += vec2<f32>(radial.x / aspect, radial.y) * wave * pullStrength * 0.12;
    clickRidge = max(clickRidge, wave);
  }

  let distortedUV = clamp(
    uv - pullDir * pullMask * pullStrength * vec2<f32>(0.18 / aspect, 0.18) + clickWarp,
    vec2<f32>(0.0),
    vec2<f32>(1.0)
  );

  var st = distortedUV * stitchScale;
  let row = floor(st.y);
  let oddRow = fract(row * 0.5) > 0.25;
  if (oddRow) {
    st.x = st.x + 0.5;
  }

  let cellId = floor(st);
  let local = fract(st) * 2.0 - 1.0;
  let loopArc = local.x * local.x * 0.80 - 0.18;
  let underArc = local.x * local.x * 0.65 + 0.55;
  let topYarn = smoothstep(0.38, 0.0, abs(local.y - loopArc));
  let underYarn = smoothstep(0.34, 0.0, abs(local.y - underArc));
  let crossover = smoothstep(0.24, 0.0, abs(local.x)) * smoothstep(0.65, 0.05, abs(local.y));
  let yarnMask = clamp(max(topYarn, underYarn * 0.78) + crossover * 0.18, 0.0, 1.0);
  let gapMask = 1.0 - yarnMask;
  let fiberNoise =
    sin(local.x * 24.0 + local.y * 31.0 + time * 1.5) * 0.06 +
    cos(local.y * 18.0 - time * 2.1) * 0.04;
  let stitchBin = (u32(abs(cellId.x) + abs(cellId.y) * 3.0) % 8u) + 1u;
  let fftStitch = plasmaBuffer[stitchBin].x;
  let shimmer = (audio.x * 0.28 + audio.y * 0.16 + audio.z * 0.10 + fftStitch * 0.22) * smoothstep(0.55, 1.0, yarnMask);

  var weaveUV = (cellId + vec2<f32>(0.5, 0.5)) / stitchScale;
  if (oddRow) {
    weaveUV.x = weaveUV.x - 0.5 / stitchScale;
  }
  weaveUV = clamp(weaveUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, weaveUV, 0.0).rgb;
  let yarnTint = mix(vec3<f32>(1.0, 0.96, 0.92), vec3<f32>(1.0, 0.80, 0.55), audio.x * 0.40 + audio.z * 0.20);
  let shadow = mix(0.55, 1.0, yarnMask);

  var finalColor = baseColor * shadow;
  finalColor = finalColor * mix(vec3<f32>(0.70), vec3<f32>(1.0), yarnMask);
  finalColor = mix(finalColor, baseColor * 0.45, gapMask * 0.45 * textureDepth);
  finalColor = finalColor + vec3<f32>(fiberNoise) * 0.12;
  finalColor = finalColor + yarnTint * shimmer * (0.40 + 0.60 * textureDepth);
  finalColor += vec3<f32>(0.35, 0.18, 0.08) * clickRidge * (0.15 + textureDepth * 0.25);

  var finalAlpha = mix(0.42, 0.90, yarnMask);
  finalAlpha = mix(finalAlpha, finalAlpha * 0.74, pullMask * pullStrength);
  finalAlpha = clamp(finalAlpha - gapMask * 0.12 + shimmer * 0.08, 0.28, 0.95);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * yarnMask, 0.15 + 0.35 * textureDepth) - clickRidge * 0.035, 0.0, 1.0);

  let display = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), display);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  // A is the host's primary feedback/output owner; keep display color there and
  // move the diagnostic material masks to B.
  textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
  textureStore(dataTextureB, vec2<i32>(global_id.xy), vec4<f32>(yarnMask, max(pullMask, clickRidge), shimmer, finalAlpha));
}
