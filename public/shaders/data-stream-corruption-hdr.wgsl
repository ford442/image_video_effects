// ═══════════════════════════════════════════════════════════════════
//  Data Stream Corruption HDR — Batch 67
//  fp128 rain phase, exact C persistence, racing column packets,
//  HDR bloom, capped ripple flashes, held brush, ACES + semantic alpha.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn column_packet(colIndex: f32, time: f32, bass: f32) -> f32 {
  let head = fract(time * (0.8 + bass * 1.5) + colIndex * 0.173);
  return pow(max(0.0, 1.0 - abs(head - 0.5) * 2.0), 6.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let streamSpeed = mix(2.0, 20.0, u.zoom_params.x) * (1.0 + treble * 0.25);
  let brushRadius = mix(0.02, 0.4, u.zoom_params.y) * select(1.0, 1.25, held);
  let maxCorruption = mix(0.0, 1.0, u.zoom_params.z);
  let bloomIntensity = u.zoom_params.w * 2.0 * (1.0 + mids * 0.3);

  let oldState = textureLoad(dataTextureC, pixel, 0);
  var corruption = oldState.r;
  var alphaHistory = oldState.a;

  let mouse = u.zoom_config.yz;
  var dist = 10.0;
  if (mouse.x >= 0.0) {
    let p = uv - mouse;
    dist = length(vec2<f32>(p.x * aspect, p.y));
  }

  let persistence = 0.92;
  if (dist < brushRadius) {
    let strength = smoothstep(brushRadius, brushRadius * 0.5, dist);
    corruption += strength * 0.5;
    alphaHistory = min(alphaHistory + strength * 0.3, 1.0);
  }
  corruption = clamp(corruption * persistence, 0.0, 1.0);
  alphaHistory = alphaHistory * persistence;

  textureStore(dataTextureA, pixel, vec4<f32>(corruption, 0.0, 0.0, alphaHistory));

  let effectiveCorruption = corruption * maxCorruption;

  let numColumns = 80.0;
  let colIndex = floor(uv.x * numColumns + 0.5);
  let colRandom = hash12(vec2<f32>(colIndex, 42.0));
  let rainSpeed = streamSpeed * (0.5 + 0.5 * colRandom);
  let rainPhase = fp128_val(fp128_sum(fp128_mul(fp128(time), fp128(rainSpeed * 0.1)), fp128(uv.y)));
  let numRows = 40.0 * (resolution.y / resolution.x);
  let rowIndex = floor(rainPhase * numRows + 0.5);
  let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
  let isChar = step(0.4, charRandom);
  let packet = column_packet(colIndex, time, bass);

  var sampleUV = uv;
  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  if (effectiveCorruption > 0.01) {
    let blockSize = 0.05;
    let blockX = floor(uv.x / blockSize) * blockSize;
    let blockRandom = hash12(vec2<f32>(blockX, floor(time * 10.0)));
    let displaceY = (blockRandom - 0.5) * 0.1 * effectiveCorruption;
    sampleUV.y += displaceY;

    let displacedSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let rgbSplit = 0.02 * effectiveCorruption * (1.0 + packet * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(rgbSplit, 0.0), 0.0).r;
    let g = displacedSample.g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(rgbSplit, 0.0), 0.0).b;
    let corruptedAlpha = mix(displacedSample.a, alphaHistory, effectiveCorruption * 0.5);
    finalColor = vec4<f32>(r, g, b, corruptedAlpha);

    let streamColor = vec3<f32>(0.2, 1.0, 0.4);
    let streamIntensity = isChar * effectiveCorruption * colRandom * (0.7 + packet * 0.6);
    let streamBlend = streamIntensity * 0.8;
    let newRGB = mix(finalColor.rgb, streamColor, streamBlend);
    let newA = mix(finalColor.a, 0.9 + streamIntensity * 0.1, streamBlend);
    finalColor = vec4<f32>(newRGB, newA);

    if (isChar < 0.5) {
      finalColor = mix(finalColor, vec4<f32>(0.0, 0.0, 0.0, finalColor.a * 0.5), effectiveCorruption * 0.5);
    }
  }

  finalColor = vec4<f32>(finalColor.rgb, clamp(finalColor.a, 0.0, 1.0));

  let sourceColor = finalColor.rgb;
  let maxChannel = max(sourceColor.r, max(sourceColor.g, sourceColor.b));
  let exposure = max(0.0, maxChannel - 1.0);

  var bloom = vec3<f32>(0.0);
  var totalWeight = 0.0;
  let bloomSamples = 12;
  let bloomRadius = 0.02 + effectiveCorruption * 0.04;

  for (var i = 0; i < bloomSamples; i = i + 1) {
    let angle = f32(i) * 6.283185307 / f32(bloomSamples);
    let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
    let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
    let sampleUV2 = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV2, 0.0).rgb;
    let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
    let neighborExposure = max(0.0, neighborMax - 1.0);
    let weight = exp(-f32(i % 4) * 0.5);
    bloom += neighbor * neighborExposure * weight;
    totalWeight += neighborExposure * weight;
  }

  if (totalWeight > 0.001) {
    bloom /= totalWeight;
  }
  bloom *= bloomIntensity;

  var hdrColor = sourceColor + bloom;

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let age = time - ripple.z;
    if (age >= 0.0 && age < 0.5 && rDist < 0.1) {
      let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
      hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
      clickBurst += flash;
    }
  }

  let prevSmear = textureLoad(dataTextureC, pixel, 0).rgb;
  hdrColor = mix(hdrColor, prevSmear * 0.88, effectiveCorruption * 0.08 * (0.4 + packet));

  let band = min(u32(uv.x * 8.0), 7u);
  hdrColor += vec3<f32>(0.04, 0.12, 0.08) * plasmaBuffer[band + 1u].x * effectiveCorruption * 0.15;

  let toneMapExp = 0.8 + effectiveCorruption;
  let ldrColor = toneMapACES(hdrColor * toneMapExp);

  let luma = dot(ldrColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * mix(0.55, 0.92, effectiveCorruption) + exposure * 0.12 + clickBurst * 0.08 + packet * 0.06, 0.06, 0.98);

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeTexture, pixel, vec4<f32>(ldrColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
