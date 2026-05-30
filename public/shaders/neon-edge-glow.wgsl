// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Glow v2
//  Category: visual-effects
//  Features: edge-glow, neon, bloom, gas-discharge, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: neon-edge-glow
//  Upgraded: 2026-05-30
//  By: 4-Agent Shader Upgrade Swarm
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

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neonSpectrum(t: f32, flicker: f32) -> vec3<f32> {
  let r = 0.85 * exp(-pow((t - 0.35) / 0.12, 2.0)) * (1.0 + flicker * 0.3);
  let g = 0.45 * exp(-pow((t - 0.52) / 0.10, 2.0)) * (1.0 + flicker * 0.15);
  let b = 0.25 * exp(-pow((t - 0.68) / 0.14, 2.0)) * (1.0 + flicker * 0.1);
  return vec3<f32>(r, g, b);
}

fn mercurySpectrum(t: f32) -> vec3<f32> {
  let r = 0.15 * exp(-pow((t - 0.40) / 0.08, 2.0));
  let g = 0.55 * exp(-pow((t - 0.55) / 0.06, 2.0));
  let b = 0.35 * exp(-pow((t - 0.72) / 0.10, 2.0));
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;

  let edgeStrength = u.zoom_params.x;
  let glowRadius = u.zoom_params.y;
  let neonTint = u.zoom_params.z;
  let intensity = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

  let texel = 1.0 / dims;
  let l = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let r = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let t = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let b = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

  let edgeMag = length(vec2<f32>(l - r, t - b)) * edgeStrength * (1.0 + bass * 0.5);

  let acFreq = 60.0 + bass * 40.0;
  let acPhase = time * acFreq;
  let rectified = abs(sin(acPhase));
  let flicker = pow(rectified, 0.7) * (0.85 + 0.15 * sin(time * 7.0 + bass * 5.0));
  let beatFlicker = step(0.7, bass) * 0.2 * sin(time * 20.0);

  let mouseOffset = (mouse - 0.5) * 0.15;
  let bendUV = uv + vec2<f32>(sin(uv.y * 3.14159) * mouseOffset.x, sin(uv.x * 3.14159) * mouseOffset.y);

  let tubeT = fract(neonTint * 0.8 + bendUV.x * 2.0 + time * 0.08);
  let neonColor = neonSpectrum(tubeT, flicker + beatFlicker);
  let mercuryColor = mercurySpectrum(tubeT) * (0.3 + mids * 0.4);

  let edgeMask = smoothstep(0.015, 0.22, edgeMag);
  let neonLine = (neonColor + mercuryColor) * edgeMask * intensity * (0.75 + treble * 0.5 + flicker * 0.3);

  let glow = smoothstep(0.0, glowRadius * 0.10, edgeMag) * (1.0 - smoothstep(glowRadius * 0.05, glowRadius * 0.15, edgeMag));
  let glowBloom = glow * intensity * 0.5 * neonColor;

  let electrodeGlow = exp(-abs(bendUV.x - 0.05) * 30.0) + exp(-abs(bendUV.x - 0.95) * 30.0);
  let sputter = vec3<f32>(1.0, 0.85, 0.6) * electrodeGlow * (0.15 + flicker * 0.25) * edgeMask;

  let chromaShift = vec2<f32>(texel.x * 1.5, 0.0) * edgeMask;
  let rEnd = textureSampleLevel(readTexture, u_sampler, clamp(uv + chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bEnd = textureSampleLevel(readTexture, u_sampler, clamp(uv - chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticBase = vec3<f32>(rEnd, baseColor.g, bEnd);

  let haze = exp(-depth * 2.0) * 0.15 * mids;
  let atmospheric = vec3<f32>(0.6, 0.7, 0.9) * haze;

  let bloomRing = smoothstep(0.25, 0.0, abs(edgeMag - 0.12)) * 0.3 * intensity;
  let secondaryBloom = neonColor * bloomRing * (0.4 + bass * 0.3);

  let tubeGeometry = smoothstep(0.02, 0.06, edgeMag) * (1.0 - smoothstep(0.12, 0.20, edgeMag));
  let tubeCore = neonColor * tubeGeometry * 0.25 * flicker;

  var finalColor = chromaticBase + neonLine + glowBloom + secondaryBloom + sputter + atmospheric + tubeCore;
  finalColor = acesTonemap(finalColor * 1.2);

  let tubeExcitation = edgeMask * (flicker + 0.3) + glow * 0.5 + electrodeGlow * 0.2;
  let finalAlpha = clamp(tubeExcitation * intensity * depth, 0.25, 0.98);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(edgeMask, flicker, tubeExcitation, finalAlpha));
}
