// Datamosh — Batch 58D authoritative motion-state correction
// A packs motion.xy, normalized age, and strength; B is intentionally unwritten.

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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> { return vec2<f32>(hash12(p), hash12(p + vec2<f32>(17.0, 31.0))); }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let texel = 1.0 / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: motion strength, I-frame interval, smear blend, trail decay.
  let motionStrength = u.zoom_params.x * 0.16 * (1.0 + bass * 0.8);
  let iframeInterval = u.zoom_params.y * 4.0 + 0.5;
  let blendAmount = clamp(u.zoom_params.z * 0.95 + 0.05 + mids * 0.12, 0.05, 1.0);
  let feedbackDecay = u.zoom_params.w;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 9.0; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let blockSize = 8.0;
  let block = floor(vec2<f32>(pixel) / blockSize);
  let blockCenter = (block * blockSize + vec2<f32>(4.0)) / res;
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gx = luma(textureSampleLevel(readTexture, u_sampler, clamp(blockCenter + vec2<f32>(texel.x * 4.0, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb) -
           luma(textureSampleLevel(readTexture, u_sampler, clamp(blockCenter - vec2<f32>(texel.x * 4.0, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let gy = luma(textureSampleLevel(readTexture, u_sampler, clamp(blockCenter + vec2<f32>(0.0, texel.y * 4.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb) -
           luma(textureSampleLevel(readTexture, u_sampler, clamp(blockCenter - vec2<f32>(0.0, texel.y * 4.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let observedMotion = vec2<f32>(-gy, gx) * motionStrength;

  // Exact C is the packed state written by A, sampled at this pixel only.
  let previous = textureLoad(dataTextureC, pixel, 0);
  var motion = previous.xy;
  var age = clamp(previous.z, 0.0, 1.0);
  var strength = clamp(previous.w, 0.0, 1.0);
  let iframePhase = fract(time / iframeInterval);
  let isIFrame = iframePhase < (0.035 + treble * 0.01);
  if (isIFrame) {
    motion = observedMotion; age = 0.0; strength = u.zoom_params.x;
  } else {
    motion = mix(motion * (0.985 - feedbackDecay * 0.08), observedMotion, 0.08 + mids * 0.04);
    age = min(age + dt / iframeInterval, 1.0);
    strength = mix(strength, u.zoom_params.x, 0.05);
  }

  let pointerDelta = (uv - springPos) * aspectVec; let pointerDist = length(pointerDelta);
  let scrub = exp(-pointerDist * 10.0) * select(0.25, 1.0, u.zoom_config.w > 0.5);
  motion += springVel * scrub * 0.7;
  var clickStrength = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let rippleAge = time - ripple.z;
    if (rippleAge < 0.0 || rippleAge > 1.2) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let front = exp(-pow((dist - rippleAge * 0.26) * 22.0, 2.0)) * (1.0 - rippleAge / 1.2);
    motion += (hash22(block + ripple.xy) - 0.5) * front * motionStrength * 2.0;
    clickStrength += front;
  }
  let corruption = step(0.93 - bass * 0.12, hash12(block + floor(time * 8.0)));
  motion += (hash22(block + floor(time * 5.0)) - 0.5) * corruption * motionStrength;
  motion = clamp(motion, vec2<f32>(-0.25), vec2<f32>(0.25));
  strength = clamp(strength + clickStrength * 0.35 + corruption * 0.2 + scrub * 0.12, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(motion, age, strength));

  // Prediction comes from the current source plus accumulated state—not C display pixels.
  let predictedUv = clamp(uv - motion * (0.4 + strength * 1.6), vec2<f32>(0.0), vec2<f32>(1.0));
  let predicted = textureSampleLevel(readTexture, u_sampler, predictedUv, 0.0);
  let blockDecision = step(0.3, hash12(block + floor(time / 0.12)));
  let predictionMix = select(blendAmount * 0.35, blendAmount, blockDecision > 0.5) * select(1.0, 0.0, isIFrame);
  var hdr = mix(source.rgb, predicted.rgb, predictionMix);
  let blockUv = fract(vec2<f32>(pixel) / blockSize) - vec2<f32>(0.5);
  let blockEdge = smoothstep(0.36, 0.5, max(abs(blockUv.x), abs(blockUv.y)));
  hdr += vec3<f32>(0.06, 0.012, 0.09) * blockEdge * (corruption + clickStrength) * (0.5 + treble);
  let effectEnergy = clamp(length(motion) * 4.0 + strength * predictionMix * 0.6 + blockEdge * corruption * 0.3 + clickStrength * 0.3, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
