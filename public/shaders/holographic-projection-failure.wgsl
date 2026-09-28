// ═══════════════════════════════════════════════════════════════════
//  Holo-Projection Failure v2
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, click-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: emitter cone (cyan carrier cast from bottom-centre, brightness + fringe pitch fall off with distance, alpha = carrier transmission); stale-frame tear bands read the shifted C frame; re-sync lock line sweeping down inside the repair circle (held = faster)
//  A packing: pre-ACES linear display RGB + transmission alpha; C read back as that linear colour for beam persistence and the stale tear bands (ACES on writeTexture only)
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

// Exact history load (C = last frame's pre-ACES linear RGB + alpha).
fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return clamp(textureLoad(dataTextureC, coord, 0), vec4<f32>(0.0), vec4<f32>(4.0));
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
  let vHoldBase = 0.2 + u.zoom_params.z * 1.8;
  let vHoldDrift = vHoldBase * (1.0 + bass * 0.25);
  let staticAmount = (0.15 + u.zoom_params.w * 1.85) * (1.0 + treble * 0.4);

  let depth = textureLoad(readDepthTexture, coord, 0).r;

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // IDEA 1 — emitter cone. The hologram is cast from an emitter at bottom-centre (screen y=1).
  // Distance from the emitter drives brightness falloff, fringe pitch and carrier transmission;
  // outside the cone's half-angle the carrier thins out (bottom corners fade).
  let emitter = vec2<f32>(0.5, 1.0);
  let eDelta = (uv - emitter) * aspectVec;
  let eDist = length(eDelta);
  let coneRatio = abs(eDelta.x) / max(-eDelta.y, 0.02);
  let coneEdge = 1.0 - 0.65 * smoothstep(0.85, 1.35, coneRatio);
  let throwFalloff = 1.0 - 0.35 * smoothstep(0.15, 1.6, eDist);
  let carrier = coneEdge * throwFalloff;

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

  // Scanline V-Hold rolling desync (tear bands)
  let scanlineBand = floor(uv.y * resolution.y / 4.0);
  let bandNoise = rand(vec2<f32>(scanlineBand, floor(time * 8.0)));
  let tearBand = step(0.92 - instability * 0.15, bandNoise);
  let scanGlitch = tearBand * (bandNoise - 0.5) * 0.08 * instability;

  // Accumulated roll phase: bass offsets the phase instead of scaling the rate (no jumps).
  let rollPhase = fract(time * (0.2 + vHoldBase * 0.6) + bass * 0.06);
  let rollDisplace = sin(uv.y * 3.0 + rollPhase * TAU) * 0.03 * vHoldDrift;

  var driftUV = uv + vec2<f32>(scanGlitch + rippleJitter.x, rollDisplace);

  // Mouse stabilizes the projection in a local repair field.
  // IDEA 3 — re-sync sweep: a horizontal lock line sweeps down through the circle; rows it has
  // already passed are locked, rows below it are still waiting to re-sync. Holding widens the
  // circle (HEAD) and speeds the sweep.
  var repairMask = 0.0;
  var lockLine = 0.0;
  if (hasMouse) {
    let mDist = length((uv - mousePos) * aspectVec);
    let repairRadius = select(0.22, 0.38, held);
    let circle = smoothstep(repairRadius, 0.0, mDist);
    let sweepRate = select(0.45, 1.1, held);
    let sweepY = mousePos.y - repairRadius + fract(time * sweepRate) * 2.0 * repairRadius;
    let locked = smoothstep(-0.004, 0.004, sweepY - uv.y);
    repairMask = circle * mix(0.45, 1.0, locked);
    lockLine = exp(-abs(uv.y - sweepY) * resolution.y * 0.45) * smoothstep(repairRadius, repairRadius * 0.6, mDist);
    driftUV = mix(driftUV, uv, repairMask * 0.85);
  }

  // Multi-band chromatic aberration
  let shift = chromaticSplit * 0.03 * (1.0 - repairMask * 0.7) * (0.8 + depth * 0.4);
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(driftUV - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let srcAlpha = textureSampleLevel(readTexture, u_sampler, clamp(driftUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;
  var chromatic = vec3<f32>(rSample, gSample, bSample);

  // IDEA 2 — stale-frame tear bands: the torn rows show the PREVIOUS picture (C), shifted by the
  // same tear offset, so the tears reveal stale frame data rather than a displaced live image.
  let stale = historyAt(driftUV + vec2<f32>(scanGlitch * 1.5, 0.0), resolution);
  chromatic = mix(chromatic, stale.rgb, tearBand * 0.8 * (1.0 - repairMask));

  // Holographic carrier interference fringes — concentric on the emitter; pitch tightens with throw.
  let holoPhase = eDist * resolution.y * 0.8 * (1.0 + eDist * 0.45) + time * 14.0 + depth * TAU;
  let interference = 0.85 + 0.15 * sin(holoPhase);
  chromatic *= interference;

  // Block quantization & DAC bit-depth truncation failure (clamped: instability can exceed 1.5
  // with bass, which drove blockSize <= 0 and bitDepth negative at HEAD).
  let blockSize = clamp(mix(32.0, 6.0, instability), 3.0, 32.0);
  let blockCoord = floor(driftUV * resolution / blockSize);
  let blockRand = rand(blockCoord + floor(time * 6.0));
  let isBlockFault = step(1.0 - instability * 0.3, blockRand);

  let bitDepth = clamp(mix(8.0, 3.0, instability * staticAmount), 1.0, 8.0);
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

  // IDEA 1 (cont.) — cyan carrier cast: throw falloff + cone edge, tinted toward the emitter's
  // carrier colour as the picture thins out; re-sync lock line glows in the same carrier cyan.
  let carrierTint = mix(vec3<f32>(1.0), vec3<f32>(0.72, 1.0, 1.06), (1.0 - carrier) * 0.9);
  outRGB = outRGB * carrier * carrierTint;
  outRGB += vec3<f32>(0.35, 0.95, 1.0) * lockLine * 0.55;

  // Exact previous frame history load for holographic beam persistence (linear, pre-ACES).
  let history = historyAt(uv - rippleJitter * 0.5, resolution);
  var hdr = max(outRGB + history.rgb * 0.065, vec3<f32>(0.0));

  // Semantic alpha = carrier transmission: the hologram is translucent where the throw is long
  // or outside the cone, denser where the picture is bright, inside the repair circle, and on fringes.
  let hdrLuma = dot(hdr, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp((0.55 + hdrLuma * 0.25 + interference * 0.15 + repairMask * 0.15) * carrier * max(srcAlpha, 0.35) + lockLine * 0.3, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
  textureStore(writeTexture, coord, vec4<f32>(aces(hdr), alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
