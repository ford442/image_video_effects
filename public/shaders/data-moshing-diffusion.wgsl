// ═══════════════════════════════════════════════════════════════════
//  Data Moshing Diffusion
//  Category: advanced-hybrid
//  Features: audio-reactive, temporal-smear-persistence, chromatic-diffusion,
//            mouse-driven, anisotropic-diffusion, upgraded-rgba
//  Complexity: Very High
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

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
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
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Audio-reactive parameters
  let smearStrength = u.zoom_params.x * (1.0 + bass * 0.3);
  let kappa = mix(0.01, 0.2, u.zoom_params.y) * (1.0 - mids * 0.1);
  let dt = mix(0.05, 0.25, u.zoom_params.z) * (1.0 + treble * 0.1);
  let quantize = u.zoom_params.w;

  // Advect the packed UV-offset state through a smooth tape conveyor.
  let conveyor = vec2<i32>(i32(round(sin(uv.y * 10.0 + time * 1.7) * 2.0)), 2 + i32(round(bass * 2.0)));
  let historyCoord = clamp(coord + conveyor, vec2<i32>(0), maxCoord);
  let prevData = textureLoad(dataTextureC, historyCoord, 0);
  var offset = prevData.xy;

  // Mouse swirl interaction
  let aspect = res.x / res.y;
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseRadius = mix(0.05, 0.3, smearStrength);
  if (mouseDist < mouseRadius) {
    let angle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let swirl = vec2<f32>(cos(angle + time), sin(angle + time));
    let heldBoost = mix(0.35, 1.0, step(0.5, u.zoom_config.w));
    let force = (1.0 - mouseDist / mouseRadius) * smearStrength * 0.02 * heldBoost;
    offset = offset + swirl * force;
  }

  // Continuous stream packets and click fronts inject coherent offset motion.
  let streamPacket = pow(max(0.0, sin(uv.y * 48.0 + uv.x * 17.0 - time * 14.0)), 12.0);
  offset += vec2<f32>(0.012, -0.004) * streamPacket * smearStrength * (1.0 + treble);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let distanceToClick = length(delta);
      let direction = delta / max(distanceToClick, 0.0001);
      let front = smoothstep(0.025, 0.0, abs(distanceToClick - age * 0.44)) * exp(-age * 1.5);
      offset += direction * front * 0.025 * smearStrength;
    }
  }

  offset = offset * 0.96;
  offset = clamp(offset, vec2<f32>(-0.5), vec2<f32>(0.5));

  let distortedUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  var currentR = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).r;
  var currentG = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).g;
  var currentB = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).b;

  // Chromatic anisotropic diffusion: each channel diffuses differently
  let iterations = 2;
  var avgCoeff = 0.0;
  for (var iter = 0; iter < iterations; iter++) {
    let n = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, 1.0) * pixelSize, 0.0);
    let s = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, -1.0) * pixelSize, 0.0);
    let e = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(1.0, 0.0) * pixelSize, 0.0);
    let w = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0);

    let gradNR = length(vec3<f32>(n.r - currentR, n.g - currentG, n.b - currentB));
    let gradSR = length(vec3<f32>(s.r - currentR, s.g - currentG, s.b - currentB));
    let gradER = length(vec3<f32>(e.r - currentR, e.g - currentG, e.b - currentB));
    let gradWR = length(vec3<f32>(w.r - currentR, w.g - currentG, w.b - currentB));

    let cN = diffusionCoefficient(gradNR, kappa * (1.0 + bass * 0.1));
    let cS = diffusionCoefficient(gradSR, kappa * (1.0 + mids * 0.1));
    let cE = diffusionCoefficient(gradER, kappa * (1.0 + treble * 0.1));
    let cW = diffusionCoefficient(gradWR, kappa);

    let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * smearStrength;
    let mouseBoost = 1.0 + mouseFactor * 5.0;

    // Chromatic diffusion: R diffuses more north, G center, B more south
    currentR = currentR + dt * mouseBoost * (cN * (n.r - currentR) + cS * (s.r - currentR) + cE * (e.r - currentR) + cW * (w.r - currentR)) * (1.0 + bass * 0.1);
    currentG = currentG + dt * mouseBoost * (cN * (n.g - currentG) + cS * (s.g - currentG) + cE * (e.g - currentG) + cW * (w.g - currentG));
    currentB = currentB + dt * mouseBoost * (cN * (n.b - currentB) + cS * (s.b - currentB) + cE * (e.b - currentB) + cW * (w.b - currentB)) * (1.0 + treble * 0.1);
    avgCoeff = (cN + cS + cE + cW) * 0.25;
  }

  var finalColor = vec3<f32>(currentR, currentG, currentB);

  // Color quantization with audio-driven glitch
  if (quantize > 0.0) {
    let q = 20.0 * (1.0 - quantize) + 1.0 + bass * 5.0;
    finalColor = floor(finalColor * q) / q;
  }

  // Display trails re-sample source color; packed A history remains UV-offset state.
  let trailUV = clamp(uv - offset * 1.65, vec2<f32>(0.0), vec2<f32>(1.0));
  let trailColor = textureSampleLevel(readTexture, u_sampler, trailUV, 0.0).rgb;
  finalColor = clamp(mix(finalColor, trailColor, 0.08 + smearStrength * 0.12), vec3<f32>(0.0), vec3<f32>(4.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(avgCoeff + length(offset) * 2.0 + bass * 0.05, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(offset, 0.0, alpha));
  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
