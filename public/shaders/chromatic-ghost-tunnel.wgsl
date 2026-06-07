// ═══════════════════════════════════════════════════════════════════
//  Chromatic Ghost Tunnel
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: High
//  Description: A perspective tunnel of chromatic ghost echoes.
//               Each ring is RGB-split by audio bands.
//               Bass warps tunnel depth, mids add spiral rotation,
//               treble creates stroboscopic ring flashes.
//               Mouse steers tunnel flight.
//  Created: 2026-05-30
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

const PI: f32 = 3.14159265;

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseOffset = vec2<f32>(mouse.x * aspect, mouse.y) * 0.4;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let tunnelSpeed   = mix(0.2, 2.0, u.zoom_params.x);
  let spiralTwist   = mix(0.0, 3.0, u.zoom_params.y);
  let echoCount     = mix(2.0, 8.0, u.zoom_params.z);
  let flashIntensity = mix(0.0, 1.0, u.zoom_params.w);

  // Perspective tunnel coordinates
  let tunnelUV = uv + mouseOffset;
  let dist = length(tunnelUV);
  let angle = atan2(tunnelUV.y, tunnelUV.x);

  // Bass warps tunnel depth
  let z = 1.0 / (dist + 0.01) + bass * 0.3;
  let moveZ = time * tunnelSpeed;

  // Mids add spiral rotation
  let twist = angle + z * spiralTwist * (0.5 + mids) + moveZ;

  var col = vec3<f32>(0.0);
  var alpha = 0.0;

  let nRings = i32(clamp(echoCount, 2.0, 12.0));

  for (var i: i32 = 0; i < nRings; i++) {
    let fi = f32(i);
    let ringPhase = fract(z * 2.0 - fi * 0.15 + moveZ * 0.3);
    let ringRadius = ringPhase * 0.6;
    let ringWidth = 0.02 + ringPhase * 0.01;

    let ringDist = abs(dist - ringRadius);
    let ringMask = exp(-ringDist * ringDist / (ringWidth * ringWidth));

    // Chromatic split per ring driven by audio bands
    let rOffset = bass * 0.03 * ringPhase;
    let gOffset = mids * 0.04 * ringPhase;
    let bOffset = treble * 0.02 * ringPhase;

    let dR = abs(dist - (ringRadius + rOffset));
    let dG = abs(dist - (ringRadius + gOffset));
    let dB = abs(dist - (ringRadius + bOffset));

    let ringR = exp(-dR * dR / (ringWidth * ringWidth));
    let ringG = exp(-dG * dG / (ringWidth * ringWidth));
    let ringB = exp(-dB * dB / (ringWidth * ringWidth));

    // Stroboscopic flashes on treble
    let flash = step(0.85, hash11(fi + time * 10.0 * treble)) * treble * flashIntensity;
    let flashMask = ringMask * (1.0 + flash * 3.0);

    // Ghost echo fade
    let echoFade = 1.0 - fi / echoCount;

    // Ring color varies with depth and audio
    let hue = ringPhase + fi * 0.1;
    let ringCol = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0 + bass * 0.1)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33 + mids * 0.1)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67 + treble * 0.1))
    );

    col.r += ringR * ringCol.r * echoFade * flashMask;
    col.g += ringG * ringCol.g * echoFade * flashMask;
    col.b += ringB * ringCol.b * echoFade * flashMask;
    alpha += ringMask * echoFade * flashMask;
  }

  // Spiral streaks driven by bass
  let streak = sin(twist * 6.0) * 0.5 + 0.5;
  let streakMask = exp(-dist * dist * 4.0) * (1.0 - dist * 1.5);
  let streakCol = vec3<f32>(0.4, 0.6, 1.0) * streak * streakMask * bass;
  col += streakCol;
  alpha += streakMask * bass * 0.5;

  // ═══ Temporal feedback with chromatic ghost echoes ═══
  let cStr = 0.005 + bass * 0.008;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));

  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
  let prevCol = vec3<f32>(prevR, prevG, prevB);
  col = mix(col, prevCol * 0.9, 0.25 + bass * 0.05);

  // Chromatic dispersion on current frame
  let dispersed = vec3<f32>(
    col.r + mids * 0.06 * (1.0 - dist),
    col.g + bass * 0.04 * (1.0 - dist),
    col.b + treble * 0.08 * (1.0 - dist)
  );
  col = mix(col, dispersed, 0.4);

  alpha = clamp(alpha, 0.0, 1.0);
  let depthVal = clamp(1.0 - dist * 2.0, 0.0, 1.0) * alpha;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
}
