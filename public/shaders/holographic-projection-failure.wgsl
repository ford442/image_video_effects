// Holographic Projection Failure v2 — faulty holo-emitter with CRT V-hold rolling, chromatic RGB beam desync, and phase tearing.
// A/C stores ACES display RGBA for phosphor beam decay persistence; B is unused; depth passes through source depth.

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

const TAU: f32 = 6.283185307179586;

fn rand(co: vec2<f32>) -> f32 {
  return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn bitTruncate(v: f32, bits: f32) -> f32 {
  let levels = exp2(bits);
  return floor(v * levels) / levels;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let instability = (0.2 + u.zoom_params.x * 1.8) * (1.0 + bass * 0.45);
  let chromaticSplit = (0.2 + u.zoom_params.y * 1.8) * (1.0 + mids * 0.35);
  let vHoldDrift = (0.2 + u.zoom_params.z * 1.8) * (1.0 + bass * 0.25);
  let staticAmount = (0.15 + u.zoom_params.w * 1.85) * (1.0 + treble * 0.4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interactions = severe desynchronization fault lines
  var rippleJitter = vec2<f32>(0.0);
  var rippleFlash = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.4 + bass * 0.15);
      let tear = sin((rd - front) * 65.0) * exp(-abs(rd - front) * 24.0) * exp(-age * 1.2);
      rippleJitter.x += tear * 0.05;
      rippleFlash += abs(tear) * 0.3;
    }
  }

  // Scanline V-Hold rolling desync
  let scanlineBand = floor(uv.y * resolution.y / 4.0);
  let bandNoise = rand(vec2<f32>(scanlineBand, floor(time * 8.0)));
  let scanGlitch = step(0.92 - instability * 0.15, bandNoise) * (bandNoise - 0.5) * 0.08 * instability;

  let rollPhase = fract(time * (0.2 + vHoldDrift * 0.6));
  let rollDisplace = sin(uv.y * 3.0 + rollPhase * TAU) * 0.03 * vHoldDrift;

  var driftUV = uv + vec2<f32>(scanGlitch + rippleJitter.x, rollDisplace);

  // Mouse stabilizes the projection in a local repair field
  var repairMask = 0.0;
  if (hasMouse) {
    let mDist = length((uv - mousePos) * aspectVec);
    let repairRadius = select(0.22, 0.38, held);
    repairMask = smoothstep(repairRadius, 0.0, mDist);
    driftUV = mix(driftUV, uv, repairMask * 0.85);
  }

  // Multi-band chromatic aberration
  let shift = chromaticSplit * 0.03 * (1.0 - repairMask * 0.7) * (0.8 + depth * 0.4);
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var chromatic = vec3<f32>(rSample, gSample, bSample);

  // Holographic carrier interference fringes
  let holoPhase = uv.y * resolution.y * 0.8 + time * 14.0 + depth * TAU;
  let interference = 0.85 + 0.15 * sin(holoPhase);
  chromatic *= interference;

  // Block quantization & DAC bit-depth truncation failure
  let blockSize = mix(32.0, 6.0, instability);
  let blockCoord = floor(driftUV * resolution / blockSize);
  let blockRand = rand(blockCoord + floor(time * 6.0));
  let isBlockFault = step(1.0 - instability * 0.3, blockRand);

  let bitDepth = mix(8.0, 3.0, instability * staticAmount);
  let truncated = vec3<f32>(
    bitTruncate(chromatic.r, bitDepth),
    bitTruncate(chromatic.g, bitDepth),
    bitTruncate(chromatic.b, bitDepth)
  );
  var outRGB = mix(chromatic, truncated, isBlockFault * 0.7 * (1.0 - repairMask));

  // High-frequency holographic static and noise bursts
  let noiseStatic = (rand(uv * resolution + time * 120.0) - 0.5) * staticAmount * 0.35 * (1.0 - repairMask * 0.8);
  outRGB += vec3<f32>(noiseStatic) + vec3<f32>(rippleFlash);

  // CRT flicker
  let flicker = 0.94 + 0.06 * sin(time * 60.0);
  outRGB *= flicker;

  // Exact previous frame history load for holographic beam persistence
  let history = historyAt(uv - rippleJitter * 0.5, resolution);
  var hdr = outRGB + history.rgb * 0.065;

  let alpha = clamp(0.75 + interference * 0.2 + repairMask * 0.15, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
