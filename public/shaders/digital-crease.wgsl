// ═══════════════════════════════════════════════════════════════════
//  Digital Crease v2
//  Category: geometric
//  Features: mouse-driven, audio-reactive, temporal-paper-fold, depth-curve-distortion, chromatic-folding, upgraded-rgba, origami
//  Complexity: Very High
//  Chunks From: digital-crease
//  Created: 2026-05-31
//  By: 4-Agent Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn paperTex(p: vec2<f32>, dir: vec2<f32>) -> f32 {
  let coarse = noise2(p * 60.0 + dir * 8.0) * 0.07;
  let fine = noise2(p * 180.0) * 0.035;
  let micro = noise2(p * 500.0) * 0.015;
  return coarse + fine + micro;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  let c = x * 0.85 + 0.30;
  return clamp((a / b) * c, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Param mapping: x=FoldCount, y=FoldDepth, z=FoldSoftness, w=ChromaOffset
  let foldCount = mix(2.0, 16.0, u.zoom_params.x);
  let foldDepth = u.zoom_params.y * 1.6;
  let foldSoftness = u.zoom_params.z;
  let chromaOffset = u.zoom_params.w * 0.014;

  // Bass drives fold animation speed
  let speed = time * (1.0 + audio.x * 0.5);
  let bassEnv = 1.0 + audio.x * 0.3;

  // Base crease pattern from center
  let center = vec2<f32>(0.5);
  let dToCenter = uv - center;
  let angle = atan2(dToCenter.y, dToCenter.x);
  let dist = length(dToCenter);

  // Mouse performs local folds
  let mouseDelta = uv - mouse;
  let mouseAngle = atan2(mouseDelta.y, mouseDelta.x);
  let mouseDist = length(mouseDelta * vec2<f32>(aspect, 1.0));
  let mouseFold = sin(mouseAngle * 4.0 + speed) * exp(-mouseDist * 5.0) * 0.4 * bassEnv;

  // Mountain/valley assignment via sine folding
  let baseFold = angle * foldCount + speed * 0.25;
  let rawFold = sin(baseFold);

  // Kawasaki-Justin flat-foldability approximation: alternate amplitudes dampen
  let kawasaki = 1.0 - abs(sin(baseFold * 0.5)) * 0.35;
  let signFold = select(-1.0, 1.0, rawFold > 0.0);

  // Crease angle with depth-curve distortion
  let foldAngle = (rawFold * foldDepth * kawasaki * (1.0 - dist * 0.8) + mouseFold) * bassEnv;
  let softness = foldSoftness * (1.0 - dist);
  let mask = smoothstep(-softness, 0.0, foldAngle) * smoothstep(softness, 0.0, foldAngle);

  // Temporal fold history for paper memory
  let prevFold = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let persistentMask = mix(mask, prevFold * 0.88, 0.22);

  // Depth controls paper layer ordering and shadow casting
  let inShadow = step(0.0, foldAngle) * step(depth, 0.5);
  let shadowFactor = mix(1.0, 0.55, inShadow);
  let layerHighlight = step(0.0, foldAngle) * step(0.5, depth) * 0.25;

  // Animated fold breathing
  let foldBreath = sin(speed * 0.4 + dist * 4.0) * 0.08;
  let animatedFold = foldAngle + foldBreath;

  // Digital paper texture with fiber direction
  let fiberDir = vec2<f32>(cos(angle), sin(angle));
  let fiber = paperTex(uv, fiberDir);
  let paperColor = vec3<f32>(0.93, 0.91, 0.87) * (1.0 + fiber);

  // Paper fiber shading
  let paperNormal = vec3<f32>(fiberDir * 0.15, 1.0);
  let lightDir = normalize(vec3<f32>(0.3, 0.5, 1.0));
  let paperShade = max(dot(normalize(paperNormal), lightDir), 0.0);
  let shadedPaper = paperColor * (0.4 + paperShade * 0.6);

  // Chromatic folding: R/B sample from different crease depths
  let shift = animatedFold * chromaOffset * bassEnv;
  let rUV = clamp(uv + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + vec2<f32>(0.0, shift * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  // HDR specular on crease highlights
  let creaseHighlight = pow(1.0 - abs(animatedFold) / max(foldDepth, 1e-4), 5.0) * 0.5;

  // Crease normal specular
  let creaseNormal = vec3<f32>(signFold * 0.25, 0.0, 1.0);
  let creaseSpec = pow(max(dot(normalize(creaseNormal), lightDir), 0.0), 10.0) * 0.35;

  // Edge glow along crease
  let edgeGlow = smoothstep(0.0, 0.12, abs(animatedFold)) * 0.08;

  var rgb = vec3<f32>(r, g, b) * shadowFactor * shadedPaper + vec3<f32>(layerHighlight + creaseHighlight + edgeGlow + creaseSpec);

  // Mountain/valley tint
  let mountainValley = signFold * 0.5 + 0.5;
  let origamiTint = mix(vec3<f32>(0.92, 0.90, 0.88), vec3<f32>(0.96, 0.95, 0.93), mountainValley);
  rgb = rgb * origamiTint;

  // Grain and ambient
  let grain = (hash12(uv * 400.0 + time * 0.5) - 0.5) * 0.025;
  let ambient = vec3<f32>(0.06, 0.05, 0.04);
  rgb = rgb + ambient + grain;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, dist) * 0.25;
  rgb = rgb * vignette;

  rgb = acesToneMap(rgb);

  let foldOpacity = clamp(abs(animatedFold) * 1.2 + 0.15, 0.0, 1.0);
  let paperOpacity = 0.9;
  let finalAlpha = clamp(foldOpacity * paperOpacity * depth, 0.08, 0.98);
  let depthLayer = mix(0.25, 0.75, depth);
  let outDepth = clamp(mix(depthLayer, 0.3 + abs(animatedFold) * 0.4, 0.25), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(rgb, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(abs(animatedFold), persistentMask, shadowFactor, finalAlpha));
}
