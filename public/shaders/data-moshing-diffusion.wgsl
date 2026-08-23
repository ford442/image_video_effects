// ═══════════════════════════════════════════════════════════════════
//  Data Moshing Diffusion — Batch 67
//  fp128 offset integration, anisotropic diffusion, racing stream
//  packets, exact C advection, capped click fronts, held swirl, ACES.
//  dataTextureA = SIM STATE (UV offset.xy, _, alpha diagnostic).
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

struct Fp128Vec2 {
  base: vec2<f32>,
  mant: vec2<f32>,
}

fn fp128v2_add(a: Fp128Vec2, b: Fp128Vec2) -> Fp128Vec2 {
  return Fp128Vec2(a.base + b.base, a.mant + b.mant);
}
fn fp128v2_val(v: Fp128Vec2) -> vec2<f32> { return v.base + v.mant; }

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stream_packet(uv: vec2<f32>, time: f32, treble: f32) -> f32 {
  return pow(max(0.0, sin(uv.y * 48.0 + uv.x * 17.0 - time * (14.0 + treble * 6.0)), 0.0), 12.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let aspect = res.x / res.y;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let smearStrength = u.zoom_params.x * (1.0 + bass * 0.3);
  let kappa = mix(0.01, 0.2, u.zoom_params.y) * (1.0 - mids * 0.1);
  let dt = mix(0.05, 0.25, u.zoom_params.z) * (1.0 + treble * 0.1);
  let quantize = u.zoom_params.w;

  let conveyor = vec2<i32>(i32(round(sin(uv.y * 10.0 + time * 1.7) * 2.0)), 2 + i32(round(bass * 2.0)));
  let historyCoord = clamp(coord + conveyor, vec2<i32>(0), maxCoord);
  var offset128 = Fp128Vec2(textureLoad(dataTextureC, historyCoord, 0).xy, vec2<f32>(0.0));

  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseRadius = mix(0.05, 0.3, smearStrength);
  if (mouseDist < mouseRadius) {
    let angle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let swirl = vec2<f32>(cos(angle + time), sin(angle + time));
    let force = (1.0 - mouseDist / mouseRadius) * smearStrength * 0.02 * select(0.35, 1.0, held);
    offset128 = fp128v2_add(offset128, Fp128Vec2(swirl * force, vec2<f32>(0.0)));
  }

  let packet = stream_packet(uv, time, treble);
  offset128 = fp128v2_add(offset128, Fp128Vec2(vec2<f32>(0.012, -0.004) * packet * smearStrength * (1.0 + treble), vec2<f32>(0.0)));

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let distanceToClick = length(delta);
      let direction = delta / max(distanceToClick, 0.0001);
      let front = smoothstep(0.025, 0.0, abs(distanceToClick - age * 0.44)) * exp(-age * 1.5);
      offset128 = fp128v2_add(offset128, Fp128Vec2(direction * front * 0.025 * smearStrength, vec2<f32>(0.0)));
    }
  }

  var offset = fp128v2_val(offset128) * 0.96;
  offset = clamp(offset, vec2<f32>(-0.5), vec2<f32>(0.5));

  let distortedUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  var currentR = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).r;
  var currentG = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).g;
  var currentB = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).b;

  var avgCoeff = 0.0;
  for (var iter = 0; iter < 2; iter++) {
    let n = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, pixelSize.y), 0.0);
    let s = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(0.0, pixelSize.y), 0.0);
    let e = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(pixelSize.x, 0.0), 0.0);
    let w = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(pixelSize.x, 0.0), 0.0);

    let gradNR = length(vec3<f32>(n.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradSR = length(vec3<f32>(s.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradER = length(vec3<f32>(e.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradWR = length(vec3<f32>(w.rgb - vec3<f32>(currentR, currentG, currentB)));

    let cN = diffusionCoefficient(gradNR, kappa * (1.0 + bass * 0.1));
    let cS = diffusionCoefficient(gradSR, kappa * (1.0 + mids * 0.1));
    let cE = diffusionCoefficient(gradER, kappa * (1.0 + treble * 0.1));
    let cW = diffusionCoefficient(gradWR, kappa);
    let mouseBoost = 1.0 + exp(-mouseDist * mouseDist * 10.0) * smearStrength * 5.0;

    currentR += dt * mouseBoost * (cN * (n.r - currentR) + cS * (s.r - currentR) + cE * (e.r - currentR) + cW * (w.r - currentR)) * (1.0 + bass * 0.1);
    currentG += dt * mouseBoost * (cN * (n.g - currentG) + cS * (s.g - currentG) + cE * (e.g - currentG) + cW * (w.g - currentG));
    currentB += dt * mouseBoost * (cN * (n.b - currentB) + cS * (s.b - currentB) + cE * (e.b - currentB) + cW * (w.b - currentB)) * (1.0 + treble * 0.1);
    avgCoeff = (cN + cS + cE + cW) * 0.25;
  }

  var finalColor = vec3<f32>(currentR, currentG, currentB);
  if (quantize > 0.0) {
    let q = 20.0 * (1.0 - quantize) + 1.0 + bass * 5.0;
    finalColor = floor(finalColor * q) / q;
  }

  let trailUV = clamp(uv - offset * 1.65, vec2<f32>(0.0), vec2<f32>(1.0));
  let trailColor = textureSampleLevel(readTexture, u_sampler, trailUV, 0.0).rgb;
  let prevDisplay = textureLoad(dataTextureC, coord, 0);
  finalColor = mix(finalColor, mix(trailColor, prevDisplay.rgb * 0.9, packet * 0.15), 0.08 + smearStrength * 0.12);
  finalColor = acesToneMap(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0)));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let alpha = clamp(avgCoeff + length(offset) * 2.0 + bass * 0.05 + packet * 0.1, 0.06, 0.98);

  textureStore(dataTextureA, coord, vec4<f32>(offset, alpha));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
