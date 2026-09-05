// ═══════════════════════════════════════════════════════════════════
//  Neon Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA (heat energy in alpha)
//  Motion: heat advection packets + refraction whip
//  Heat field is closed-form from pointer/ripples — not a raw A simulation
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

struct ThermalField {
  heat: f32,
  grad: vec2<f32>,
  pulse: f32,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  let cool = t <= 6600.0;
  let r = select(1.29293618 * pow(max(tt - 60.0, 0.01), -0.1332047592), 1.0, cool);
  let g = select(1.12989086 * pow(max(tt - 60.0, 0.01), -0.0755148492), 0.39008157 * log(tt) - 0.63184144, cool);
  let b = select(1.0, select(0.0, 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408, t >= 2000.0), cool);
  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn addSource(uv: vec2<f32>, center: vec2<f32>, aspect: f32, sigma: f32, amp: f32, field: ThermalField) -> ThermalField {
  var outf = field;
  let delta = vec2<f32>((uv.x - center.x) * aspect, uv.y - center.y);
  let r2 = dot(delta, delta);
  let contribution = amp * exp(-r2 / max(sigma, 1e-5));
  let gradAspect = contribution * (-2.0 / max(sigma, 1e-5)) * delta;
  outf.heat = outf.heat + contribution;
  outf.grad = outf.grad + vec2<f32>(gradAspect.x / aspect, gradAspect.y);
  outf.pulse = max(outf.pulse, contribution);
  return outf;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[4].x;
  let binB = plasmaBuffer[8].y;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.6), vec2<f32>(2.6));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let refractionStrength = mix(0.001, 0.04, u.zoom_params.x);
  let diffusion = mix(0.35, 1.8, u.zoom_params.y);
  let glowGain = mix(0.25, 2.6, u.zoom_params.z);
  let cooling = mix(0.35, 2.2, u.zoom_params.w);

  var field: ThermalField;
  field.heat = 0.0;
  field.grad = vec2<f32>(0.0);
  field.pulse = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let alive = age > 0.0 && age < 4.0;
    let sigma = 0.003 + diffusion * (0.02 + age * 0.04);
    let amp = exp(-age * cooling) * (1.0 + 0.5 * sin(age * 8.0));
    field = addSource(uv, ripple.xy, aspect, sigma, select(0.0, amp, alive), field);
  }

  let mouseAmp = 0.25 + 1.15 * select(0.35, 1.0, held);
  field = addSource(uv, spring, aspect, 0.006 + diffusion * 0.015, mouseAmp, field);

  for (var j = 0u; j < 3u; j = j + 1u) {
    let phase = time * 0.55 + f32(j) * 2.094;
    let center = vec2<f32>(0.5 + 0.32 * sin(phase * 1.17 + f32(j)), 0.5 + 0.28 * cos(phase * 0.91 + f32(j) * 1.7));
    let packet = 0.5 + 0.5 * sin(time * 2.3 + f32(j) * 2.1);
    let amp = bass * packet * 0.7 * exp(-cooling * 0.15);
    field = addSource(uv, center, aspect, 0.004 + diffusion * 0.012, amp, field);
  }

  let whip = vec2<f32>(-field.grad.y, field.grad.x) * (0.35 + treble * 0.25);
  let advect = field.grad * 0.015 + whip * 0.02;
  let temperature = 300.0 + field.heat * 6000.0 + bass * 900.0;
  let displacedUV = clamp(uv + (field.grad * (-0.3) + whip) * refractionStrength, vec2<f32>(0.0), vec2<f32>(1.0));

  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let histCoord = vec2<i32>(clamp(uv - advect, vec2<f32>(0.0), vec2<f32>(0.999)) * dims);
  let hist = textureLoad(dataTextureC, histCoord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;

  let spectral = blackbodyRGB(temperature);
  let thermalGlow = spectral * smoothstep(0.06, 0.65, field.heat) * glowGain * (0.35 + 0.65 * field.pulse + 0.4 * bass);
  let fogGlow = blackbodyRGB(temperature * 0.55 + 900.0) * field.heat * (0.03 + 0.07 * mids + binA * 0.04);
  var hdr = mix(displaced.rgb + thermalGlow + fogGlow, hist.rgb, 0.18);
  hdr = hdr + spectral * length(whip) * (0.12 + binB * 0.08);
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * 1.18;
  let rgb = acesToneMap(hdr * 1.05);
  let alpha = clamp(displaced.a * 0.4 + field.heat * 0.55 + field.pulse * 0.2, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
