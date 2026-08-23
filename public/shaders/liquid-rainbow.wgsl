// ═══════════════════════════════════════════════════════════════════
//  Liquid Rainbow (Deep-polished Batch 59; Batch 51 wave foundation)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  A/C packing: display RGBA exact-load history. B/extraBuffer unused.
//  Upgraded: 2026-08-23
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

fn spectralPalette(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 * (t + vec3<f32>(0.0, 0.333, 0.667)));
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Trochoidal Gerstner wave displacement
fn trochoidalWave(p: vec2<f32>, dir: vec2<f32>, k: f32, amp: f32, speed: f32, time: f32) -> vec3<f32> {
  let phase = dot(dir, p) * k - time * speed;
  let s = sin(phase);
  let c = cos(phase);
  // Returns (dx, dy, dz_height)
  return vec3<f32>(-dir.x * amp * s, -dir.y * amp * s, amp * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.18, 0.94, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.003, 0.042, u.zoom_params.z);
  let dispersion = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Dual continuous motion: Trochoidal Gerstner wave array + ambient vortex drift
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let wave1 = trochoidalWave(pAspect, normalize(vec2<f32>(1.0, 0.6)), 12.0 + turbulence * 14.0, 0.003 * depthFactor, 4.2 + audio.x * 3.0, time);
  let wave2 = trochoidalWave(pAspect, normalize(vec2<f32>(-0.7, 1.0)), 18.0 + turbulence * 18.0, 0.002 * depthFactor, 5.1 + audio.y * 3.4, time);
  let wave3 = trochoidalWave(pAspect, normalize(vec2<f32>(0.35, -1.0)), 27.0 + turbulence * 11.0, 0.0014 * depthFactor, 7.0 + audio.z * 4.0, time);

  let braidA = sin(pAspect.x * 15.0 + sin(pAspect.y * 7.0 - time * 3.5) * 2.0 - time * 6.0);
  let braidB = cos(pAspect.y * 18.0 + sin(pAspect.x * 9.0 + time * 4.0) * 1.7 + time * 7.2);
  let braidFlow = vec2<f32>(braidA, braidB) * (0.0012 + turbulence * 0.0025);
  var totalDisp = (wave1.xy + wave2.xy + wave3.xy + braidFlow) * mix(1.25, 0.55, viscosity);
  var waveCrest = (wave1.z + wave2.z + wave3.z) * 150.0 + (braidA + braidB) * 0.3;

  // Interactive pointer drag / vortex shear
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * mix(8.0, 3.5, viscosity));
  let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  let dragForce = dragTangent * dragCore * (0.008 + turbulence * 0.015) * (1.0 + isMouseDown * 2.2);
  totalDisp += vec2<f32>(dragForce.x / aspect, dragForce.y);

  // 50-ripple shockwaves with dispersion
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 3.5) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let life = 1.0 - smoothstep(0.0, 3.5, age);
      let kWave = sin(rDist * (26.0 + turbulence * 22.0) - age * (4.0 + audio.x * 6.5));
      let envelope = exp(-rDist * mix(10.0, 4.0, viscosity)) * life;
      let rDisp = rDir * kWave * envelope * rippleStrength * (1.0 + audio.x * 0.75);

      totalDisp += vec2<f32>(rDisp.x / aspect, rDisp.y);
      waveCrest += pow(max(kWave, 0.0), 3.5) * envelope * 12.0;
    }
  }

  // 2.5D surface normal & Fresnel rim
  let normal = normalize(vec3<f32>(-totalDisp.x * 36.0, -totalDisp.y * 36.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.038);

  // Thin-film interference phase calculation
  let filmAngle = time * (1.8 + audio.y * 1.4) + dot(uv, vec2<f32>(7.0, 11.0)) + braidA * 0.45;
  let filmThickness = waveCrest * 0.15 + length(totalDisp) * 12.0 + dispersion * 0.5;
  let phaseShift = filmThickness + filmAngle * 0.1;
  let iridescentColor = spectralPalette(fract(phaseShift));

  // Chromatic dispersion splitting for R, G, B channels
  let dispDir = totalDisp / max(length(totalDisp), 0.0001);
  let spectralSpread = dispDir * (0.0012 + dispersion * 0.02 + audio.z * 0.005);
  let baseUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  let uvR = clamp(baseUV + spectralSpread, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = baseUV;
  let uvB = clamp(baseUV - spectralSpread, vec2<f32>(0.0), vec2<f32>(1.0));

  let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(uvG * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  let spectralMask = clamp(waveCrest * 0.18 + fresnel * (0.6 + dispersion * 0.8), 0.0, 1.0);
  let sampledRGB = vec3<f32>(cR.r, cG.g, cB.b);
  var rgb = mix(sampledRGB, sampledRGB * (0.7 + iridescentColor * 0.9), spectralMask);
  rgb += iridescentColor * fresnel * (0.18 + audio.z * 0.35);

  let feedbackMix = clamp((0.08 + viscosity * 0.2) * history.a, 0.04, 0.32);
  rgb = mix(rgb, history.rgb, feedbackMix);
  rgb = acesToneMapping(rgb);

  let sourceAlpha = max(cR.a, max(cG.a, cB.a));
  let alpha = clamp(sourceAlpha * (0.84 + viscosity * 0.16) + spectralMask * 0.16 + fresnel * 0.1, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r;
  let outDepth = clamp(displacedDepth + waveCrest * 0.02 - length(totalDisp) * 0.15, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
