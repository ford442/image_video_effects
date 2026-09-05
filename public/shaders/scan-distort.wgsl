// Scan Distort — Composer batch cyber/digital/glitch
// CRT scanline tear with block quantization, exact C smear, spring cursor,
// held glitch bursts, capped ripples, three-band audio, ACES + semantic alpha.

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

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn quantize(color: vec3<f32>, levels: f32) -> vec3<f32> {
  return floor(color * levels) / levels;
}

fn blockEdgeFactor(uv: vec2<f32>, blockSize: f32) -> f32 {
  let blockUV = uv * blockSize;
  let fracUV = fract(blockUV);
  let edgeDist = min(min(fracUV.x, 1.0 - fracUV.x), min(fracUV.y, 1.0 - fracUV.y));
  return smoothstep(0.05, 0.0, edgeDist);
}

fn bassEnv(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn glitchProbability(time: f32, freq: f32) -> f32 {
  let framePhase = fract(time * freq);
  let seed = hash2(vec2<f32>(floor(time * freq), 0.0));
  return select(0.0, 1.0, framePhase < 0.1 && seed < 0.15);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
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
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
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

  let blockSize = 4.0 + u.zoom_params.x * 12.0 * (1.0 + bass * 0.1);
  let quantLevel = 2.0 + u.zoom_params.y * 62.0;
  let mvVisibility = u.zoom_params.z * (1.0 + mids * 0.15);
  let glitchFreq = (0.1 + u.zoom_params.w * 2.0) * (1.0 + treble * 0.2);

  let prevFrame = textureLoad(dataTextureC, coord, 0);
  let prevEnv = prevFrame.a;
  let env = bassEnv(prevEnv, bass, 0.8, 0.15);

  let mouseGlitchBoost = select(0.0, 0.5, held);
  let effectiveGlitchFreq = glitchFreq + mouseGlitchBoost;

  let mouseScanBoost = 1.0 + smoothMouse.y * 0.5;
  let dist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));

  let lines = 100.0 * mouseScanBoost;
  let bendStr = 0.15 * (1.0 + env * 0.5);
  let speed = 3.0 + mids * 1.5;

  let push = smoothstep(0.4, 0.0, dist);
  let vOffset = push * bendStr * sin(dist * 20.0 - time * 2.0);
  let scanVal = sin((uv.y + vOffset) * lines - time * speed);
  let scanLine = smoothstep(0.0, 1.0, scanVal);

  var rippleDisp = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rElapsed = time - ripple.z;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
      rippleDisp = rippleDisp + rWave * smoothstep(0.3, 0.0, rDist);
    }
  }
  let totalVOffset = vOffset + rippleDisp * 0.05;

  let displacement = vec2<f32>(totalVOffset * 0.1, totalVOffset);
  let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseSample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var color = baseSample.rgb;

  let quantized = quantize(color, quantLevel);
  let edgeDetect = abs(color.r - quantized.r) + abs(color.g - quantized.g) + abs(color.b - quantized.b);
  let isEdge = step(0.1, edgeDetect);
  color = mix(quantized, color, isEdge * 0.3);

  let edgeFactor = blockEdgeFactor(uv, blockSize);
  let edgeNoise = hash2(uv * 1000.0 + time) * 0.1;
  color = color * (1.0 - edgeFactor * 0.3) + vec3<f32>(edgeFactor * edgeNoise);
  color = mix(color, color * vec3<f32>(1.0, 0.98, 1.02), edgeFactor * 0.5);

  if (mvVisibility > 0.01) {
    let blockIdx = floor(uv * blockSize);
    let angle = sin(blockIdx.x * 0.5 + time * 0.5) * cos(blockIdx.y * 0.3 + time * 0.3) * 6.28318;
    let magnitude = 0.5 + 0.5 * sin(blockIdx.x * 0.7 + blockIdx.y * 0.4 + time * 0.8);
    let mv = vec2<f32>(cos(angle), sin(angle)) * magnitude * 0.02;
    let mvColor = vec3<f32>(0.5 + mv.x * 10.0, 0.5 + mv.y * 10.0, 0.3);
    let blockUV = fract(uv * blockSize) - 0.5;
    let arrowMask = smoothstep(0.15, 0.1, length(blockUV));
    color = mix(color, mvColor, arrowMask * mvVisibility * 0.5);
  }

  let blockIdx = floor(uv * blockSize);
  let blockHash = hash2(blockIdx * 0.1);
  let timeHash = hash2(vec2<f32>(floor(time * effectiveGlitchFreq), 0.0));
  if (blockHash < 0.02 && timeHash < 0.3) {
    let garble = hash3(vec3<f32>(uv * 50.0, time));
    color = vec3<f32>(garble, fract(garble * 1.5), fract(garble * 2.3));
  }

  let isGlitch = glitchProbability(time, effectiveGlitchFreq) > 0.5;
  if (isGlitch) {
    let glitchPattern = hash3(vec3<f32>(uv * 20.0, floor(time * effectiveGlitchFreq)));
    let shiftUV = clamp(uv + vec2<f32>(glitchPattern - 0.5, 0.0) * 0.1, vec2<f32>(0.0), vec2<f32>(1.0));
    let shiftedColor = textureSampleLevel(readTexture, u_sampler, shiftUV, 0.0).rgb;
    color = mix(color, shiftedColor, 0.5) + vec3<f32>(glitchPattern * 0.2);
  }

  let distortionMag = abs(totalVOffset) * 4.0;
  let feedbackMix = tentAlpha(distortionMag) * mix(0.1, 0.22, u.zoom_params.z);
  color = mix(color, prevFrame.rgb, feedbackMix);

  color = color * (0.8 + 0.2 * scanLine);

  let bandBin = min(u32(uv.x * 8.0), 7u) + 1u;
  color = color + vec3<f32>(plasmaBuffer[bandBin].x * 0.03, plasmaBuffer[bandBin].y * 0.02, plasmaBuffer[bandBin].z * 0.025);

  color = acesToneMap(color * (0.95 + bass * 0.06));

  let glitchProb = select(0.0, 1.0, isGlitch);
  let distortionIntensity = abs(totalVOffset) * 10.0;
  let alpha = clamp(baseSample.a * (1.0 - distortionIntensity * 0.08) + distortionIntensity * 0.05 + glitchProb * 0.25 + env * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, env));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
