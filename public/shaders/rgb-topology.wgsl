// ═══════════════════════════════════════════════════════════════════
//  RGB Topology v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware
//  Complexity: High
//  Chunks From: rgb-topology
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

fn hypsoTint(t: f32) -> vec3<f32> {
  let low = vec3<f32>(0.12, 0.42, 0.18);
  let mid = vec3<f32>(0.55, 0.38, 0.22);
  let high = vec3<f32>(0.92, 0.92, 0.95);
  let s1 = smoothstep(0.25, 0.55, t);
  let s2 = smoothstep(0.6, 0.9, t);
  return mix(mix(low, mid, s1), high, s2);
}

fn grain(uv: vec2<f32>, t: f32) -> f32 {
  return fract(sin(dot(uv + t, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 0.03 - 0.015;
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
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let contourDensity = mix(6.0, 80.0, u.zoom_params.x + bass * 0.25);
  let lineThickness = mix(0.004, 0.09, u.zoom_params.y);
  let channelSep = mix(0.0, 0.06, u.zoom_params.z);
  let sourceBlend = mix(0.0, 0.8, u.zoom_params.w);
  let elevExag = 0.5 + depth * 1.5;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let rotAngle = (mouse.x - 0.5) * 1.2;
  let s = sin(rotAngle);
  let c = cos(rotAngle);
  let rotUV = vec2<f32>(
    centered.x * c - centered.y * s,
    centered.x * s + centered.y * c
  );

  let topoR = (src.r * 0.8 + depth * 0.2) * elevExag + rotUV.x * 0.3;
  let topoG = (src.g * 0.8 + depth * 0.2) * elevExag + rotUV.y * 0.25;
  let topoB = (src.b * 0.8 + depth * 0.2) * elevExag - length(rotUV) * 0.18;

  let intervals = vec3<f32>(1.0, 1.618, 2.414);
  let lineR = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoR + time * 0.02) * contourDensity * intervals.x)));
  let lineG = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoG + time * 0.03) * contourDensity * intervals.y)));
  let lineB = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoB - time * 0.025) * contourDensity * intervals.z)));

  let hachureR = 1.0 - smoothstep(0.0, lineThickness * 1.6, abs(sin((topoR + time * 0.015) * contourDensity * intervals.x * 2.0 + 1.57)));
  let hachureG = 1.0 - smoothstep(0.0, lineThickness * 1.6, abs(sin((topoG + time * 0.02) * contourDensity * intervals.y * 2.0 + 1.57)));
  let hachureB = 1.0 - smoothstep(0.0, lineThickness * 1.6, abs(sin((topoB - time * 0.018) * contourDensity * intervals.z * 2.0 + 1.57)));

  let tilt = rotUV * channelSep * (0.5 + bass * 0.5);
  let sampR = textureSampleLevel(readTexture, u_sampler, clamp(uv + tilt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let sampG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let sampB = textureSampleLevel(readTexture, u_sampler, clamp(uv - tilt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  let hypsoR = hypsoTint(clamp(topoR, 0.0, 1.0));
  let hypsoG = hypsoTint(clamp(topoG, 0.0, 1.0));
  let hypsoB = hypsoTint(clamp(topoB, 0.0, 1.0));

  var contourColor = vec3<f32>(lineR * sampR * hypsoR.r, lineG * sampG * hypsoG.g, lineB * sampB * hypsoB.b);
  contourColor = contourColor + vec3<f32>(hachureR * sampR * 0.15, hachureG * sampG * 0.12, hachureB * sampB * 0.1);

  let peakMask = max(max(lineR * topoR, lineG * topoG), lineB * topoB);
  let specDir = normalize(vec3<f32>(rotUV * 0.5, 1.0));
  let spec = pow(max(0.0, specDir.z), 16.0) * peakMask * (0.35 + bass * 0.35);
  contourColor = contourColor + vec3<f32>(spec);

  let crossMix = smoothstep(0.01, 0.06, abs(lineR - lineG) + abs(lineG - lineB));
  let chromaBlend = mix(vec3<f32>(0.9, 0.25, 0.6), vec3<f32>(0.25, 0.85, 0.95), 0.5 + 0.5 * sin(time * 0.7));
  contourColor = mix(contourColor, contourColor * chromaBlend * 1.3, crossMix * 0.4);

  var finalColor = mix(contourColor, src.rgb, sourceBlend);
  finalColor = acesToneMap(finalColor * 1.15);
  finalColor = finalColor + vec3<f32>(grain(uv, time));

  let contourMask = max(max(lineR, lineG), lineB);
  let finalAlpha = clamp(contourDensity * 0.012 * channelSep * depth + contourMask * 0.38 + src.a * sourceBlend * 0.25, 0.04, 0.98);
  let outDepth = clamp(mix(depth, 0.18 + contourMask * 0.72, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lineR, lineG, lineB, finalAlpha));
}
