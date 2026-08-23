// ═══════════════════════════════════════════════════════════════════
//  Liquid Fast (Upgraded Batch 51)
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

// Analytical Hamiltonian streamfunction: u = dPsi/dy, v = -dPsi/dx (guarantees div u = 0)
fn streamVelocity(p: vec2<f32>, time: f32, turb: f32) -> vec2<f32> {
  let k1 = 5.0 + turb * 8.0;
  let k2 = 4.5 + turb * 7.0;
  let k3 = 8.0 + turb * 12.0;
  let w1 = time * 0.85;
  let w2 = time * 0.65;
  let w3 = time * 1.15;
  
  // Psi(x,y) = sin(k1*x + w1)*cos(k2*y - w2) + 0.4*cos(k3*x + k2*y + w3)
  // dPsi/dy = -k2*sin(k1*x + w1)*sin(k2*y - w2) - 0.4*k2*sin(k3*x + k2*y + w3)
  // -dPsi/dx = -k1*cos(k1*x + w1)*cos(k2*y - w2) + 0.4*k3*sin(k3*x + k2*y + w3)
  let u_vel = -k2 * sin(p.x * k1 + w1) * sin(p.y * k2 - w2) - 0.4 * k2 * sin(p.x * k3 + p.y * k2 + w3);
  let v_vel = -k1 * cos(p.x * k1 + w1) * cos(p.y * k2 - w2) + 0.4 * k3 * sin(p.x * k3 + p.y * k2 + w3);
  return vec2<f32>(u_vel, v_vel) * 0.0035;
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

  let response = mix(0.4, 1.8, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.004, 0.045, u.zoom_params.z);
  let highlightShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Dual continuous motion: Primary Hamiltonian stream + Secondary convective shear
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let streamFlow = streamVelocity(pAspect, time * response, turbulence) * depthFactor;
  let convectiveShear = vec2<f32>(
    sin(pAspect.y * 14.0 + time * (1.2 * response) + audio.y * 2.0),
    cos(pAspect.x * 12.0 - time * (0.9 * response) + audio.x * 1.5)
  ) * (0.0015 + turbulence * 0.003) * depthFactor;

  var totalDisp = streamFlow + convectiveShear;
  var waveElevation = 0.0;
  var kineticEnergy = length(totalDisp);

  // Interactive pointer drag / vortex circulation
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * 7.5);
  let vortexTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  let dragWake = vortexTangent * dragCore * (0.008 + turbulence * 0.015) * (1.0 + isMouseDown * 2.5);
  totalDisp += vec2<f32>(dragWake.x / aspect, dragWake.y);

  // Capped ripple shockwaves with radial wave packet dispersion
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 2.5) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let life = 1.0 - smoothstep(0.0, 2.5, age);
      let freq = mix(28.0, 56.0, turbulence);
      let kWave = sin(rDist * freq - age * (14.0 + audio.x * 12.0 * response));
      let envelope = exp(-rDist * (8.0 - turbulence * 3.0)) * life;
      let elevation = kWave * envelope;
      
      totalDisp += vec2<f32>(rDir.x / aspect, rDir.y) * elevation * rippleStrength * (1.0 + audio.x * 0.85);
      waveElevation += elevation;
      kineticEnergy += abs(elevation);
    }
  }

  // 2.5D Surface height-field normal via central difference approximations
  let hL = sin((uv.x - texel.x) * 35.0 + time * response) * 0.02 + waveElevation;
  let hR = sin((uv.x + texel.x) * 35.0 + time * response) * 0.02 + waveElevation;
  let hD = cos((uv.y - texel.y) * 35.0 - time * response) * 0.02 + waveElevation;
  let hU = cos((uv.y + texel.y) * 35.0 - time * response) * 0.02 + waveElevation;
  let surfNormal = normalize(vec3<f32>((hL - hR) * 20.0, (hD - hU) * 20.0, 1.0));
  let fresnel = fresnelSchlick(max(surfNormal.z, 0.0), 0.04);

  // Sub-pixel multi-tap advection with chromatic dispersion
  let dispMagnitude = length(totalDisp);
  let dispDir = totalDisp / max(dispMagnitude, 0.0001);
  let chromaticSplit = dispDir * (0.0015 + highlightShift * 0.012 + audio.z * 0.006);

  let uvCenter = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvRed = clamp(uvCenter + chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvBlue = clamp(uvCenter - chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0));

  let tap0R = textureSampleLevel(readTexture, u_sampler, uvRed, 0.0).r;
  let tap0G = textureSampleLevel(readTexture, u_sampler, uvCenter, 0.0).g;
  let tap0B = textureSampleLevel(readTexture, u_sampler, uvBlue, 0.0).b;
  let tap0A = textureSampleLevel(readTexture, u_sampler, uvCenter, 0.0).a;

  let tap1 = textureSampleLevel(readTexture, u_sampler, clamp(uvCenter - totalDisp * 0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let tap2 = textureSampleLevel(readTexture, u_sampler, clamp(uvCenter - totalDisp * 1.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let advectedColor = vec4<f32>(tap0R, tap0G, tap0B, tap0A) * 0.54 + tap1 * 0.30 + tap2 * 0.16;

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(uvCenter * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // Optical highlight and spectral caustics
  let rimHue = mix(vec3<f32>(0.1, 0.45, 1.0), vec3<f32>(1.0, 0.35, 0.85), highlightShift);
  let causticLight = pow(clamp(waveElevation * 0.5 + 0.5, 0.0, 1.0), 3.5) * (0.3 + audio.x * 0.7);
  let specular = fresnel * (rimHue * 0.75 + vec3<f32>(causticLight));

  let feedbackMix = clamp(0.08 + response * 0.14 - kineticEnergy * 2.0, 0.04, 0.28) * history.a;
  var finalRGB = mix(advectedColor.rgb + specular, history.rgb, feedbackMix);
  finalRGB = acesToneMapping(finalRGB);

  let finalAlpha = clamp(advectedColor.a * (0.85 + depthFactor * 0.15) + fresnel * 0.15 + causticLight * 0.1, 0.0, 1.0);
  let outputColor = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let outDepth = clamp(rawDepth + waveElevation * 0.05 - dispMagnitude * 0.2, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
