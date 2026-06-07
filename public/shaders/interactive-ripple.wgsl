// ═══════════════════════════════════════════════════════════════════
//  Interactive Ripple v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, wave
//  Complexity: High
//  Chunks From: interactive-ripple
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn causticPattern(p: vec2<f32>, t: f32) -> f32 {
  let c1 = sin(p.x * 12.0 + t * 2.0) + sin(p.y * 10.0 - t * 1.5);
  let c2 = sin((p.x + p.y) * 8.0 + t) * 0.5;
  return smoothstep(0.2, 1.8, c1 + c2) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let waveHeight = u.zoom_params.x * 0.045;
  let waveCount = mix(3.0, 22.0, u.zoom_params.y + bass * 0.25);
  let waveSpeedBase = 0.25 + u.zoom_params.z * 3.5;
  let damping = mix(0.3, 2.5, u.zoom_params.w);
  let waterDepth = mix(0.2, 3.0, depth);
  let rippleCount = min(u32(u.config.y), 50u);

  var totalOffset = vec2<f32>(0.0);
  var rippleHeight = 0.0;
  var dispersionIntensity = 0.0;

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let center = ripple.xy;
    let delta = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(delta);
    let age = max(0.0, time - ripple.z);
    let envelope = exp(-age * damping) * exp(-dist * (3.0 + damping));

    let waveSpeed = waveSpeedBase * sqrt(waterDepth) * (1.0 + bass * 0.3);
    let phase = dist * waveCount * 8.0 - age * waveSpeed * 6.0;
    let wave = sin(phase) * envelope;

    let dispersionFreq = waveCount * (1.0 + treble * 0.5);
    let waveDisp = sin(phase * 1.3 + age * 2.0) * envelope * 0.35;
    let dir = delta / max(dist, 1e-4);

    totalOffset = totalOffset + dir * (wave + waveDisp) * waveHeight;
    rippleHeight = rippleHeight + abs(wave);
    dispersionIntensity = dispersionIntensity + abs(waveDisp);
  }

  let boundReflect = vec2<f32>(1.0) - smoothstep(vec2<f32>(0.92), vec2<f32>(1.0), abs(uv - 0.5) * 2.0);
  totalOffset = totalOffset * boundReflect;

  let sampleUV = clamp(uv + totalOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  let crestMask = smoothstep(0.15, 0.55, rippleHeight);
  let chromaDisp = totalOffset * crestMask * 0.06 * (1.0 + treble * 0.5);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + chromaDisp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - chromaDisp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var finalColor = vec3<f32>(r, src.g, b);

  let caustic = causticPattern(sampleUV * 3.0, time) * smoothstep(0.35, 0.85, rippleHeight) * (0.25 + mids * 0.35);
  let causticTint = mix(vec3<f32>(0.85, 0.95, 1.0), vec3<f32>(0.6, 0.9, 1.0), 0.5 + 0.5 * sin(time * 1.2));
  finalColor = finalColor + causticTint * caustic;

  let bloom = pow(max(0.0, rippleHeight - 0.5), 2.0) * (0.2 + bass * 0.25);
  let bloomTint = mix(vec3<f32>(0.1, 0.5, 0.9), vec3<f32>(0.95, 0.75, 1.0), 0.5 + 0.5 * sin(time * 0.8));
  finalColor = finalColor + bloomTint * bloom;

  let sss = smoothstep(0.0, 0.4, rippleHeight) * depth * 0.15;
  let sssTint = vec3<f32>(0.08, 0.35, 0.55);
  finalColor = mix(finalColor, finalColor + sssTint * sss, 0.4);

  let wetRefl = smoothstep(0.5, 1.0, rippleHeight) * 0.08;
  finalColor = finalColor + vec3<f32>(wetRefl);

  finalColor = acesToneMap(finalColor * 1.1);

  let finalAlpha = clamp(rippleHeight * dispersionIntensity * depth * 2.5 + 0.55 + caustic * 0.3, 0.06, 0.98);
  let outDepth = clamp(mix(depth, 0.2 + rippleHeight * 0.15, 0.3), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(totalOffset.x, totalOffset.y, rippleHeight, finalAlpha));
}
