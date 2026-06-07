// ═══════════════════════════════════════════════════════════════════
//  Chroma Threads v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-threads
//  Upgraded: 2026-05-30
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn aniso_noise(p: vec2<f32>, angle: f32, scale: f32) -> f32 {
  let ca = cos(angle);
  let sa = sin(angle);
  let rot = vec2<f32>(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
  let i = floor(rot * scale);
  let f = fract(rot * scale);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sheen_brdf(V: vec3<f32>, L: vec3<f32>, N: vec3<f32>, roughness: f32) -> f32 {
  let H = normalize(V + L);
  let NdotH = max(dot(N, H), 0.0);
  let NdotV = max(dot(N, V), 0.0001);
  let NdotL = max(dot(N, L), 0.0);
  let d = (NdotH * NdotH) * (roughness * roughness - 1.0) + 1.0;
  let D = (roughness * roughness) / (3.14159 * d * d);
  let G = min(1.0, min(2.0 * NdotH * NdotV / dot(V, H), 2.0 * NdotH * NdotL / dot(V, H)));
  return D * G * 0.25 / (NdotV * max(NdotL, 0.0001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let time = u.config.x;
  let mouseDown = u.zoom_config.w;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let densityBase = mix(40.0, 320.0, u.zoom_params.x);
  let density = densityBase * (0.7 + depth * 0.6);
  let amp = u.zoom_params.y * 0.18;
  let split = u.zoom_params.z * 0.045;
  let decay = u.zoom_params.w;

  let threadID = floor(uv.y * density);
  let threadUVY = (threadID + 0.5) / density;
  let distY = abs(threadUVY - mouse.y);
  let influence = smoothstep(0.2 + decay * 0.1, 0.0, distY);
  let distX = uv.x - mouse.x;

  let tension = 1.0 + bass * 0.8;
  let weaveAngle = 0.785 + sin(threadID * 0.17) * 0.35;
  let aniso = aniso_noise(uv, weaveAngle, density * tension * 0.5);
  let weave = sin(distX * (20.0 + treble * 12.0) * tension - time * (6.0 + bass * 10.0));
  let pluck = exp(-abs(distX) * (3.0 + decay * 5.0));
  let vibration = weave * pluck * (1.0 + aniso * 0.5);
  let activeAmp = amp * (1.0 + mouseDown * 2.5 + bass * 0.7);
  let offset = vibration * influence * activeAmp;

  let threadPattern = abs(fract(uv.y * density) - 0.5) * 2.0;
  let mask = smoothstep(0.95, 0.5, threadPattern);
  let sheen = smoothstep(0.6, 1.0, sin((uv.y * density + time * (1.0 + mids * 5.0)) * 6.28318) * 0.5 + 0.5);

  let offsetR = offset * (1.0 + split * 12.0);
  let offsetG = offset * (0.85 + decay * 0.5);
  let offsetB = offset * (1.0 - split * 12.0);

  let uvR = clamp(vec2<f32>(uv.x - offsetR, uv.y), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = clamp(vec2<f32>(uv.x - offsetG, uv.y), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(vec2<f32>(uv.x - offsetB, uv.y), vec2<f32>(0.001), vec2<f32>(0.999));

  let sampled = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  let N = normalize(vec3<f32>(offset * 15.0, 0.5, 1.0));
  let V = vec3<f32>(0.0, 0.0, 1.0);
  let L = normalize(vec3<f32>(0.3, 0.7, 0.6));
  let spec = sheen_brdf(V, L, N, 0.35) * sheen * influence;
  let silk = vec3<f32>(0.9, 0.82 + treble * 0.18, 0.7) * spec * 0.4;
  let sss = vec3<f32>(1.0, 0.35 + mids * 0.3, 0.65) * max(offset, 0.0) * 1.6 * (1.0 - mask);

  let edgeCA = smoothstep(0.5, 0.0, abs(offset) * 10.0) * split * vec3<f32>(1.0, 0.6, 0.3);
  let finalColor = aces_tone_map(sampled * mask + silk + sss + edgeCA);

  let threadDensityVis = density / 320.0;
  let alpha = clamp(threadDensityVis * sheen * depth + abs(offset) * 4.0 + influence * 0.1, 0.08, 1.0);
  let outDepth = clamp(depth + abs(offset) * 0.2 + sheen * 0.05, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(offset, influence, sheen, alpha));
}
