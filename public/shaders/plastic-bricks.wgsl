// ═══════════════════════════════════════════════════════════════════
//  Plastic Bricks v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: plastic-bricks
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(173.3, 251.9))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn plasticBRDF(lightDir: vec2<f32>, viewDir: vec2<f32>, normal: vec2<f32>, roughness: f32) -> f32 {
  let h = normalize(lightDir + viewDir);
  let ndotl = max(dot(normal, lightDir), 0.0);
  let ndoth = max(dot(normal, h), 0.0);
  let spec = pow(ndoth, mix(4.0, 128.0, 1.0 - roughness));
  return ndotl * 0.6 + spec * 0.4;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let density = mix(4.0, 28.0, u.zoom_params.x) * (0.5 + depth * 0.5);
  let studSize = mix(0.08, 0.36, u.zoom_params.y);
  let relief = mix(0.04, 0.38, u.zoom_params.z);
  let bevel = mix(0.01, 0.16, u.zoom_params.w);

  var brickUV = uv * density;
  let rowPhase = floor(brickUV.y);
  if (fract(rowPhase * 0.5) >= 0.5) {
    brickUV.x = brickUV.x + 0.5;
  }
  let brickId = floor(brickUV);
  let cell = fract(brickUV) - 0.5;

  let assemblyWave = sin(time * 2.0 + bass * 4.0 + brickId.x * 0.3 + brickId.y * 0.2) * 0.5 + 0.5;
  let assemblyMask = smoothstep(0.0, 0.3, assemblyWave);

  let mortar = smoothstep(0.44, 0.50, max(abs(cell.x), abs(cell.y)));
  let studDist = length(cell);
  let studMask = 1.0 - smoothstep(studSize, studSize + bevel, studDist);
  let bodyMask = 1.0 - mortar;

  let studCavityAO = 1.0 - smoothstep(0.0, studSize * 1.5, studDist) * 0.35;
  let cornerAO = smoothstep(0.5, 0.35, max(abs(cell.x), abs(cell.y))) * 0.25;

  let centerUV = clamp((brickId + 0.5) / density, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).rgb;

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mousePush = 1.0 - smoothstep(0.0, 0.35, mouseDist);
  let deconstruct = mousePush * 0.4;

  let huePulse = hash12(brickId + vec2<f32>(floor(time), 0.0));
  let toyTint = mix(vec3<f32>(1.0, 0.22, 0.15), vec3<f32>(0.05, 0.72, 1.0), huePulse + treble * 0.25);
  let translucent = hash12(brickId + vec2<f32>(0.0, 1.0)) > 0.7;

  let lightDir = normalize(vec2<f32>(0.3, 0.7));
  let viewDir = vec2<f32>(0.0, 1.0);
  let brickNormal = normalize(cell + vec2<f32>(0.0, 0.15));
  let studNormal = normalize(cell * vec2<f32>(1.0, 0.6) + vec2<f32>(0.0, 0.25));

  let bodyBRDF = plasticBRDF(lightDir, viewDir, brickNormal, 0.35) * bodyMask;
  let studBRDF = plasticBRDF(lightDir, viewDir, studNormal, 0.15) * studMask;
  let plasticGloss = bodyBRDF + studBRDF * 1.5;

  let fingerprint = hash22(cell * 50.0).x * 0.08 * bodyMask;
  let smudge = vec3<f32>(0.92, 0.92, 0.90) * fingerprint;

  var finalColor = mix(baseColor, toyTint, 0.25 * bodyMask + 0.2 * studMask);
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * plasticGloss * (0.25 + mids * 0.2);
  finalColor = finalColor + smudge;

  let sss = select(vec3<f32>(0.0), toyTint * 0.35 * bodyBRDF, translucent);
  finalColor = finalColor + sss;

  let reliefMask = clamp(bodyMask * relief + studMask * (relief + 0.3), 0.0, 1.0);
  let ao = studCavityAO * (1.0 - cornerAO);
  finalColor = finalColor * ao;

  let depthOut = clamp(mix(depth, 0.18 + reliefMask * 0.78 + deconstruct * 0.05, 0.4), 0.0, 1.0);

  finalColor = mix(finalColor, finalColor * (1.0 - deconstruct), deconstruct);
  finalColor = acesTonemap(finalColor * 1.1);

  let plasticAlpha = clamp(0.65 + reliefMask * 0.2 + plasticGloss * 0.15, 0.42, 0.96);
  let finalAlpha = plasticAlpha * plasticGloss * depth;

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(studMask, bodyMask, plasticGloss, finalAlpha));
}
