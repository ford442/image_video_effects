// ═══════════════════════════════════════════════════════════════════
//  Holographic Glitch
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, click-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: emitter flicker (random blackouts + slow luminance sag on the Flicker slider); grating-order ghosts (±1-order hue-split copies along the shear axis, scaled by Holographic Intensity); peel shadow (the folded crest casts a soft contact shadow onto the image beneath)
//  A packing: pre-ACES linear display RGB + transmission alpha; C read back as that linear colour by the three per-channel history taps (ACES on writeTexture only)
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

// Exact history load; C holds last frame's pre-ACES linear RGB (bounded).
fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return clamp(textureLoad(dataTextureC, historyCoord(uv, resolution), 0), vec4<f32>(0.0), vec4<f32>(4.0));
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn spectrum(t: f32) -> vec3<f32> {
  return 0.52 + 0.48 * cos(TAU * (vec3<f32>(0.01, 0.34, 0.67) + t));
}

fn sampleRGB(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

// Peel fold height at an arbitrary point (used to cast the crest's shadow, idea 3).
fn peelFoldAt(p: vec2<f32>, mouse: vec2<f32>, aspectVec: vec2<f32>, phase: f32, heldGain: f32) -> f32 {
  let d = length((p - mouse) * aspectVec);
  return sin(d * 38.0 - phase) * smoothstep(0.42, 0.0, d) * heldGain;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;   // half-texel (floor fix)
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
  let glitchIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let holoIntensity = clamp(u.zoom_params.y, 0.0, 1.0);
  let rgbShift = clamp(u.zoom_params.z, 0.0, 1.0);
  let phaseInstability = clamp(u.zoom_params.w, 0.0, 1.0);   // "Flicker" slider: phase instability (HEAD) + emitter flicker (idea 1)

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerDir = pointerDelta / max(pointerDist, 0.0001);
  let heldGain = select(0.18, 1.0, held);
  let peelMask = smoothstep(0.42, 0.0, pointerDist) * heldGain;
  // Audio offsets phase rather than scaling the rate (no phase jumps on transients).
  let peelPhase = time * 2.0 + mids * 0.8;
  let peelFold = sin(pointerDist * 38.0 - peelPhase) * peelMask;

  var desync = 0.0;
  var clickDirection = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let delta = (uv - ripple.xy) * aspectVec;
      let dist = length(delta);
      let front = age * (0.34 + bass * 0.09);
      let pulse = sin((dist - front) * 83.0) * exp(-abs(dist - front) * 31.0) * exp(-age * 1.2);
      desync += pulse;
      clickDirection += delta / max(dist, 0.0001) * pulse;
    }
  }

  // Continuous row phase: spatially blocky, temporally smooth (no floor(time)).
  let row = floor(uv.y * (26.0 + glitchIntensity * 58.0));
  let phaseNoise = valueNoise(vec2<f32>(row * 0.173 + sin(time * 0.23),
                                        time * (0.7 + phaseInstability * 3.8) + row * 0.071));
  let carrier = sin(uv.y * resolution.y * (0.18 + phaseInstability * 0.72) +
                    time * 2.0 + treble * 1.5 + phaseNoise * TAU);
  let continuousShear = (phaseNoise - 0.5) * glitchIntensity * (0.025 + bass * 0.035) +
                        carrier * glitchIntensity * 0.004;
  let peelOffset = pointerDir / aspectVec * peelFold * (0.008 + holoIntensity * 0.018);
  let clickOffset = clickDirection / aspectVec * desync * glitchIntensity * 0.006;
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let warpedUV = clamp(uv + vec2<f32>(continuousShear, 0.0) + peelOffset + clickOffset +
                       vec2<f32>((depth - 0.5) * rgbShift * 0.004, 0.0),
                       vec2<f32>(0.0), vec2<f32>(1.0));

  let chromaDir = normalize((warpedUV - 0.5) * aspectVec + vec2<f32>(0.0001)) / aspectVec;
  let chromaAmount = rgbShift * (0.0015 + bass * 0.0035 + abs(desync) * 0.0025);
  let red = textureSampleLevel(readTexture, u_sampler,
                               clamp(warpedUV + chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler,
                                clamp(warpedUV - chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

  let trailVelocity = vec2<f32>(continuousShear * 0.35, carrier * 0.0015) + peelOffset * 0.3;
  let historyR = historyAt(uv - trailVelocity + chromaDir * chromaAmount * 0.8, resolution);
  let historyG = historyAt(uv - trailVelocity * 0.65, resolution);
  let historyB = historyAt(uv - trailVelocity - chromaDir * chromaAmount * 0.8, resolution);
  let historyRGB = vec3<f32>(historyR.r, historyG.g, historyB.b);
  let historyAlpha = max(historyR.a, max(historyG.a, historyB.a));

  let interferencePhase = uv.x * (9.0 + holoIntensity * 20.0) +
                           uv.y * 5.0 + time * 0.55 + mids * 0.5 +
                           depth * 7.0 + peelFold * 2.5 + desync;
  let hologram = spectrum(interferencePhase / TAU) * (0.22 + holoIntensity * 1.15);
  let scan = 0.5 + 0.5 * sin(uv.y * resolution.y * 0.68 + time * 3.0 + treble * 2.0);
  let scanMask = mix(0.76, 1.08, scan) * (1.0 + treble * 0.12);
  let rimBase = max(1.0 - pointerDist / 0.42, 0.0);
  let peelRim = rimBase * rimBase * abs(peelFold);
  var hdr = vec3<f32>(red, green, blue) * scanMask;

  // IDEA 2 — grating-order ghosts. The interference grating diffracts ±1-order copies of the
  // image along the shear (x) axis. Each order is dispersed per channel (red thrown further than
  // blue) so the ghosts are hue-split; they brighten with Holographic Intensity and fade in the
  // row-phase troughs like the overlay itself.
  let orderStep = (0.012 + holoIntensity * 0.045) / aspectVec.x;
  let dispersion = vec3<f32>(1.25, 1.0, 0.78);
  let plusOrder = vec3<f32>(
    sampleRGB(warpedUV + vec2<f32>(orderStep * dispersion.x, 0.0)).r,
    sampleRGB(warpedUV + vec2<f32>(orderStep * dispersion.y, 0.0)).g,
    sampleRGB(warpedUV + vec2<f32>(orderStep * dispersion.z, 0.0)).b);
  let minusOrder = vec3<f32>(
    sampleRGB(warpedUV - vec2<f32>(orderStep * dispersion.x, 0.0)).r,
    sampleRGB(warpedUV - vec2<f32>(orderStep * dispersion.y, 0.0)).g,
    sampleRGB(warpedUV - vec2<f32>(orderStep * dispersion.z, 0.0)).b);
  let orderGain = holoIntensity * (0.14 + phaseNoise * 0.12) * (0.8 + mids * 0.3);
  hdr += (plusOrder * vec3<f32>(1.0, 0.85, 0.7) + minusOrder * vec3<f32>(0.7, 0.85, 1.0)) * orderGain;

  hdr = mix(hdr, hologram + source.rgb * 0.24, holoIntensity * (0.38 + phaseNoise * 0.28));
  hdr += spectrum(time * 0.08 + pointerDist + mids * 0.12) * peelRim * (0.45 + treble * 0.7);
  hdr += spectrum(desync * 0.2 + time * 0.04) * abs(desync) * (0.22 + bass * 0.4);

  // IDEA 3 — peel shadow. The raised crest (peelFold > 0) casts a soft contact shadow onto the
  // image beneath it: evaluate the fold a little "under" this pixel (down-screen and away from
  // the pointer) — where a crest sits there, this pixel is in its shadow, unless it is itself lifted.
  let shadowOffset = (pointerDir / aspectVec) * 0.018 + vec2<f32>(0.0, -0.014);
  let crestAbove = max(peelFoldAt(uv - shadowOffset, mouse, aspectVec, peelPhase, heldGain), 0.0);
  let crestHere = max(peelFold, 0.0);
  let peelShadow = crestAbove * (1.0 - crestHere) * 0.55;
  hdr *= 1.0 - peelShadow;

  let trailMix = clamp(0.10 + phaseInstability * 0.30 + glitchIntensity * 0.12, 0.08, 0.48);
  hdr = mix(hdr, historyRGB * (0.90 + holoIntensity * 0.08), trailMix);

  // IDEA 1 — emitter flicker on the Flicker slider: short random blackouts (a few frames, hashed
  // at 24 Hz) plus a slow luminance sag as the emitter's supply wanders. Default 0.4 stays mild.
  let flickTick = floor(time * 24.0);
  let blackoutOdds = phaseInstability * 0.05;
  let blackout = step(1.0 - blackoutOdds, hash21(vec2<f32>(flickTick, 17.3)));
  let sag = valueNoise(vec2<f32>(time * 0.9, 4.7)) * phaseInstability * 0.28;
  let emitterGain = (1.0 - sag) * mix(1.0, 0.10, blackout);
  hdr = max(hdr * emitterGain, vec3<f32>(0.0));

  // Semantic alpha: source coverage times hologram transmission (brighter carrier = denser).
  let transmission = clamp(0.45 + luma(hdr) * 0.4 + historyAlpha * trailMix * 0.25 + peelRim * 0.2, 0.0, 1.0);
  let alpha = clamp(max(source.a, 0.25) * transmission * mix(1.0, 0.35, blackout), 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
  textureStore(writeTexture, coord, vec4<f32>(aces(hdr), alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
