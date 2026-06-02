// ═══════════════════════════════════════════════════════════════════
//  Liquid Lens v2
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: snell-law, chromatic-dispersion, caustics
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Refraction, y=Radius, z=Dispersion, w=SurfaceWave
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ═══ CHUNK: snell_refraction ═══
fn snellRefraction(I: vec3<f32>, N: vec3<f32>, n1: f32, n2: f32) -> vec3<f32> {
  let eta = n1 / n2;
  let cosI = dot(-I, N);
  let sinT2 = eta * eta * (1.0 - cosI * cosI);
  if (sinT2 > 1.0) {
    return reflect(I, N);
  }
  let cosT = sqrt(1.0 - sinT2);
  return eta * I + (eta * cosI - cosT) * N;
}

// ═══ CHUNK: spectral_sample ═══
fn spectralRefract(uv: vec2<f32>, N: vec3<f32>, nBase: f32, dispersion: f32) -> vec3<f32> {
  let I = vec3(0.0, 0.0, -1.0);
  let rUV = uv + snellRefraction(I, N, 1.0, nBase - dispersion * 0.04).xy * 0.05;
  let gUV = uv + snellRefraction(I, N, 1.0, nBase).xy * 0.05;
  let bUV = uv + snellRefraction(I, N, 1.0, nBase + dispersion * 0.04).xy * 0.05;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2(0.0), vec2(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2(0.0), vec2(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2(0.0), vec2(1.0)), 0.0).b;
  return vec3(r, g, b);
}

// ═══ CHUNK: fresnel_reflectance ═══
fn fresnelReflectance(cosTheta: f32, n1: f32, n2: f32) -> f32 {
  let R0 = pow((n1 - n2) / (n1 + n2), 2.0);
  return R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: caustic_highlight ═══
fn causticHighlight(dist: f32, time: f32, mask: f32, intensity: f32) -> f32 {
  let c1 = pow(max(0.0, sin(dist * 25.0 - time * 3.0)), 6.0);
  let c2 = pow(max(0.0, sin(dist * 40.0 + time * 2.0)), 10.0);
  return (c1 * 0.6 + c2 * 0.4) * mask * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let strength = u.zoom_params.x * (1.0 + bass * 0.2);
  let radius = u.zoom_params.y;
  let dispersion = u.zoom_params.z;
  let surfaceWave = u.zoom_params.w;

  let uvCorrected = vec2(uv.x * aspect, uv.y);
  let mouseCorrected = vec2(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  let waveH = sin(dist * 20.0 - u.config.x * 3.0) * surfaceWave * 0.02 * (1.0 + bass * 0.3);
  let deformedDist = dist + waveH;

  let lensMask = smoothstep(radius, radius * 0.7, deformedDist);
  let h = sqrt(max(0.0, radius * radius - deformedDist * deformedDist)) + waveH;
  let nd = deformedDist / max(radius, 0.001);

  let nBase = 1.33 + depth * 0.2 * strength;
  let lensThickness = h / max(radius, 0.001);

  let N = normalize(vec3(
    (uvCorrected - mouseCorrected) / max(radius, 0.001),
    lensThickness * 2.0
  ));
  let I = vec3(0.0, 0.0, -1.0);
  let cosTheta = max(0.0, dot(-I, N));

  let refracted = spectralRefract(uv, N, nBase, dispersion * strength);
  let fresnel = fresnelReflectance(cosTheta, 1.0, nBase);

  let caustic = causticHighlight(deformedDist, u.config.x, lensMask, dispersion * strength);

  let specDir = normalize(vec3(-0.3, -0.3, 1.0));
  let spec = pow(max(0.0, dot(N, specDir)), 30.0) * lensMask * 0.4;

  let rim = smoothstep(radius * 0.8, radius, deformedDist);
  let isInside = deformedDist < radius;
  let edgeDarken = 1.0 - rim * 0.4;

  let reflectionColor = vec3(0.6, 0.7, 0.8) * fresnel * lensMask;
  let surfaceNoise = hash21(uv * 300.0 + u.config.x) * 0.02 * lensMask;
  let finalColor = refracted * edgeDarken * (1.0 - fresnel) + reflectionColor + spec + caustic + surfaceNoise;
  let tonemapped = aces_tonemap(finalColor);

  let alpha = clamp(lensThickness * fresnel * lensMask * 2.0, 0.0, 1.0);
  let outCol = vec4(tonemapped, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
