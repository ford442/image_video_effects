// ═══════════════════════════════════════════════════════════════════
//  Neon Warp
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, thermal-diffusion, blackbody-refraction
//  Complexity: High
//  Scientific: Gaussian heat sources drive both refractive-index gradients and blackbody emission for mirage-like warp.
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

struct ThermalField {
  heat: f32,
  grad: vec2<f32>,
  pulse: f32,
};

fn hash12(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn sampleColor(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;

  if (t <= 6600.0) {
    r = 1.0;
    g = 0.39008157 * log(tt) - 0.63184144;
    if (t < 2000.0) {
      b = 0.0;
    } else {
      b = 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408;
    }
  } else {
    r = 1.29293618 * pow(tt - 60.0, -0.1332047592);
    g = 1.12989086 * pow(tt - 60.0, -0.0755148492);
    b = 1.0;
  }

  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn thermalField(uv: vec2<f32>, resolution: vec2<f32>, time: f32, bass: f32, diffusion: f32, cooling: f32) -> ThermalField {
  let aspect = resolution.x / max(resolution.y, 1.0);
  var field: ThermalField;
  field.heat = 0.0;
  field.grad = vec2<f32>(0.0);
  field.pulse = 0.0;

  for (var i: u32 = 0u; i < 50u; i = i + 1u) {
    if (i >= min(u32(u.config.y), 50u)) {
      break;
    }

    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let sigma = 0.003 + diffusion * (0.02 + age * 0.04);
    let amplitude = exp(-age * cooling) * (1.0 + 0.5 * sin(age * 8.0));
    let delta = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
    let r2 = dot(delta, delta);
    let contribution = amplitude * exp(-r2 / sigma);
    let gradAspect = contribution * (-2.0 / sigma) * delta;

    field.heat = field.heat + contribution;
    field.grad = field.grad + vec2<f32>(gradAspect.x / aspect, gradAspect.y);
    field.pulse = max(field.pulse, contribution);
  }

  let mousePos = u.zoom_config.yz;
  let mouseDelta = vec2<f32>((uv.x - mousePos.x) * aspect, uv.y - mousePos.y);
  let mouseSigma = 0.006 + diffusion * 0.015;
  let mouseAmplitude = 0.25 + 1.15 * u.zoom_config.w;
  let mouseContribution = mouseAmplitude * exp(-dot(mouseDelta, mouseDelta) / mouseSigma);
  let mouseGradAspect = mouseContribution * (-2.0 / mouseSigma) * mouseDelta;
  field.heat = field.heat + mouseContribution;
  field.grad = field.grad + vec2<f32>(mouseGradAspect.x / aspect, mouseGradAspect.y);
  field.pulse = max(field.pulse, mouseContribution);

  for (var j: u32 = 0u; j < 3u; j = j + 1u) {
    let seed = floor(time * 1.75) + f32(j) * 17.0;
    let center = vec2<f32>(hash12(vec2<f32>(seed, 1.3)), hash12(vec2<f32>(seed, 7.1)));
    let age = fract(time * 1.75 + f32(j) * 0.37);
    let sigma = 0.003 + diffusion * 0.012 + age * 0.008;
    let amplitude = bass * exp(-age * 5.0) * 0.85;
    let delta = vec2<f32>((uv.x - center.x) * aspect, uv.y - center.y);
    let r2 = dot(delta, delta);
    let contribution = amplitude * exp(-r2 / sigma);
    let gradAspect = contribution * (-2.0 / sigma) * delta;

    field.heat = field.heat + contribution;
    field.grad = field.grad + vec2<f32>(gradAspect.x / aspect, gradAspect.y);
    field.pulse = max(field.pulse, contribution);
  }

  return field;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let uv = vec2<f32>(global_id.xy) / resolution;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let refractionStrength = mix(0.001, 0.04, u.zoom_params.x);
  let diffusion = mix(0.35, 1.8, u.zoom_params.y);
  let glowGain = mix(0.25, 2.6, u.zoom_params.z);
  let cooling = mix(0.35, 2.2, u.zoom_params.w);

  let field = thermalField(uv, resolution, time, bass, diffusion, cooling);
  let temperature = 300.0 + field.heat * 6000.0 + bass * 900.0;
  let dn_dT = -1e-6;
  let refractiveGradient = field.grad * dn_dT * 300000.0;
  let displacedUV = clamp(uv + refractiveGradient * refractionStrength, vec2<f32>(0.0), vec2<f32>(1.0));

  let displaced = sampleColor(displacedUV);
  let displacedDepth = sampleDepth(displacedUV);
  let spectral = blackbodyRGB(temperature);
  let thermalGlow = spectral * smoothstep(0.06, 0.65, field.heat) * glowGain * (0.35 + 0.65 * field.pulse + 0.4 * bass);
  let fogGlow = blackbodyRGB(temperature * 0.55 + 900.0) * field.heat * (0.03 + 0.07 * mids);

  let finalColor = displaced.rgb + thermalGlow + fogGlow;
  let alpha = clamp(displaced.a + length(thermalGlow) * 0.08, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(field.heat, field.grad.x, field.grad.y, clamp((temperature - 300.0) / 7000.0, 0.0, 1.0)));
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
