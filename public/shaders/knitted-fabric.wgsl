// ═══════════════════════════════════════════════════════════════════
//  Knitted Fabric
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04
//  Ideas: strain-thinned yarn and opening gaps under the pull; two-ply twist striation; heathered per-stitch fibre tint
//  A packing: ACES display RGBA; B keeps the documented material masks (yarn, pull/ridge, shimmer, alpha)
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
  zoom_params: vec4<f32>,  // x=StitchSize, y=PullStrength, z=PullRadius, w=TextureDepth
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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

  // Raw pointer: the old extraBuffer[133..138] spring never persisted (the
  // host re-uploads the whole extraBuffer every frame).
  let mouse = rawMouse;
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
  // Idea 1: strain. Where the cursor pulls (and where a pluck wave passes)
  // the stitches are stretched, so the yarn thins and the gaps between loops
  // open onto the dark backing.
  let strain = clamp(pullMask * pullStrength * 1.6 + clickRidge * 0.35, 0.0, 0.85);
  let yarnWidth = 1.0 - strain * 0.55;
  let topYarn = smoothstep(0.38 * yarnWidth, 0.0, abs(local.y - loopArc));
  let underYarn = smoothstep(0.34 * yarnWidth, 0.0, abs(local.y - underArc));
  let crossover = smoothstep(0.24, 0.0, abs(local.x)) * smoothstep(0.65, 0.05, abs(local.y));
  let yarnMask = clamp(max(topYarn, underYarn * 0.78) + crossover * 0.18, 0.0, 1.0);
  let gapMask = 1.0 - yarnMask;
  let fiberNoise =
    sin(local.x * 24.0 + local.y * 31.0 + time * 1.5) * 0.06 +
    cos(local.y * 18.0 - time * 2.1) * 0.04;
  // Only plasmaBuffer[0] is uploaded: each stitch listens to one of the three bands.
  let stitchBin = u32(abs(cellId.x) + abs(cellId.y) * 3.0) % 3u;
  let fftStitch = select(select(audio.z, audio.y, stitchBin == 1u), audio.x, stitchBin == 0u);

  // Idea 2: two-ply twist. Diagonal striations run along whichever yarn
  // dominates this texel, measured across that yarn's own centreline.
  let onTop = topYarn >= underYarn * 0.78;
  let across = select(local.y - underArc, local.y - loopArc, onTop);
  let twist = sin(local.x * 9.0 + across * 14.0 * select(-1.0, 1.0, onTop));
  let plyShade = mix(0.84, 1.07, smoothstep(-0.35, 0.35, twist));

  // Idea 3: heathered yarn. Each stitch is spun from slightly different
  // fibre, with an occasional pale fleck.
  let heatherSeed = vec3<f32>(hash12(cellId), hash12(cellId + vec2<f32>(17.3, 5.1)), hash12(cellId + vec2<f32>(41.7, 23.9)));
  let fleck = step(0.94, hash12(cellId * 1.31 + vec2<f32>(9.2, 3.7)));
  let heather = (vec3<f32>(1.0) + (heatherSeed - vec3<f32>(0.5)) * 0.10) * (1.0 + fleck * 0.18);
  let shimmer = (audio.x * 0.28 + audio.y * 0.16 + audio.z * 0.10 + fftStitch * 0.22) * smoothstep(0.55, 1.0, yarnMask);

  var weaveUV = (cellId + vec2<f32>(0.5, 0.5)) / stitchScale;
  if (oddRow) {
    weaveUV.x = weaveUV.x - 0.5 / stitchScale;
  }
  weaveUV = clamp(weaveUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, weaveUV, 0.0).rgb * heather;
  let yarnTint = mix(vec3<f32>(1.0, 0.96, 0.92), vec3<f32>(1.0, 0.80, 0.55), audio.x * 0.40 + audio.z * 0.20);
  let shadow = mix(0.55, 1.0, yarnMask);

  var finalColor = baseColor * shadow;
  finalColor = finalColor * mix(vec3<f32>(0.70), vec3<f32>(1.0), yarnMask);
  finalColor = mix(finalColor, baseColor * 0.45, gapMask * 0.45 * textureDepth);
  finalColor = finalColor * mix(1.0, plyShade, yarnMask);
  finalColor = mix(finalColor, finalColor * 0.35, gapMask * strain * 0.8);
  finalColor = finalColor + vec3<f32>(fiberNoise) * 0.12;
  finalColor = finalColor + yarnTint * shimmer * (0.40 + 0.60 * textureDepth);
  finalColor += vec3<f32>(0.35, 0.18, 0.08) * clickRidge * (0.15 + textureDepth * 0.25);

  var finalAlpha = mix(0.42, 0.90, yarnMask);
  finalAlpha = mix(finalAlpha, finalAlpha * 0.74, pullMask * pullStrength);
  finalAlpha = clamp(finalAlpha - gapMask * 0.12 + shimmer * 0.08, 0.28, 0.95);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * yarnMask, 0.15 + 0.35 * textureDepth) - clickRidge * 0.035, 0.0, 1.0);

  let display = vec4<f32>(aces(max(finalColor, vec3<f32>(0.0)) * 0.8), finalAlpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), display);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  // A is the host's primary feedback/output owner; keep display color there and
  // move the diagnostic material masks to B.
  textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
  textureStore(dataTextureB, vec2<i32>(global_id.xy), vec4<f32>(yarnMask, max(pullMask, clickRidge), shimmer, finalAlpha));
}
