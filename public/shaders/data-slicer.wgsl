// ================================================================
//  Data Slicer — Batch 66
//  fp128 slice phase, continuous jitter waves, voronoi cracks,
//  C smear along slices, racing horizontal packet, capped clicks,
//  held intensifies chaos, ACES + semantic alpha.
// ================================================================

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
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  let f = e - (t - p);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var total = 0.0;
  var amplitude = 1.0;
  var frequency = 1.0;
  var maxVal = 0.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total = total + amplitude * noise2(p * frequency);
    maxVal = maxVal + amplitude;
    amplitude = amplitude * gain;
    frequency = frequency * lacunarity;
  }
  return total / maxVal;
}

fn voronoiF2F1(p: vec2<f32>, time: f32) -> vec2<f32> {
  let n = floor(p);
  let f = fract(p);
  var minDist1 = 100.0;
  var minDist2 = 100.0;
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let h = hash22(n + g);
      let o = vec2<f32>(sin(h.x * TAU + time * 0.45), cos(h.y * TAU + time * 0.38)) * 0.3 + 0.5;
      let r = g + o - f;
      let d = dot(r, r);
      if (d < minDist1) {
        minDist2 = minDist1;
        minDist1 = d;
      } else if (d < minDist2) {
        minDist2 = d;
      }
    }
  }
  return vec2<f32>(sqrt(minDist1), sqrt(minDist2));
}

fn domainWarp(p: vec2<f32>, time: f32, strength: f32, bass: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm(p + vec2<f32>(0.0, 0.0) + time * 0.22, 5, 2.1, 0.5),
    fbm(p + vec2<f32>(5.2, 1.3) + time * 0.18, 5, 2.1, 0.5)
  );
  let r = vec2<f32>(
    fbm(p + 3.0 * q + vec2<f32>(1.7, 9.2) + time * 0.12 + bass * 0.5, 4, 2.0, 0.5),
    fbm(p + 3.0 * q + vec2<f32>(8.3, 2.8) + time * 0.14 + bass * 0.3, 4, 2.0, 0.5)
  );
  return p + strength * r;
}

fn quasicrystal(p: vec2<f32>, time: f32, freq: f32) -> f32 {
  var value = 0.0;
  for (var i = 0; i < 5; i = i + 1) {
    let angle = f32(i) * TAU / 5.0 + time * 0.08;
    let dir = vec2<f32>(cos(angle), sin(angle));
    value = value + cos(dot(p, dir) * freq);
  }
  return value / 5.0;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn slice_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (1.5 + speed * 4.0));
  let d = abs(uv.x - head);
  return pow(max(0.0, 1.0 - d * 12.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }
  let pixel = vec2<i32>(gid.xy);

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let aspect = resolution.x / resolution.y;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let jitterSpeed = 0.15 + zp.x * 3.5;
  let sliceThickness = mix(0.006, 0.12, zp.y);
  let chaosAmount = zp.z * 0.12 * select(1.0, 1.35, held);
  let colorSplit = zp.w * 0.03;

  let warpedUV = domainWarp(uv * vec2<f32>(aspect * 3.0, 3.0), time, chaosAmount * 2.0, bass);

  let slicePhase = fp128_mul(fp128(warpedUV.y / sliceThickness), fp128(1.0));
  let sliceIndex = floor(fp128_val(slicePhase));
  let localY = fract(fp128_val(slicePhase));

  let voro = voronoiF2F1(uv * 8.0 + vec2<f32>(time * 0.35, sliceIndex * 0.5), time);
  let cellEdge = smoothstep(0.02, 0.08, voro.y - voro.x);
  let qc = quasicrystal(uv * 12.0, time * 0.35 + bass * 2.0, 2.0 + mids * 3.0);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, mouseDist);

  let jitterT = time * jitterSpeed * 6.0;
  let fbmJitter = (fbm(vec2<f32>(sliceIndex, jitterT) + vec2<f32>(sin(jitterT * 0.7), cos(jitterT * 0.5)), 6, 2.1, 0.5) - 0.5) * chaosAmount * (1.0 + bass * 0.8 + mouseMask * 0.5);

  let wave1 = sin(sliceIndex * 0.33 + time * jitterSpeed * 5.0 + uv.x * 18.0) * chaosAmount * 0.30;
  let wave2 = cos(sliceIndex * 0.71 + time * jitterSpeed * 3.7 + uv.x * 31.0) * chaosAmount * 0.15;
  let wave3 = sin(sliceIndex * 1.13 + time * jitterSpeed * 7.2 + uv.y * 23.0) * chaosAmount * 0.08;
  let totalWave = wave1 + wave2 + wave3;

  let sliceBend = sin(localY * TAU + time * 2.0 + sliceIndex * 0.4 + fbm(vec2<f32>(localY, sliceIndex) + time * 0.35, 4, 2.0, 0.5) * PI) * chaosAmount * 0.18;
  let fractalDisplacement = (fbmJitter + totalWave + sliceBend * mouseMask) * (1.0 + bass * 0.5);
  let packet = slice_packet(uv, time, jitterSpeed);

  let baseUV = clamp(uv + vec2<f32>(fractalDisplacement + qc * chaosAmount * 0.3 * cellEdge + packet * chaosAmount * 0.04, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let splitStrength = colorSplit * (0.4 + mouseMask) * (1.0 + treble * 0.5);
  let curlAngle = fbm(uv * 5.0 + time * 0.25, 4, 2.0, 0.5) * PI;
  let rotatedSplit = vec2<f32>(
    splitStrength * cos(curlAngle),
    splitStrength * sin(curlAngle)
  );

  let sampleR = clamp(baseUV + rotatedSplit, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleB = clamp(baseUV - rotatedSplit, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, baseUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b
  );

  let prev = textureLoad(dataTextureC, pixel, 0);
  finalColor = mix(finalColor, prev.rgb * 0.9, packet * 0.18);

  let scanGlow = (1.0 - smoothstep(0.15, 0.50, abs(localY - 0.5))) * (0.08 + 0.18 * mids);
  let cellGlow = cellEdge * (0.05 + 0.12 * treble);

  let glitchTint1 = mix(vec3<f32>(0.05, 0.65, 1.0), vec3<f32>(1.0, 0.35, 0.85), treble * 0.6 + mouseMask * 0.25);
  let glitchTint2 = mix(vec3<f32>(1.0, 0.8, 0.1), vec3<f32>(0.2, 1.0, 0.5), bass * 0.7);
  let glitchTint = mix(glitchTint1, glitchTint2, fbm(uv * 3.0 + time * 0.12, 4, 2.0, 0.5));

  finalColor = finalColor + glitchTint * (scanGlow + cellGlow + packet * 0.15) * (1.0 + bass * 0.4);

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.02, 0.0, abs(rDist - age * 0.34)) * exp(-age * 1.8);
    }
  }
  finalColor = finalColor + glitchTint * clickBurst * 0.35;

  let sparkle = hash12(vec2<f32>(gid.xy) + vec2<f32>(time * 12.0, time * 8.0)) * treble * 0.15 * mouseMask;
  finalColor = finalColor + vec3<f32>(sparkle);

  finalColor = acesToneMap(finalColor);
  let finalAlpha = clamp(0.76 + mouseMask * 0.12 + abs(fractalDisplacement) * 1.4 + cellEdge * 0.2 + clickBurst * 0.1, 0.45, 0.98);

  let baseDepth = textureLoad(readDepthTexture, vec2<i32>(clamp(vec2<i32>(baseUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1))), 0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + scanGlow + mouseMask * 0.25 + cellEdge * 0.15, 0.25 + chaosAmount * 2.0), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(finalColor, finalAlpha));
}
