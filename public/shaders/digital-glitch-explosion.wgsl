// Digital Glitch Explosion — Composer batch cyber/digital/glitch
// Bitwise corruption + prismatic chromatic shockwaves: spring cursor, held
// burst, capped ripples, exact C smear, three-band audio, ACES + semantic alpha.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

fn floatToByte(v: f32) -> u32 {
  return u32(clamp(v, 0.0, 1.0) * 255.0);
}

fn byteToFloat(b: u32) -> f32 {
  return f32(b & 0xFFu) / 255.0;
}

fn bitFlip(b: u32, pos: u32) -> u32 {
  return b ^ (1u << (pos % 8u));
}

fn randomBitFlip(b: u32, seed: f32, probability: f32) -> u32 {
  if (seed < probability) {
    let bitPos = u32(seed * 1000.0) % 8u;
    return bitFlip(b, bitPos);
  }
  return b;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let corruptionIntensity = clamp(u.zoom_params.x * (1.0 + bass * 0.35), 0.0, 1.0);
  let prismStrength = mix(0.02, 0.14, u.zoom_params.y) * (1.0 + treble * 0.2);
  let dispersion = mix(0.5, 3.0, u.zoom_params.z) * (1.0 + mids * 0.15);
  let decayRate = u.zoom_params.w;

  let mouseDist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);
  var effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.35, 0.0, 1.0);
  effectiveIntensity = clamp(effectiveIntensity * select(1.0, 1.45, held), 0.0, 1.0);

  let prevFrame = textureLoad(dataTextureC, coord, 0);
  let prevSmear = prevFrame.rgb;
  let prevEnergy = prevFrame.a;

  var rippleBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.5) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      rippleBurst += smoothstep(0.14, 0.0, rDist) * (1.0 - age * 0.4);
    }
  }
  effectiveIntensity = clamp(effectiveIntensity + rippleBurst * 0.35 + prevEnergy * 0.12, 0.0, 1.0);

  let blockSize = mix(8.0, 64.0, effectiveIntensity);
  let blockCoord = floor(uv * blockSize);
  let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
  let maxShift = mix(0.0, 0.05, effectiveIntensity);
  let xShift = (blockSeed - 0.5) * maxShift;
  let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;

  var displacedUV = clamp(uv + vec2<f32>(xShift, yShift), vec2<f32>(0.0), vec2<f32>(1.0));

  let row = floor(uv.y * blockSize);
  let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
  let tear = step(0.95, scanSeed);
  displacedUV.x = displacedUV.x + tear * 0.15 * (blockSeed - 0.5) * effectiveIntensity;
  displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let rUV = prismDisplace(displacedUV, smoothMouse, -1.0 * dispersion, prismStrength);
  let gUV = prismDisplace(displacedUV, smoothMouse, 0.0, prismStrength);
  let bUV = prismDisplace(displacedUV, smoothMouse, 1.0 * dispersion, prismStrength);

  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((displacedUV - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((displacedUV - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let intensity = 1.0 + select(0.0, 1.5, held) + rippleBurst * 0.5;
  let baseSample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var r = textureSampleLevel(readTexture, u_sampler, clamp(rUV + rOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, clamp(gUV + gOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, clamp(bUV + bOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  if (effectiveIntensity > 0.01) {
    let pixelSeed = hash33(vec3<f32>(uv * 1000.0, time));
    var channels = array<f32, 3>(r, g, b);
    for (var ch = 0; ch < 3; ch = ch + 1) {
      var byteVal = floatToByte(channels[ch]);
      let channelSeed = hash21(uv + vec2<f32>(f32(ch) * 100.0, time));
      let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
      channels[ch] = byteToFloat(byteVal);
    }
    r = channels[0];
    g = channels[1];
    b = channels[2];
  }

  var color = vec3<f32>(r, g, b);

  if (decayRate > 0.01) {
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let levels = max(2.0, 16.0 - timeDecay * 2.0 - spatialDecay);
    color = floor(color * levels) / levels;
  }

  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.15 + treble * 0.1);

  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  color = color + vec3<f32>(0.5, 0.3, 0.8) * glow * (1.0 + bass * 0.3);

  let bandBin = min(u32(uv.x * 8.0), 7u) + 1u;
  color = color + vec3<f32>(plasmaBuffer[bandBin].x * 0.04, plasmaBuffer[bandBin].y * 0.02, plasmaBuffer[bandBin].z * 0.05);

  let smearMix = mix(0.08, 0.35, decayRate) * (0.5 + effectiveIntensity * 0.5);
  color = mix(color, prevSmear, smearMix);

  color = acesToneMap(color * (0.95 + bass * 0.08));

  let totalDisp = length(rUV - gUV) + length(gUV - bUV);
  let alpha = clamp(baseSample.a * (1.0 - effectiveIntensity * 0.15) + totalDisp * 4.0 + effectiveIntensity * 0.25 + mouseInfluence * 0.1, 0.0, 1.0);
  let energy = clamp(effectiveIntensity * 0.85 + rippleBurst * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, energy));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
