// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Smear — May 2026 Batch D Upgrade
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Chunks From: temporal-rgb-smear (original)
//  Created: 2026-05-02
//  Upgraded: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters: x=Smear Length, y=Smear Decay, z=Chromatic Split, w=Turbulence
  let smearLength = mix(0.01, 0.25, u.zoom_params.x);
  let smearDecay = mix(0.3, 0.98, u.zoom_params.y);
  let chromaticSplit = mix(0.0, 0.05, u.zoom_params.z) * (1.0 + mids * 0.5);
  let turbulence = u.zoom_params.w;

  // Depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.3, depth);

  // Directional smear: estimate motion from dataTextureC gradients
  let texel = vec2<f32>(1.0) / resolution;
  let hC = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let hR = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
  let hL = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
  let hU = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
  let hD = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
  let gradX = (hR - hL) * 0.5;
  let gradY = (hU - hD) * 0.5;
  let motionDir = normalize(vec2<f32>(gradX, gradY) + vec2<f32>(0.0001));

  // Time-based offset blended with estimated motion
  let timeAngle = time * 0.5 + turbulence * 6.2831;
  let timeDir = vec2<f32>(cos(timeAngle), sin(timeAngle));
  let motionStrength = length(vec2<f32>(gradX, gradY));
  let smearDir = mix(timeDir, motionDir, smoothstep(0.0, 0.05, motionStrength));

  let len = smearLength * (1.0 + bass * 0.3) * depthFactor;

  // Chromatic samples along smear direction, split modulated by mids
  let offR = uv + smearDir * len * (1.0 + chromaticSplit);
  let offG = uv + smearDir * len;
  let offB = uv + smearDir * len * (1.0 - chromaticSplit);

  let colR = textureSampleLevel(readTexture, u_sampler, offR, 0.0).r;
  let colG = textureSampleLevel(readTexture, u_sampler, offG, 0.0).g;
  let colB = textureSampleLevel(readTexture, u_sampler, offB, 0.0).b;

  // Temporal accumulation from history
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let fb = smearDecay * (1.0 + bass * 0.15);

  let accR = mix(colR, history.r, fb * 0.5);
  let accG = mix(colG, history.g, fb * 0.45);
  let accB = mix(colB, history.b, fb * 0.5);

  // Treble sparkle near mouse
  let sparkle = treble * 0.2 * smoothstep(0.3, 0.0, distance(uv, mouse));

  let outColor = vec3<f32>(accR + sparkle, accG, accB);

  // Accumulative alpha — trails fade over time
  let trailAlpha = mix(0.5, 0.95, smearDecay) * mix(0.7, 1.0, 1.0 - depth * 0.3);

  // Store history for next frame
  textureStore(dataTextureA, global_id.xy, vec4<f32>(outColor, trailAlpha));

  textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, trailAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
