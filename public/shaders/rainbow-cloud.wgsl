// ═══════════════════════════════════════════════════════════════════
//  Rainbow Cloud v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, volumetric-cloud, mie-scattering, upgraded-rgba
//  Complexity: Very High
//  Chunks From: rainbow-cloud, volumetric-raymarch, aces-tonemap
//  Created: 2026-05-31
//  Upgraded: 2026-05-31
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

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

fn noise3d(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash12(vec2(n, n + 1.0)), hash12(vec2(n + 57.0, n + 58.0)), u.x),
        mix(hash12(vec2(n + 113.0, n + 114.0)), hash12(vec2(n + 170.0, n + 171.0)), u.x), u.y),
    mix(mix(hash12(vec2(n + 1.0, n + 2.0)), hash12(vec2(n + 58.0, n + 59.0)), u.x),
        mix(hash12(vec2(n + 114.0, n + 115.0)), hash12(vec2(n + 171.0, n + 172.0)), u.x), u.y), u.z
  );
}

fn fbm3d(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + noise3d(f) * a;
    f = f * 2.03 + vec3(1.7, 3.1, 5.3);
    a = a * 0.5;
  }
  return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let cloudScale = mix(1.0, 6.0, u.zoom_params.x);
  let driftSpeed = mix(0.02, 0.3, u.zoom_params.y);
  let densityParam = mix(0.15, 0.9, u.zoom_params.z);
  let iridescence = mix(0.1, 1.0, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.3, 1.0, depth);

  // Ray direction and origin for volumetric march
  let aspect = dims.x / dims.y;
  let ro = vec3(uv.x * aspect, uv.y, 0.0);
  let rd = vec3(0.0, 0.0, 1.0);
  let lightDir = normalize(vec3(0.3, 0.5, 1.0));

  // Bass drives turbulence
  let turbulence = 1.0 + bass * 0.6;

  // Mouse scatters cloud particles
  let mouseScatter = 1.0 - smoothstep(0.0, 0.5, length(uv - mouse));

  var transmittance = 1.0;
  var scatteredLight = vec3(0.0);
  var totalDensity = 0.0;
  let steps = 10;
  let stepSize = 1.0 / f32(steps);

  for (var i = 0; i < steps; i = i + 1) {
    let t = f32(i) * stepSize;
    let pos = ro + rd * t;
    let cloudUV = pos * cloudScale + vec3(time * driftSpeed, time * driftSpeed * 0.3, time * driftSpeed * 0.1);
    let turbPos = cloudUV * turbulence + mouseScatter * 0.4;
    let d = fbm3d(turbPos) * densityParam * depthFactor;

    // Cloud density with soft edges
    let density = max(d - 0.35, 0.0) * 2.5;

    // Mie scattering approximation (forward-peaked)
    let cosTheta = dot(rd, lightDir);
    let miePhase = (1.0 + cosTheta * cosTheta) * 0.5;
    let lightAtten = exp(-density * 3.0);

    // Iridescent cloud colors (nacreous / polar stratospheric)
    let hue = density * 2.0 + t * 0.8 + time * 0.06 + mids * 0.2;
    let iridColor = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.25, 0.5) + hue));

    // HDR god rays through cloud gaps
    let godRay = smoothstep(0.05, 0.25, density) * (1.0 - lightAtten) * miePhase;
    let lightColor = vec3(1.0, 0.95, 0.85) * godRay * 2.0 + iridColor * density * iridescence;

    scatteredLight = scatteredLight + lightColor * density * transmittance * stepSize;
    transmittance = transmittance * (1.0 - density * stepSize);
    totalDensity = totalDensity + density;
  }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = src.rgb * transmittance + scatteredLight;

  // Atmospheric perspective
  let atmFog = vec3(0.15, 0.18, 0.25) * (1.0 - depthFactor);
  color = mix(color, atmFog, 0.15);

  // ACES tone mapping
  color = aces(color * 1.1);

  let cloudDensity = clamp(totalDensity * 0.15, 0.0, 1.0);
  let alpha = clamp(cloudDensity * iridescence * depthFactor, 0.03, 0.95);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4(cloudDensity, iridescence, depthFactor, alpha));
}
