// ═══════════════════════════════════════════════════════════════════
//  Rotoscope Ink v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, edge-stylization
//  Complexity: High
//  Chunks From: rotoscope-ink
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let edgeThreshold = mix(0.025, 0.32, u.zoom_params.x);
  let levels = mix(2.0, 10.0, u.zoom_params.y);
  let inkDensity = mix(0.25, 1.5, u.zoom_params.z);
  let shadeMix = mix(0.06, 1.0, u.zoom_params.w);

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let l = sampleLuma(uv - px);
  let r = sampleLuma(uv + vec2<f32>(px.x, -px.y));
  let t = sampleLuma(uv + vec2<f32>(-px.x, px.y));
  let b = sampleLuma(uv + px);
  let edgeGrad = vec2<f32>(r - l, t - b);
  let edge = length(edgeGrad);
  let edgeDir = atan2(edgeGrad.y, edgeGrad.x);

  let temporalNoise = hash12(floor(uv * 80.0) + vec2<f32>(time * 8.0, time * 5.0));
  let motionStrength = smoothstep(edgeThreshold, edgeThreshold + 0.18, edge) * (0.7 + temporalNoise * 0.3);

  let brushAngle = edgeDir + temporalNoise * 0.4 * (1.0 + audio.x);
  let brushUV = vec2<f32>(
    uv.x * cos(brushAngle) + uv.y * sin(brushAngle),
    -uv.x * sin(brushAngle) + uv.y * cos(brushAngle)
  );
  let brushStroke = smoothstep(0.0, 0.5, sin(brushUV.x * 120.0)) * smoothstep(0.0, 0.15, abs(sin(brushUV.y * 60.0)));
  let taperedLine = brushStroke * motionStrength * (0.6 + 0.4 * sin(brushUV.x * 30.0 + time * 3.0));

  let posterized = floor(src.rgb * levels) / max(levels - 1.0, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.5, length((uv - mouse) * vec2<f32>(aspect, 1.0)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax = (depth - 0.5) * 0.008;
  let parallaxUV = clamp(uv + vec2<f32>(parallax, parallax * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let parallaxSrc = textureSampleLevel(readTexture, u_sampler, parallaxUV, 0.0).rgb;

  let inkTint = mix(vec3<f32>(0.04, 0.04, 0.05), vec3<f32>(0.10, 0.18, 0.30), audio.z * 0.45);
  let edgeGlow = mix(vec3<f32>(0.85, 0.45, 0.15), vec3<f32>(0.25, 0.85, 1.0), 0.5 + 0.5 * sin(time + uv.y * 14.0));

  let fastEdge = smoothstep(0.12, 0.35, edge) * (0.5 + 0.5 * sin(time * 6.0 + edge * 20.0));
  let chromaSepR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(fastEdge * 0.003, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromaSepB = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(fastEdge * 0.003, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticSrc = vec3<f32>(chromaSepR, src.g, chromaSepB);

  var toon = mix(chromaticSrc, posterized, shadeMix);
  let bleedEdge = smoothstep(0.02, 0.08, edge) * (1.0 - smoothstep(0.08, 0.18, edge));
  toon = mix(toon, toon * (1.0 - inkDensity * 0.22) + inkTint * 0.12, bleedEdge * 0.4);

  let jitter = (hash12(uv * 200.0 + time * 20.0) - 0.5) * audio.x * 0.035;
  let handDrawn = toon + inkTint * (taperedLine * inkDensity + jitter);
  let mouseInk = mouseMask * smoothstep(0.4, 0.6, hash12(floor(uv * 70.0) + vec2<f32>(time * 4.0, 0.0))) * 0.2;

  let filmGrain = (hash12(uv * 600.0 + fract(time) * 100.0) - 0.5) * 0.035;
  var finalColor = mix(handDrawn, inkTint, taperedLine * inkDensity * 0.8) + edgeGlow * taperedLine * mouseMask * (0.06 + audio.x * 0.2) + mouseInk * inkTint;
  finalColor = mix(finalColor, parallaxSrc * 0.5 + finalColor * 0.5, depth * 0.3);
  finalColor = finalColor + filmGrain;
  finalColor = acesToneMap(finalColor * 1.05);

  let outlineConfidence = clamp(taperedLine + motionStrength * 0.5 + bleedEdge * 0.3, 0.0, 1.0);
  let finalAlpha = clamp(outlineConfidence * motionStrength * depth + src.a * 0.12 + bleedEdge * 0.15, 0.07, 0.95);

  let outDepth = clamp(mix(depth, 0.16 + outlineConfidence * 0.8, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(outlineConfidence, motionStrength, mouseMask, finalAlpha));
}
