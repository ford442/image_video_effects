// ═══════════════════════════════════════════════════════════════════
//  Liquid RGB (Upgraded Batch 51)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-15
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

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Complex potential vortex superposition: sum of i*Gamma / (2*pi * (z - z_k))
fn complexVortexField(p: vec2<f32>, time: f32, turb: f32) -> vec2<f32> {
  var vel = vec2<f32>(0.0);
  let vortexCenters = array<vec2<f32>, 4>(
    vec2<f32>(0.35 * cos(time * 0.45), 0.25 * sin(time * 0.55)),
    vec2<f32>(-0.4 * sin(time * 0.38), 0.3 * cos(time * 0.42)),
    vec2<f32>(0.28 * sin(time * 0.62), -0.35 * cos(time * 0.51)),
    vec2<f32>(-0.32 * cos(time * 0.53), -0.28 * sin(time * 0.67))
  );
  let circulations = array<f32, 4>(1.0, -1.2, 0.85, -0.95);

  for (var k = 0; k < 4; k = k + 1) {
    let delta = p - vortexCenters[k];
    let r2 = dot(delta, delta) + 0.04;
    let gamma = circulations[k] * (0.8 + turb * 1.5);
    // u = -Gamma * delta.y / (2*pi*r2), v = Gamma * delta.x / (2*pi*r2)
    vel += vec2<f32>(-delta.y, delta.x) * (gamma / (6.28318 * r2));
  }
  return vel * 0.004;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.15, 0.95, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.003, 0.042, u.zoom_params.z);
  let separation = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Complex potential vortex stream + harmonic wave drift
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let vortexFlow = complexVortexField(pAspect, time, turbulence) * depthFactor * mix(1.3, 0.6, viscosity);
  let driftWave = vec2<f32>(
    sin(pAspect.y * (9.0 + turbulence * 12.0) + time * 0.75 + audio.y * 1.5),
    cos(pAspect.x * (8.0 + turbulence * 10.0) - time * 0.65 + audio.x * 1.2)
  ) * (0.0012 + turbulence * 0.0028) * depthFactor;

  var totalDisp = vortexFlow + driftWave;
  var causticPotential = 0.0;

  // Interactive pointer drag / vortex shear
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragEnvelope = exp(-mouseDist * mix(8.0, 4.0, viscosity));
  let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  let dragForce = dragTangent * dragEnvelope * (0.007 + turbulence * 0.014) * (1.0 + isMouseDown * 2.2);
  totalDisp += vec2<f32>(dragForce.x / aspect, dragForce.y);

  // 50-ripple shockwave fronts with frequency-dependent damping
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 3.2) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let life = 1.0 - smoothstep(0.0, 3.2, age);
      let kWave = sin(rDist * (32.0 + turbulence * 18.0) - age * (5.0 + audio.x * 7.0));
      let envelope = exp(-rDist * mix(12.0, 4.5, viscosity)) * life;
      let waveDisp = rDir * kWave * envelope * rippleStrength * (1.0 + audio.x * 0.7);

      totalDisp += vec2<f32>(waveDisp.x / aspect, waveDisp.y);
      causticPotential += pow(max(kWave, 0.0), 4.5) * envelope;
    }
  }

  // Cauchy chromatic refraction split: R (long), G (mid), B (short)
  let dispMag = length(totalDisp);
  let cauchyBase = 0.002 + separation * 0.024 + audio.y * 0.008;
  let splitVector = totalDisp * (1.0 + separation * 4.0 + audio.z * 1.5);
  let rOffset = totalDisp + splitVector * (cauchyBase * 1.25);
  let gOffset = totalDisp;
  let bOffset = totalDisp - splitVector * (cauchyBase * 1.45);

  let uvR = clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + gOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(uvG * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // 2.5D normal field & optical Beer-Lambert absorption
  let normal = normalize(vec3<f32>(-totalDisp.x * 32.0, -totalDisp.y * 32.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.035);

  let fluidThickness = dispMag * (22.0 + viscosity * 35.0) + causticPotential * 0.15;
  let absorption = exp(-fluidThickness * vec3<f32>(0.65, 0.95, 1.35));
  var rgb = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) * absorption;

  // Caustic prismatic specular highlight
  let causticHue = vec3<f32>(1.0, 0.45 + separation * 0.35, 0.85);
  let specular = causticHue * causticPotential * (0.15 + audio.z * 0.45) + fresnel * vec3<f32>(0.08, 0.16, 0.24);
  rgb += specular;

  let feedbackMix = clamp((0.08 + viscosity * 0.22) * history.a, 0.04, 0.35);
  rgb = mix(rgb, history.rgb, feedbackMix);
  rgb = acesToneMapping(rgb);

  let sourceAlpha = max(sampleR.a, max(sampleG.a, sampleB.a));
  let alpha = clamp(sourceAlpha * mix(0.82, 0.98, viscosity) + fresnel * 0.12 + causticPotential * 0.15, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
  let outDepth = clamp(displacedDepth + causticPotential * 0.04 - dispMag * 0.18, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
