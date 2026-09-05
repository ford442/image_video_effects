// ═══════════════════════════════════════════════════════════════════
//  Signal Noise — Batch 62
//  Analog VHS/DCT noise: spring cursor, held burst, capped ripples,
//  exact C temporal smear, regional FFT, ACES + semantic alpha.
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 6; i = i + 1) {
    if (i >= octaves) { break; }
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
  let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
  let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
  return vec3<f32>(y, u, v);
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  let r = yuv.x + 1.13983 * yuv.z;
  let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
  let b = yuv.x + 2.03211 * yuv.y;
  return vec3<f32>(r, g, b);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn vhsHeadSwitch(uv: vec2<f32>, time: f32, intensity: f32, bass: f32) -> f32 {
  let bandPos = 0.92 + 0.02 * sin(time * 2.5) - bass * 0.1;
  let inBand = smoothstep(bandPos - 0.03, bandPos, uv.y) *
               smoothstep(bandPos + 0.08, bandPos + 0.03, uv.y);
  let lineNoise = hash11(floor(uv.x * 80.0) + time * 25.0) * 2.0 - 1.0;
  return lineNoise * intensity * inBand * (1.0 + bass * 2.0);
}
fn dctBlockArtifact(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32, mids: f32) -> vec3<f32> {
  let blockId = floor(uv / blockSize);
  let localUV = fract(uv / blockSize);
  let checker = fract(blockId.x + blockId.y) * 2.0 - 1.0;
  let ring = sin(localUV.x * 3.14159 * 8.0) * sin(localUV.y * 3.14159 * 8.0);
  let rnd = hash21(blockId + vec2<f32>(time * 0.2, 5.91));
  let artifact = (ring * 0.7 + checker * 0.3) * rnd * intensity * (1.0 + mids);
  return vec3<f32>(artifact);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = vec2<f32>(u.config.z, u.config.w);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
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

  var rippleNoise = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.3) {
      rippleNoise = max(rippleNoise, smoothstep(0.12, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age * 0.8));
    }
  }

  let vhsIntensity = u.zoom_params.x * (1.0 + bass * 0.5) * select(1.0, 1.3, held);
  let artifactStrength = u.zoom_params.y * (1.0 + mids * 0.5) + rippleNoise * 0.25;
  let smearAmount = u.zoom_params.z;
  let chromaStrength = u.zoom_params.w + treble * 0.1;

  let mousePull = (uv - smoothMouse) * exp(-length((uv - smoothMouse) * vec2<f32>(aspect, 1.0)) * 5.0) * 0.015 * select(0.0, 1.0, held);
  let noiseUV = uv + mousePull;

  let noise = fbm(noiseUV * 8.0 + time * 1.5, 4);
  let vhsNoise = vhsHeadSwitch(noiseUV, time, vhsIntensity, bass);
  let blockArtifact = dctBlockArtifact(noiseUV, 0.06, artifactStrength, time, mids);
  let bandBin = min(u32(uv.x * 8.0), 7u) + 1u;
  let fftNoise = plasmaBuffer[bandBin].x * 0.15;

  let noiseDir = fbm(noiseUV * 4.0 + time * 0.7, 3) * 6.28318;
  let glitchDisp = step(0.9, hash21(vec2<f32>(noiseUV.y * 10.0, time))) * treble * 0.1 + rippleNoise * 0.05;
  let uvGlitch = noiseUV + vec2<f32>(glitchDisp, 0.0);

  let offR = vec2<f32>(cos(noiseDir), sin(noiseDir)) * chromaStrength * 0.02;
  let offG = vec2<f32>(cos(noiseDir + 2.094), sin(noiseDir + 2.094)) * chromaStrength * 0.02;
  let offB = vec2<f32>(cos(noiseDir + 4.189), sin(noiseDir + 4.189)) * chromaStrength * 0.02;

  let cR = textureSampleLevel(readTexture, u_sampler, uvGlitch + offR, 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, uvGlitch + offG, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, uvGlitch + offB, 0.0);

  var col = vec3<f32>(cR.r, cG.g, cB.b);

  let smearVec = vec2<f32>(
    fbm(uvGlitch * 6.0 + vec2<f32>(time, 0.0), 3),
    fbm(uvGlitch * 6.0 + vec2<f32>(0.0, time), 3)
  ) * 2.0 - 1.0;
  let smearUV = clamp(uvGlitch + smearVec * smearAmount * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
  let smearCol = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
  col = mix(col, smearCol.rgb, smearAmount * 0.5);

  var yuv = rgbToYuv(col);
  yuv.y = yuv.y + (noise - 0.5) * vhsIntensity * 0.3 + blockArtifact.r + fftNoise;
  yuv.z = yuv.z + (vhsNoise - 0.5) * vhsIntensity * 0.3 + blockArtifact.g;
  col = yuvToRgb(yuv);

  let scanline = sin(uv.y * resolution.y * 3.14159) * 0.05 * mids;
  col = col - scanline;

  let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
  let temporalDecay = mix(0.1, 0.8, smearAmount);
  col = mix(col, prevFrame, temporalDecay);

  col = acesToneMap(col * (0.95 + bass * 0.05));

  let noiseIntensity = clamp(noise + abs(vhsNoise) + length(blockArtifact) + glitchDisp + rippleNoise, 0.0, 1.0);
  let alpha = clamp(cG.a * (1.0 - noiseIntensity * 0.4) + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(col, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
