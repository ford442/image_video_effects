// ═══════════════════════════════════════════════════════════════════
//  Rainbow Smoke with Dual Scattering
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, temporal
//  Complexity: Very High
//  Scientific: Multi-scale curl-noise smoke with vorticity confinement, buoyancy, Rayleigh edge scattering, and Mie forward glow
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn safeNormalize2(v: vec2<f32>, fallback: vec2<f32>) -> vec2<f32> {
  let len = length(v);
  if (len > 1e-5) {
    return v / len;
  }
  return fallback;
}

fn safeNormalize3(v: vec3<f32>, fallback: vec3<f32>) -> vec3<f32> {
  let len = length(v);
  if (len > 1e-5) {
    return v / len;
  }
  return fallback;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash21(i + vec2<f32>(0.0, 0.0));
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm3(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.55;
  var frequency = 1.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    value += amplitude * valueNoise(p * frequency);
    frequency *= 2.15;
    amplitude *= 0.48;
  }
  return value;
}

fn streamFunction(p: vec2<f32>, time: f32, scale: f32, phase: f32) -> f32 {
  return fbm3(p * scale + vec2<f32>(time * 0.026 + phase, -time * 0.018 + phase * 0.5));
}

fn curlNoise(p: vec2<f32>, time: f32, scale: f32, phase: f32, eps: f32) -> vec2<f32> {
  let dy = streamFunction(p + vec2<f32>(0.0, eps), time, scale, phase) - streamFunction(p - vec2<f32>(0.0, eps), time, scale, phase);
  let dx = streamFunction(p + vec2<f32>(eps, 0.0), time, scale, phase) - streamFunction(p - vec2<f32>(eps, 0.0), time, scale, phase);
  return vec2<f32>(dy, -dx) / max(2.0 * eps, 1e-4);
}

fn sampleState(uv: vec2<f32>, resolution: vec2<f32>, size: vec2<i32>) -> vec4<f32> {
  let pos = clamp(uv * resolution - vec2<f32>(0.5), vec2<f32>(0.0), resolution - vec2<f32>(1.001));
  let i0 = vec2<i32>(i32(floor(pos.x)), i32(floor(pos.y)));
  let f = fract(pos);
  let c00 = textureLoad(dataTextureC, clampCoord(i0, size), 0);
  let c10 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 0), size), 0);
  let c01 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(0, 1), size), 0);
  let c11 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 1), size), 0);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn phaseMie(cosTheta: f32, g: f32) -> f32 {
  let denom = pow(max(1.0 + g * g - 2.0 * g * cosTheta, 0.08), 1.5);
  return (1.0 - g * g) / (4.0 * PI * denom);
}

fn phaseRayleigh(cosTheta: f32) -> f32 {
  return 0.75 * (1.0 + cosTheta * cosTheta);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let size = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;
  let pixel = 1.0 / min(resolution.x, resolution.y);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let emissionControl = saturate(u.zoom_params.x);
  let turbulenceControl = saturate(u.zoom_params.y);
  let scatteringControl = saturate(u.zoom_params.z);
  let advectionControl = mix(0.45, 1.45, u.zoom_params.w);

  let prev = textureLoad(dataTextureC, coord, 0);
  let prevVelocity = prev.rg;
  let advected = sampleState(uv - prevVelocity * advectionControl, resolution, size);

  var velocity = advected.rg * 0.972;
  var density = advected.b * 0.994;
  var temperature = advected.a * 0.992;

  let mouse = u.zoom_config.yz;
  let mouseMask = (1.0 - smoothstep(0.0, 0.22, distance(uv, mouse))) * (0.2 + u.zoom_config.w * 1.35);
  let mouseDir = safeNormalize2(mouse - vec2<f32>(0.5, 0.5), vec2<f32>(1.0, 0.0));

  let baseEmissionCenter = vec2<f32>(0.5 + 0.18 * sin(time * 0.18), 0.88);
  let baseEmission = (1.0 - smoothstep(0.0, 0.24, distance(uv, baseEmissionCenter))) * (0.03 + emissionControl * 0.12 + bass * 0.18);

  let curl1 = curlNoise(uv, time, 2.0, 0.0, pixel * 5.0);
  let curl2 = curlNoise(uv + vec2<f32>(1.7, -2.3), time * 1.2, 4.5, 7.1, pixel * 4.0);
  let curl3 = curlNoise(uv + vec2<f32>(-4.4, 5.1), time * 1.45, 8.0, 13.7, pixel * 3.0);
  let multiCurl = curl1 + curl2 * 0.5 + curl3 * 0.25;
  velocity += multiCurl * (0.0015 + turbulenceControl * 0.011);

  let vN = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, -1), size), 0).rg;
  let vS = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, 1), size), 0).rg;
  let vE = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(1, 0), size), 0).rg;
  let vW = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(-1, 0), size), 0).rg;
  let omega = (vE.y - vW.y) - (vN.x - vS.x);
  let gradAbsOmega = vec2<f32>(abs(vE.y) - abs(vW.y), abs(vN.x) - abs(vS.x));
  let confDir = safeNormalize2(gradAbsOmega, vec2<f32>(0.0, 1.0));
  velocity += vec2<f32>(confDir.y, -confDir.x) * omega * (0.001 + turbulenceControl * 0.012) * (1.0 + bass * 3.0);

  velocity += mouseDir * mouseMask * 0.008;
  velocity.y -= mouseMask * 0.005;
  velocity.y -= 0.0015 + temperature * 0.014 + density * 0.004;

  density = saturate(density + baseEmission + mouseMask * 0.02 - 0.003);
  temperature = saturate(temperature + baseEmission * (0.8 + bass * 1.4) + mouseMask * 0.05 - 0.002);

  let densityN = sampleState(uv + vec2<f32>(0.0, -pixel * 2.0), resolution, size).b;
  let densityS = sampleState(uv + vec2<f32>(0.0, pixel * 2.0), resolution, size).b;
  let densityE = sampleState(uv + vec2<f32>(pixel * 2.0, 0.0), resolution, size).b;
  let densityW = sampleState(uv + vec2<f32>(-pixel * 2.0, 0.0), resolution, size).b;
  let gradient = vec2<f32>(densityE - densityW, densityN - densityS);
  let edge = smoothstep(0.015, 0.14, length(gradient));

  let spectralPhase = fract(time * 0.045 + density * 0.22 + uv.x * 0.25 + uv.y * 0.18 + treble * 0.25);
  let rainbow = 0.55 + 0.45 * cos(6.28318 * vec3<f32>(spectralPhase, spectralPhase + 0.33, spectralPhase + 0.67));
  let colorTemp = saturate(temperature + treble * 0.55);
  let thermalColor = mix(vec3<f32>(0.24, 0.45, 1.0), vec3<f32>(1.0, 0.68, 0.26), colorTemp);
  let albedo = mix(rainbow, thermalColor, 0.45 + mids * 0.15);

  let normal = safeNormalize3(vec3<f32>(-gradient.x * 5.0, 0.6 + temperature * 0.8, -gradient.y * 5.0), vec3<f32>(0.0, 1.0, 0.0));
  let lightDir = safeNormalize3(vec3<f32>(0.35, 0.22, 1.0), vec3<f32>(0.35, 0.22, 1.0));
  let cosTheta = dot(normal, lightDir);
  let mie = phaseMie(cosTheta, 0.68) * (0.25 + density * 0.95) * (0.35 + temperature * 0.9);
  let rayleigh = phaseRayleigh(cosTheta) * edge * (0.4 + (1.0 - colorTemp) * 0.8);

  let mieColor = albedo * density * mie * (0.10 + scatteringControl * 0.22);
  let rayleighColor = vec3<f32>(0.28, 0.54, 1.0) * rayleigh * (0.25 + scatteringControl * 0.6);
  let coreGlow = vec3<f32>(1.0, 0.9, 0.72) * smoothstep(0.42, 0.95, density) * (0.18 + bass * 0.9 + temperature * 0.55);
  let bodyColor = albedo * density * (0.35 + scatteringControl * 0.55);

  let alpha = 1.0 - exp(-density * (1.8 + scatteringControl * 2.2));
  let generatedColor = acesToneMap(mieColor + rayleighColor + bodyColor + coreGlow);
  let background = mix(vec3<f32>(0.02, 0.02, 0.03), inputColor.rgb, 0.35);
  let finalColor = mix(background, generatedColor, alpha);
  let finalAlpha = max(inputColor.a, alpha);
  let finalDepth = mix(inputDepth, saturate(0.12 + density * 0.72 + temperature * 0.12), 0.9);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(velocity, density, temperature));
  textureStore(dataTextureB, coord, vec4<f32>(omega * 0.5 + 0.5, edge, bass, treble));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
