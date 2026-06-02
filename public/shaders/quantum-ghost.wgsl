// ═══════════════════════════════════════════════════════════════════
//  Quantum Ghost v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-ghosting, interference-fringes,
//            upgraded-rgba, quantum-uncertainty, wave-packet, entanglement-correlation
//  Complexity: Very High
//  Chunks From: quantum-ghost.wgsl v1
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gaussianWavePacket(uv: vec2<f32>, center: vec2<f32>, sigma: f32, momentum: vec2<f32>, time: f32) -> f32 {
  let drift = momentum * time * 0.1;
  let d = uv - center - drift;
  let spread = sigma + time * 0.02;
  let amp = exp(-dot(d, d) / (2.0 * spread * spread));
  let phase = dot(d, momentum) * 20.0 - time * 3.0;
  return amp * cos(phase);
}

fn quantumNumberGlow(n: i32, uv: vec2<f32>, time: f32) -> vec3<f32> {
  let col = select(select(vec3<f32>(0.0, 1.0, 0.8), vec3<f32>(1.0, 0.2, 0.9), n == 2), vec3<f32>(0.2, 0.6, 1.0), n == 1);
  let pulse = 0.7 + 0.3 * sin(time * 4.0 + f32(n) * 1.7);
  return col * pulse;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let offsetStrength = u.zoom_params.x * 0.06 * (1.0 + bass * 0.4);
  let fringeFreq = u.zoom_params.y * 60.0;
  let ghostDecay = 0.82 + u.zoom_params.z * 0.16;
  let chromaticShift = u.zoom_params.w * 0.012;

  let uncertaintySpread = (1.0 - depth) * 0.15 * (1.0 + bass * 0.5);
  let measurementCertainty = select(0.3 + depth * 0.5, 1.0, mouseDown > 0.5);

  let dir = normalize(uv - mousePos + vec2<f32>(0.001));
  let offset = dir * offsetStrength;

  let mainColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let wave1 = gaussianWavePacket(uv, mousePos, 0.08 + uncertaintySpread, dir, time);
  let wave2 = gaussianWavePacket(uv, mousePos + offset * 2.0, 0.06, dir * 1.3, time);
  let interference = (wave1 + wave2) * 0.5;

  let ghostUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let ghostColor = textureSampleLevel(readTexture, u_sampler, ghostUV, 0.0);

  let prevGhost = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let temporalGhost = mix(ghostColor, prevGhost, ghostDecay);

  let fringePhase = dot(uv - 0.5, dir) * fringeFreq * (1.0 + treble * 0.6);
  let fringe = cos(fringePhase) * 0.5 + 0.5;
  let partialMeasurement = fringe * (1.0 - measurementCertainty) * 2.0;

  let rGhostUV = clamp(ghostUV + vec2<f32>(chromaticShift * (1.0 + uncertaintySpread * 3.0), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bGhostUV = clamp(ghostUV - vec2<f32>(chromaticShift * (1.0 + uncertaintySpread * 3.0), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let rGhost = textureSampleLevel(readTexture, u_sampler, rGhostUV, 0.0).r;
  let bGhost = textureSampleLevel(readTexture, u_sampler, bGhostUV, 0.0).b;

  let depthAtten = mix(1.0, 0.25, depth);
  let ghostMix = temporalGhost.rgb * depthAtten;

  let entangleLine = smoothstep(0.02, 0.0, abs(dot(uv - mousePos, vec2<f32>(-dir.y, dir.x))));
  let entangleGlow = entangleLine * 0.4 * (0.5 + 0.5 * sin(time * 6.0)) * (1.0 - measurementCertainty);

  let qn = i32(fract(time * 0.3) * 3.0) + 1;
  let qnGlow = quantumNumberGlow(qn, uv, time) * entangleGlow * 2.0;

  var rgb = vec3<f32>(
    mix(mainColor.r, rGhost, fringe * 0.35 * depthAtten),
    mix(mainColor.g, ghostMix.g, fringe * 0.28 * depthAtten),
    mix(mainColor.b, bGhost, fringe * 0.35 * depthAtten)
  );

  rgb = rgb + vec3<f32>(interference * 0.15 * depthAtten);
  rgb = rgb + qnGlow;

  let bloom = max(entangleGlow * 3.0, 0.0) * vec3<f32>(1.0, 0.9, 0.6);
  rgb = rgb + bloom * (1.0 + bass * 0.5);

  let fringeTint = vec3<f32>(0.0, mids * 0.12, mids * 0.18) * fringe;
  var finalRGB = rgb + fringeTint;

  finalRGB = acesToneMap(finalRGB * 1.2);

  let waveAmp = abs(interference) * depthAtten;
  let alpha = clamp(waveAmp * measurementCertainty + depthAtten * 0.12 + bass * 0.04, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(temporalGhost.rgb, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
