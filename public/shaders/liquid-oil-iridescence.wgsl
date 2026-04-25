// ═══════════════════════════════════════════════════════════════════
//  liquid-oil-iridescence
//  Category: advanced-hybrid
//  Features: liquid-oil, thin-film-interference, depth-aware, spectral-render
//  Complexity: High
//  Chunks From: liquid-oil.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Oil slick swirls meet thin-film interference. Mouse stirs viscous
//  oil while film thickness varies with depth and noise, producing
//  physically-based iridescent colors via optical path difference.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: noise2D + flowPattern (from liquid-oil.wgsl) ═══
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise2D(p: vec2<f32>) -> vec2<f32> {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash2(i);
  let b = hash2(i + vec2<f32>(1.0, 0.0));
  let c = hash2(i + vec2<f32>(0.0, 1.0));
  let d = hash2(i + vec2<f32>(1.0, 1.0));
  let h = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  return vec2<f32>(cos(h * 6.283), sin(h * 6.283));
}

fn flowPattern(p: vec2<f32>, time: f32) -> vec2<f32> {
  var flow = vec2<f32>(0.0);
  var amplitude = 1.0;
  var frequency = 1.0;
  for (var i = 0; i < 3; i++) {
    flow += noise2D(p * frequency + time * 0.1) * amplitude;
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return flow;
}

// ═══ CHUNK: schlickFresnel (from liquid-oil.wgsl) ═══
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: thinFilmColor (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  let viscosity = u.zoom_params.x;
  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
  let intensity = mix(0.3, 1.5, u.zoom_params.z);
  let turbulence = u.zoom_params.w;

  // --- Liquid Oil: Swirl Flow ---
  let time = currentTime * 0.05 * (0.5 + viscosity);
  let noiseuv = uv * 3.0;
  var flow = flowPattern(noiseuv, time);
  let ambientDisplacement = flow * 0.01;

  // Mouse stir
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let stir = vec2<f32>(-direction_vec.y, direction_vec.x);
        let wave = sin(dist * 10.0 - timeSinceClick * 1.5);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        mouseDisplacement += stir * wave * 0.02 * attenuation;
      }
    }
  }

  let totalDisplacement = ambientDisplacement + mouseDisplacement;
  let displacedUV = uv + totalDisplacement;

  // Sample base color
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // --- Iridescence Engine: Thin-Film ---
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let filmThicknessBase = mix(200.0, 800.0, viscosity);
  let noiseVal = hash12(uv * 12.0 + currentTime * 0.1) * 0.5
               + hash12(uv * 25.0 - currentTime * 0.15) * 0.25;

  var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

  // Mouse interaction: local thickness perturbation
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  if (isMouseDown) {
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
    thickness += mouseInfluence * 300.0 * sin(currentTime * 3.0 + mouseDist * 30.0);
  }

  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

  // Oil absorption: thicker = more opaque, yellowish
  let displacementMag = length(totalDisplacement);
  let oilThickness = displacementMag * 8.0 + 0.15;
  let absorptionR = exp(-oilThickness * 0.5);
  let absorptionG = exp(-oilThickness * 0.8);
  let absorptionB = exp(-oilThickness * 1.3);
  let absorbed = vec3<f32>(
    baseColor.r * absorptionR,
    baseColor.g * absorptionG,
    baseColor.b * absorptionB
  );

  // Combine oil color with iridescence
  let fresnel = pow(1.0 - cosTheta, 3.0);
  let oilTint = mix(absorbed, iridescent, 0.2);
  let goldenSheen = vec3<f32>(0.3, 0.25, 0.1) * displacementMag * 2.0;
  let outColor = mix(oilTint + goldenSheen, iridescent, fresnel * 0.6);

  let tonemapped = outColor / (1.0 + outColor * 0.2);

  // Alpha: oil physics
  let normal = normalize(vec3<f32>(
    -totalDisplacement.x * 20.0,
    -totalDisplacement.y * 20.0,
    1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  let F0 = 0.05;
  let fresnelAlpha = schlickFresnel(max(0.0, viewDotNormal), F0);
  let absorptionAlpha = exp(-oilThickness * 1.2);
  let interferenceAlpha = mix(0.6, 0.9, absorptionAlpha);
  let alpha = interferenceAlpha * (1.0 - fresnelAlpha * 0.35);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tonemapped, clamp(alpha, 0.0, 1.0)));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(iridescent, thickness / 1000.0));

  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
