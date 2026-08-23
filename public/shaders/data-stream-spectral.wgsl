// ═══════════════════════════════════════════════════════════════════
//  Data Stream Spectral — Batch 67
//  fp128 strip flow, FFT band tinting, racing head packets,
//  spring mouse [133..138], capped click wakes, ACES + semantic alpha.
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

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn strip_head_packet(uv: vec2<f32>, stripIdx: f32, time: f32, speed: f32) -> f32 {
  let head = fract(time * speed * (0.4 + fract(sin(stripIdx * 12.9898) * 43758.5453) * 0.6));
  return pow(max(0.0, 1.0 - abs(uv.y - head) * 20.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 0.001);
  let held = u.zoom_config.w > 0.5;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let speed = max(u.zoom_params.x * (1.0 + bass * 0.3), 0.001);
  let density = max(u.zoom_params.y, 0.001);
  let turbulence = clamp(u.zoom_params.z * select(1.0, 1.4, held), 0.0, 1.0);
  let glow = clamp(u.zoom_params.w, 0.0, 1.0);

  let rawMouse = u.zoom_config.yz;
  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var mousePos = rawMouse;
  if (hasSpringState && extraBuffer[138] > 0.5) {
    mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = mousePos;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 8.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let interact = smoothstep(0.3, 0.0, mouseDist) * turbulence;

  let numStrips = 20.0 + density * 100.0;
  let stripIdx = floor(uv.x * numStrips);
  let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

  let stripBin = (u32(abs(stripIdx)) % 8u) + 1u;
  let fftStrip = plasmaBuffer[stripBin].x;
  let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5 * (1.0 + fftStrip * 0.28);
  let packet = strip_head_packet(uv, stripIdx, time, flowSpeed * (1.0 + treble));

  var clickWake = 0.0;
  var clickGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.6, age));
    let clickVec = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
    let clickDist = length(clickVec);
    let ring = 1.0 - smoothstep(0.018, 0.065, abs(clickDist - safeAge * 0.34));
    let wave = ring * exp(-safeAge * 1.7) * live;
    clickWake += wave * sin(uv.y * 24.0 + rp.x * 19.0 + safeAge * 8.0);
    clickGlow = max(clickGlow, wave);
  }

  let xOffset = interact * sin(uv.y * 10.0 + time * 5.0) * 0.05 + clickWake * turbulence * 0.045;
  let flowPhase = fp128_sum(fp128_mul(fp128(time), fp128(flowSpeed)), fp128(-uv.y));
  var sampleUV = uv;
  sampleUV.x = sampleUV.x + xOffset;
  sampleUV.y = fract(fp128_val(flowPhase));

  if (rand > 0.8) {
    sampleUV.y = sampleUV.y + sin(time * 10.0) * 0.01;
  }

  let band = u32(stripIdx) % 4u;
  var color = vec3<f32>(0.0);
  var spectralEnergy = 0.0;

  if (band == 0u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 8; i++) {
      let angle = f32(i) * 6.283185307 / 8.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 4.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 8.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(1.0, 0.8, 0.6);
  } else if (band == 1u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 6; i++) {
      let angle = f32(i) * 6.283185307 / 6.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 2.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 6.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.6, 1.0, 0.7);
  } else if (band == 2u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 4; i++) {
      let angle = f32(i) * 6.283185307 / 4.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 1.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 4.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.5, 0.7, 1.0);
  } else {
    color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let blurred = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(1.0, 0.0) / res, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = color - blurred * 0.5;
    spectralEnergy = length(color);
    color = color * vec3<f32>(1.0, 1.0, 1.0);
  }

  spectralEnergy = spectralEnergy * (1.0 + fftStrip * 0.35 + mids * 0.15);

  let blockY = floor(uv.y * 50.0);
  let noise = fract(sin(dot(vec2<f32>(stripIdx, blockY), vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let bright = step(0.98, noise * (sin(time * 2.0 + stripIdx) * 0.5 + 0.5));

  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2);
  var outputColor = mix(color, digitalColor, glow);
  outputColor = outputColor + vec3<f32>(0.0, bright * glow, 0.0);
  outputColor += vec3<f32>(0.15, 0.35, 0.5) * packet * (0.2 + treble * 0.3);
  outputColor += vec3<f32>(0.1, 0.25, 0.4) * clickGlow * 0.35;

  let prev = textureLoad(dataTextureC, pixel, 0);
  outputColor = mix(outputColor, prev.rgb * 0.9, packet * 0.1);

  outputColor = acesToneMap(max(outputColor, vec3<f32>(0.0)));

  let alpha = clamp(spectralEnergy * mix(0.45, 0.88, glow) + packet * 0.08 + clickGlow * 0.1, 0.06, 0.98);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(outputColor, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(outputColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
