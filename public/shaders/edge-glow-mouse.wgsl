// ═══════════════════════════════════════════════════════════════════
//  Edge Glow Mouse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: edge-glow-mouse
//  Created: 2026-05-30
//  By: 4-Agent Upgrade Swarm
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
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.x);
  let glowRadius = mix(0.08, 0.70, u.zoom_params.y) * (1.0 + bass * 0.35);
  let intensity = mix(0.3, 2.5, u.zoom_params.z);
  let colorSpeed = 0.2 + u.zoom_params.w * 4.0;

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Unsharp masking kernel
  let center = sampleLuma(uv);
  let nb = sampleLuma(uv + vec2<f32>(px.x, 0.0)) + sampleLuma(uv - vec2<f32>(px.x, 0.0))
         + sampleLuma(uv + vec2<f32>(0.0, px.y)) + sampleLuma(uv - vec2<f32>(0.0, px.y));
  let sharpened = center * 5.0 - nb;

  let edgeX = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let edgeY = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let edgeGrad = vec2<f32>(edgeX, edgeY);
  let edgeMag = length(edgeGrad);
  let edgeTangent = normalize(vec2<f32>(-edgeY, edgeX) + 0.0001);
  let glowMask = smoothstep(edgeThreshold, edgeThreshold + 0.15, edgeMag);

  // Multi-octave glow bloom with anisotropic diffusion
  var glowAccum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var o: i32 = 0; o < 4; o = o + 1) {
    let radius = glowRadius * (1.0 + f32(o) * 0.6) * px;
    let offset = edgeTangent * radius * (1.0 + f32(o) * 0.4);
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let w = 1.0 / (1.0 + f32(o) * 0.7);
    glowAccum = glowAccum + samp * w;
    weightSum = weightSum + w;
  }
  let glowColor = glowAccum / max(weightSum, 0.001);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseAura = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
  let hue = 0.5 + 0.5 * sin(time * colorSpeed + mouseDist * 18.0);
  let neonTint = mix(vec3<f32>(0.10, 0.85, 1.0), vec3<f32>(1.0, 0.45, 0.75), hue);

  // Chromatic aberration on glow halos
  let caStrength = 0.003 * glowMask * intensity;
  let rSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var chromatic = vec3<f32>(rSamp, baseColor.g, bSamp);
  chromatic = mix(baseColor, chromatic, glowMask * 0.5);

  // HDR bloom composite
  var finalColor = chromatic + neonTint * glowMask * intensity * (0.25 + mouseAura + bass * 0.4);
  finalColor = finalColor + glowColor * glowMask * intensity * 0.35 * (1.0 + mouseAura);
  finalColor = mix(finalColor, finalColor * (1.0 + sharpened * 0.15), glowMask);

  // Depth-driven glow falloff
  let depthFalloff = mix(1.0, 0.3, depth);
  finalColor = finalColor * depthFalloff;

  // ACES tone mapping + film grain
  finalColor = acesToneMap(finalColor * 1.2);
  let grain = (hash21(uv * 1000.0 + time * 60.0) - 0.5) * 0.03;
  finalColor = finalColor + grain;

  // Semantic alpha: edge_strength * glow_radius * depth
  let finalAlpha = clamp(glowMask * glowRadius * depth * 2.5, 0.15, 0.95);
  let depthOut = clamp(mix(depth, 0.20 + glowMask * 0.72, 0.26), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(glowMask, mouseAura, intensity, finalAlpha));
}
