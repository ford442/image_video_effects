// ═══════════════════════════════════════════════════════════════════
//  Scan Distort
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: sync-tear band (rows inside the glitch pulse slide along a sawtooth ramp and drag the stale row from C); DCT-basis garble (garbled blocks show hashed cosine basis patterns and the garbled set re-rolls with time); MV arrows from temporal gradient (per-block arrows along -grad(L)*(L-Lprev) from C, dots on still content)
//  A packing: pre-ACES linear display RGB + semantic alpha; C read back as that linear colour (feedback smear, tear-band stale rows, temporal-gradient flow)
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

const PI: f32 = 3.14159265359;
const LUMA: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);

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

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn glitchProbability(time: f32, freq: f32) -> f32 {
  let framePhase = fract(time * freq);
  let seed = hash2(vec2<f32>(floor(time * freq), 0.0));
  return select(0.0, 1.0, framePhase < 0.1 && seed < 0.15);
}

fn srcLuma(uv: vec2<f32>) -> f32 {
  return dot(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, LUMA);
}

// Distance from p to the segment a-b (for the MV arrow shaft).
fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let ab = b - a;
  let t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  return length(p - (a + ab * t));
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
  // Pointer read directly (the old extraBuffer spring was re-zeroed every frame).
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let blockSize = 4.0 + u.zoom_params.x * 12.0 * (1.0 + bass * 0.1);
  let quantLevel = 2.0 + u.zoom_params.y * 62.0;
  let mvVisibility = u.zoom_params.z * (1.0 + mids * 0.15);
  let glitchFreq = (0.1 + u.zoom_params.w * 2.0) * (1.0 + treble * 0.2);

  // C holds last frame's pre-ACES linear colour (A packing).
  let prevFrame = textureLoad(dataTextureC, coord, 0);

  let mouseGlitchBoost = select(0.0, 0.5, held);
  let effectiveGlitchFreq = glitchFreq + mouseGlitchBoost;

  let mouseScanBoost = 1.0 + mouse.y * 0.5;
  let dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));

  let lines = 100.0 * mouseScanBoost;
  let bendStr = 0.15 * (1.0 + bass * 0.5);
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

  let blockIdx = floor(uv * blockSize);
  let blockUV = fract(uv * blockSize) - 0.5;

  if (mvVisibility > 0.01) {
    // IDEA 3 — MV arrows from a per-block temporal gradient. One-pixel Lucas-Kanade at the
    // block centre: spatial gradient from the source (4 taps), temporal difference against C
    // (1 tap, compared with the current quantised/scanlined luma so the processing bias
    // cancels). v = -grad(L) * (L - Lprev) / |grad(L)|^2, clamped; still content gives a
    // near-zero vector and only the HEAD dot remains.
    let centreUV = (blockIdx + 0.5) / blockSize;
    let texel = 1.0 / dims;
    let gx = (srcLuma(centreUV + vec2<f32>(texel.x * 2.0, 0.0)) - srcLuma(centreUV - vec2<f32>(texel.x * 2.0, 0.0))) * 0.5;
    let gy = (srcLuma(centreUV + vec2<f32>(0.0, texel.y * 2.0)) - srcLuma(centreUV - vec2<f32>(0.0, texel.y * 2.0))) * 0.5;
    let grad = vec2<f32>(gx, gy);
    let centreCoord = vec2<i32>(clamp(centreUV * dims, vec2<f32>(0.0), dims - 1.0));
    let centreSrc = textureSampleLevel(readTexture, u_sampler, centreUV, 0.0).rgb;
    let centreScan = 0.8 + 0.2 * smoothstep(0.0, 1.0, sin(centreUV.y * lines - time * speed));
    let lCur = dot(quantize(centreSrc, quantLevel), LUMA) * centreScan;
    let lPrev = dot(max(textureLoad(dataTextureC, centreCoord, 0).rgb, vec3<f32>(0.0)), LUMA);
    var dt = lCur - lPrev;
    dt = sign(dt) * max(abs(dt) - 0.06, 0.0);
    let g2 = dot(grad, grad);
    var flow = -grad * dt / (g2 + 0.002);
    let flowLen = length(flow);
    flow = flow / max(flowLen, 1e-5) * min(flowLen, 4.0);
    let arrowLen = min(flowLen, 4.0) * 0.1;                       // in block units, max 0.4
    let arrowDir = select(vec2<f32>(1.0, 0.0), flow / max(flowLen, 1e-5), flowLen > 1e-5);
    let tip = arrowDir * arrowLen;
    let shaft = smoothstep(0.045, 0.02, segDist(blockUV, vec2<f32>(0.0), tip));
    let headMask = smoothstep(0.09, 0.03, length(blockUV - tip)) * step(0.05, arrowLen);
    let dotMask = smoothstep(0.15, 0.1, length(blockUV));
    let arrowMask = max(dotMask, max(shaft, headMask) * step(0.05, arrowLen));
    let mvColor = vec3<f32>(0.5 + flow.x * 0.125, 0.5 + flow.y * 0.125, 0.3);
    color = mix(color, mvColor, arrowMask * mvVisibility * 0.5);
  }

  // IDEA 2 — DCT-basis garble. A corrupted macroblock decodes as a single cosine basis
  // function: (ku, kv) are hashed per block, the block's chroma phases come from the same
  // hash, and the garbled SET re-rolls each glitch-frequency tick (HEAD's was static).
  let garbleRoll = floor(time * effectiveGlitchFreq);
  let blockHash = hash2(blockIdx * 0.1 + vec2<f32>(garbleRoll * 0.37, garbleRoll * 0.11));
  let timeHash = hash2(vec2<f32>(garbleRoll, 0.0));
  if (blockHash < 0.02 && timeHash < 0.3) {
    let seed = hash2(blockIdx + vec2<f32>(garbleRoll));
    let ku = floor(seed * 7.99);
    let kv = floor(fract(seed * 13.7) * 7.99);
    let local = blockUV + 0.5;
    let basis = cos((2.0 * local.x + 1.0) * ku * PI / 16.0) * cos((2.0 * local.y + 1.0) * kv * PI / 16.0);
    let level = 0.5 + 0.5 * basis;
    let garble = hash3(vec3<f32>(blockIdx, garbleRoll));
    color = vec3<f32>(level, fract(level + garble * 1.5), fract(level + garble * 2.3));
  }

  let isGlitch = glitchProbability(time, effectiveGlitchFreq) > 0.5;
  if (isGlitch) {
    let glitchPattern = hash3(vec3<f32>(uv * 20.0, floor(time * effectiveGlitchFreq)));
    let shiftUV = clamp(uv + vec2<f32>(glitchPattern - 0.5, 0.0) * 0.1, vec2<f32>(0.0), vec2<f32>(1.0));
    let shiftedColor = textureSampleLevel(readTexture, u_sampler, shiftUV, 0.0).rgb;
    color = mix(color, shiftedColor, 0.5) + vec3<f32>(glitchPattern * 0.2);

    // IDEA 1 — sync-tear band. During the pulse a horizontal band loses h-sync: its rows slide
    // sideways along a sawtooth ramp (top of the band barely moves, bottom is thrown far) and
    // the slid rows are STALE — pulled from C — so the tear shows last frame's picture.
    let pulseIdx = floor(time * effectiveGlitchFreq);
    let bandTop = hash2(vec2<f32>(pulseIdx, 7.3)) * 0.8;
    let bandH = 0.08 + hash2(vec2<f32>(pulseIdx, 3.1)) * 0.12;
    let bandT = (uv.y - bandTop) / bandH;
    let inBand = step(0.0, bandT) * step(bandT, 1.0);
    let ramp = fract(bandT * 2.0) * 0.5 + floor(bandT * 2.0) * 0.5;   // 2-step sawtooth
    let slide = (ramp * ramp) * (0.12 + treble * 0.05) * select(-1.0, 1.0, hash2(vec2<f32>(pulseIdx, 1.9)) > 0.5);
    let staleX = clamp(i32(f32(coord.x) - slide * dims.x), 0, i32(dims.x) - 1);
    let stale = max(textureLoad(dataTextureC, vec2<i32>(staleX, coord.y), 0).rgb, vec3<f32>(0.0));
    let tearEdge = smoothstep(0.0, 0.02, bandT) * smoothstep(1.0, 0.98, bandT);
    color = mix(color, stale * (1.0 + ramp * 0.3), inBand * tearEdge * 0.9);
  }

  let distortionMag = abs(totalVOffset) * 4.0;
  let feedbackMix = tentAlpha(distortionMag) * mix(0.1, 0.22, u.zoom_params.z);
  color = mix(color, max(prevFrame.rgb, vec3<f32>(0.0)), feedbackMix);

  color = color * (0.8 + 0.2 * scanLine);

  // Three-band audio lift from plasmaBuffer[0] (the per-column bins were never written).
  color = color + vec3<f32>(bass * 0.03, mids * 0.02, treble * 0.025);
  color = clamp(color * (0.95 + bass * 0.06), vec3<f32>(0.0), vec3<f32>(4.0));

  let glitchProb = select(0.0, 1.0, isGlitch);
  let distortionIntensity = abs(totalVOffset) * 10.0;
  let alpha = clamp(baseSample.a * (1.0 - distortionIntensity * 0.08) + distortionIntensity * 0.05 + glitchProb * 0.25 + bass * 0.15, 0.0, 1.0);

  // A holds the pre-ACES linear colour; ACES only on the displayed RGB.
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
  textureStore(writeTexture, coord, vec4<f32>(acesToneMap(color), alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
