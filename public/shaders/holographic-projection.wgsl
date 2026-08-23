// ═══════════════════════════════════════════════════════════════════
//  Holo Projector — Batch 58C rebuild
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal,
//            holographic-scan, speckle-interference
//  Complexity: High
//  Upgraded: 2026-08-23
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

const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn iqPalette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(t, t + 0.33, t + 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let scanSpeed = u.zoom_params.x * 4.0 + 0.5;
  let glitchAmt = u.zoom_params.y;
  let holoHue = u.zoom_params.z;
  let focusStrength = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let band = plasmaBuffer[(u32(hash12(uv * 80.0) * 8.0) % 8u) + 1u].x;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scanY = fract(uv.y * 120.0 - time * scanSpeed * (1.0 + bass * 0.35));
  let scanLine = smoothstep(0.02, 0.0, abs(scanY - 0.5)) * 0.35;
  let refreshPhase = sin(uv.y * resolution.y * 0.08 - time * scanSpeed * 2.0 + mids * 2.0);

  let glitchSeed = hash12(floor(uv * vec2<f32>(resolution.x * 0.02, 12.0)) + floor(time * (3.0 + glitchAmt * 8.0)));
  let glitchDrop = select(1.0, 0.0, glitchSeed > (1.0 - glitchAmt * 0.25));
  let chromaShift = (hash12(uv + time) - 0.5) * glitchAmt * 0.012 * (1.0 + treble * 0.5);
  let rUV = clamp(uv + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let holoRgb = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    src.g * glitchDrop,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  let speckle = hash12(uv * 400.0 + time * 0.5) * (0.85 + treble * 0.3);
  let interference = 0.5 + 0.5 * cos((uv.x * aspect + uv.y) * 80.0 + refreshPhase * 3.0 + band * 6.0);
  var color = holoRgb * (0.7 + interference * 0.35) * (0.9 + speckle * 0.2);

  let tint = iqPalette(holoHue + time * 0.05 * mids + depth * 0.1);
  color = mix(color, color * tint * 1.4, 0.35 + glitchAmt * 0.15);
  color += vec3<f32>(0.2, 0.85, 1.0) * scanLine;

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let stabilize = (1.0 - smoothstep(0.0, 0.4, mouseDist)) * focusStrength * (0.5 + held * 0.5);
  color = mix(color, color * 1.2 + tint * 0.15, stabilize);
  color = mix(color, prev.rgb, (1.0 - stabilize) * 0.12);

  var clickPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickPulse += exp(-age * 2.0) * exp(-abs(rDist - age * 0.5) * 50.0);
  }
  color += tint * clickPulse * 0.4;

  color = aces(color * (1.0 + bass * 0.1));
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(src.a, 0.35 + luma * 0.55, 0.7) + stabilize * 0.1 + clickPulse * 0.08, 0.15, 1.0);
  let finalPixel = vec4<f32>(color, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
