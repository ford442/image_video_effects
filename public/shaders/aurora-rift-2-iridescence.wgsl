// ═══════════════════════════════════════════════════════════════════
//  aurora-rift-2-iridescence
//  Category: advanced-hybrid
//  Features: thin-film-interference, aurora, volumetric, depth-aware,
//            spectral-render, mouse-driven, HDR
//  Complexity: Very High
//  Chunks From: aurora-rift-2 (aurora curtains, Beer's Law,
//               physical transmittance, multi-layer volumetric),
//               spec-iridescence-engine (thin-film interference,
//               wavelength-to-RGB, Fresnel blend)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Iridescent aurora curtains: thin-film interference replaces simple
//  spectral coloring in each aurora layer. Optical depth from the
//  aurora simulation modulates film thickness, creating oil-slick
//  and soap-bubble colors that shift with viewing angle. Beer's Law
//  transmittance composites layers physically. Mouse click creates
//  local thickness perturbations.
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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

// ═══ CHUNK: physical transmittance (from aurora-rift-2) ═══
fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
  let transmittance = exp(-absorptionCoeff * opticalDepth);
  return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
  return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAlpha = mix(0.3, 1.0, depth);
  return mix(1.0, depthAlpha, depthWeight);
}

fn calculateAtmosphericAlpha(uv: vec2<f32>, opticalDepth: f32, density: f32, params: vec4<f32>) -> f32 {
  let volAlpha = volumetricAlpha(density, opticalDepth);
  let depthAlpha = depthLayeredAlpha(uv, params.z);
  return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

// ═══ CHUNK: thin-film interference (from spec-iridescence-engine) ═══
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
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 25.0) {
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
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);

  // Parameters
  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y * 2.0 + 0.5;
  let depthWeight = u.zoom_params.z;
  let turbulence = u.zoom_params.w * 3.0 + 1.0;

  // Iridescence parameters
  let filmThicknessBase = mix(200.0, 800.0, 0.3 + intensity * 0.4);
  let filmIOR = mix(1.2, 2.4, 0.3 + turbulence * 0.2);
  let iridIntensity = mix(0.4, 1.8, intensity);

  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Viewing angle from pixel position
  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));
  let fresnel = pow(1.0 - cosTheta, 3.0);

  // Aurora curtain simulation
  let curtainUV = uv * vec2<f32>(3.0, 1.0);
  var accumulatedLight = vec3<f32>(0.0);
  var accumulatedOpticalDepth = 0.0;

  for (var i: i32 = 0; i < 5; i++) {
    let layer = f32(i);
    let layerOffset = vec2<f32>(time * speed * 0.1 * (1.0 + layer * 0.1), 0.0);

    // FBM for curtain shape
    let n1 = fbm(curtainUV + layerOffset + vec2<f32>(layer * 10.0), 4);
    let n2 = fbm(curtainUV * 2.0 - layerOffset * 0.5 + vec2<f32>(layer * 5.0), 3);

    // Curtain shape
    let curtainY = 0.3 + n1 * 0.4 + n2 * 0.2;
    let curtainWidth = 0.15 + n2 * 0.1;

    // Distance from curtain center
    let distFromCurtain = abs(uv.y - curtainY);
    let curtainIntensity = smoothstep(curtainWidth, 0.0, distFromCurtain);

    // Optical depth for this layer
    let layerOpticalDepth = curtainIntensity * (0.2 + n1 * 0.3);

    // ═══ IRIDESCENT COLORING PER LAYER ═══
    // Film thickness varies with depth + layer + animated noise
    let noiseVal = hash12(uv * 12.0 + layer * 7.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - layer * 3.0 - time * 0.15) * 0.25;

    var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence + layer * 0.15);

    // Mouse interaction: local thickness perturbation
    if (isMouseDown) {
      let mouseDist = length(uv - mousePos);
      let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
      thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

    // Accumulate with Beer's Law
    let transmittance = exp(-accumulatedOpticalDepth * 2.0);
    accumulatedLight += iridescent * layerOpticalDepth * transmittance;
    accumulatedOpticalDepth += layerOpticalDepth;
  }

  // Sample background
  let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Apply aurora with physical transmittance
  let absorptionCoeff = vec3<f32>(0.5, 0.3, 0.8);
  let transmitted = physicalTransmittance(bgSample.rgb, accumulatedOpticalDepth, absorptionCoeff);

  // Final composite: transmitted background + accumulated iridescent light
  var finalColor = transmitted + accumulatedLight;

  // Fresnel-like rim glow from iridescence
  let rimIrid = thinFilmColor(filmThicknessBase * 1.2, cosTheta, filmIOR) * fresnel * 0.5;
  finalColor += rimIrid;

  // HDR tone map
  finalColor = finalColor / (1.0 + finalColor * 0.2);

  // Alpha
  let density = accumulatedOpticalDepth * 2.0;
  let alpha = calculateAtmosphericAlpha(uv, accumulatedOpticalDepth, density, u.zoom_params);

  textureStore(writeTexture, id, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));

  // Store iridescent color for downstream
  textureStore(dataTextureA, id, vec4<f32>(accumulatedLight, accumulatedOpticalDepth));
}
