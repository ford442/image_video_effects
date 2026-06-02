// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: glass-bead-curtain
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(1.0 - abs(cosTheta), 5.0);
}

fn sphereRefract(incident: vec2<f32>, n: vec2<f32>, eta: f32) -> vec2<f32> {
  let cosI = clamp(-dot(incident, n), -1.0, 1.0);
  let sinT2 = eta * eta * (1.0 - cosI * cosI);
  let cosT = sqrt(max(0.0, 1.0 - sinT2));
  return incident * eta + n * (eta * cosI - cosT);
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
  let beadCount = mix(6.0, 32.0, 1.0 - u.zoom_params.x) * (0.5 + depth * 0.5);
  let refraction = u.zoom_params.y * 0.10;
  let interactTension = mix(0.05, 0.45, u.zoom_params.z);
  let density = mix(0.25, 1.0, u.zoom_params.w);

  let curtainUV = vec2<f32>(uv.x * beadCount * aspect, uv.y * beadCount);
  let beadId = floor(curtainUV);
  let beadCenter = beadId + 0.5;
  let beadPhase = hash12(beadId) * 6.28318;

  let windSway = sin(time * (1.2 + bass * 2.5) + beadId.y * 0.35 + beadPhase) * (0.10 + bass * 0.12);
  let neighborLeft = hash22(beadId + vec2<f32>(-1.0, 0.0)).x * 0.06;
  let neighborRight = hash22(beadId + vec2<f32>(1.0, 0.0)).x * 0.06;
  let collisionPush = (neighborLeft - neighborRight) * (1.0 - smoothstep(0.0, 0.5, length((beadCenter / beadCount) - mouse)));
  let verticalCoupling = sin(time * 0.8 + beadId.y * 0.6 + beadId.x * 0.3) * 0.04 * bass;
  let beadLocal = curtainUV - beadCenter + vec2<f32>(windSway + collisionPush, verticalCoupling);
  let beadDist = length(beadLocal);
  let beadMask = 1.0 - smoothstep(0.30, 0.50, beadDist);
  let sphereHeight = sqrt(max(0.0, 1.0 - beadDist * beadDist * 4.0));

  let beadCenterUV = vec2<f32>((beadCenter.x - windSway) / (beadCount * aspect), beadCenter.y / beadCount);
  let pullDelta = (beadCenterUV - mouse) * vec2<f32>(aspect, 1.0);
  let pullDist = length(pullDelta);
  let pull = (1.0 - smoothstep(0.0, 0.40, pullDist)) * interactTension;

  let normal = normalize(beadLocal + normalize(pullDelta + vec2<f32>(0.001, 0.0)) * pull);
  let viewDir = vec2<f32>(0.0, 1.0);
  let cosTheta = max(0.0, dot(normal, viewDir));
  let f0 = 0.04;
  let fresnel = fresnelSchlick(cosTheta, f0);

  let etaGlass = 1.5;
  let etaAir = 1.0;
  let etaRatio = etaAir / etaGlass;
  let refractDir = sphereRefract(viewDir, normal, etaRatio);

  let chromatic = vec3<f32>(1.00, 0.97, 0.94);
  let rOff = refractDir * refraction * chromatic.r * beadMask * (1.0 + treble * 0.9);
  let gOff = refractDir * refraction * chromatic.g * beadMask * (1.0 + treble * 0.6);
  let bOff = refractDir * refraction * chromatic.b * beadMask * (1.0 + treble * 0.3);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(uv + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var refracted = vec3<f32>(sampleR, sampleG, sampleB);

  let causticFocus = pow(max(0.0, 1.0 - beadDist * 2.2), 4.0);
  let causticPattern = pow(sin(beadLocal.x * 18.0 + beadLocal.y * 14.0 + time * 2.5 + beadPhase) * 0.5 + 0.5, 5.0);
  let causticRing = pow(sin(beadDist * 12.0 - time * 1.5) * 0.5 + 0.5, 3.0);
  let causticIntensity = causticFocus * (causticPattern * 0.6 + causticRing * 0.4) * (0.35 + mids * 0.65) * beadMask;

  let sssColor = mix(vec3<f32>(0.95, 0.35, 0.15), vec3<f32>(0.12, 0.60, 0.95), hash12(beadId));
  let sss = sssColor * causticIntensity * density * 0.55;

  let specAngle = max(0.0, dot(normal, vec2<f32>(0.25, 0.75)));
  let specularSharp = pow(specAngle, 64.0) * (0.25 + treble * 0.45) * beadMask * fresnel;
  let specularBroad = pow(specAngle, 8.0) * 0.15 * beadMask * (1.0 - fresnel);
  let specular = specularSharp + specularBroad;

  let envReflect = pow(max(0.0, normal.y), 2.0) * 0.15 * fresnel * beadMask;

  var finalColor = refracted * (1.0 - fresnel * beadMask * density * 0.8) + sss;
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * specular;
  finalColor = finalColor + vec3<f32>(0.7, 0.8, 0.9) * envReflect;
  finalColor = finalColor + vec3<f32>(0.25, 0.55, 0.9) * causticIntensity * 0.35 * density;

  let sparkle = pow(max(0.0, 1.0 - beadDist * 1.7), 6.0) * (0.15 + treble * 0.4);
  finalColor = finalColor + vec3<f32>(0.85, 0.92, 1.0) * sparkle;

  finalColor = acesTonemap(finalColor * 1.15);

  let causticAlpha = causticIntensity * 0.75 + sparkle * 0.25 + beadMask * 0.15;
  let finalAlpha = clamp(beadMask * density * causticAlpha + beadMask * density * 0.25, 0.12, 0.92) * depth;

  let depthOut = clamp(mix(depth, depth * 0.25 + beadMask * sphereHeight * 0.75, 0.42), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(beadMask, causticIntensity, fresnel, finalAlpha));
}
