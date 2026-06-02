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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
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
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;

  let stitchScale = 24.0 + u.zoom_params.x * 124.0;
  let pullStrength = u.zoom_params.y * 0.55;
  let pullRadius = 0.04 + u.zoom_params.z * 0.70;
  let textureDepth = u.zoom_params.w;

  let pullVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let pullDist = length(pullVec);
  let pullDir = select(vec2<f32>(0.0), pullVec / max(pullDist, 0.0001), pullDist > 0.0001);
  let pullMask = 1.0 - smoothstep(0.0, pullRadius, pullDist);
  let distortedUV = clamp(
    uv - pullDir * pullMask * pullStrength * vec2<f32>(0.18 / aspect, 0.18),
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
  let shimmer = (audio.x * 0.35 + audio.y * 0.20 + audio.z * 0.15) * smoothstep(0.55, 1.0, yarnMask);

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

  var finalAlpha = mix(0.42, 0.90, yarnMask);
  finalAlpha = mix(finalAlpha, finalAlpha * 0.74, pullMask * pullStrength);
  finalAlpha = clamp(finalAlpha - gapMask * 0.12 + shimmer * 0.08, 0.28, 0.95);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * yarnMask, 0.15 + 0.35 * textureDepth), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(yarnMask, pullMask, shimmer, finalAlpha));
}
