// ═══════════════════════════════════════════════════════════════════
//  Cyber Lens v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration, hud-overlay, glitch
//  Complexity: High
//  Chunks From: cyber-lens
//  Created: 2026-05-31
//  By: 4-Agent Swarm
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 64)
//
//  Brought up to the pool standard: `dataTextureC` was never read, there was no
//  click response, and `dataTextureA` held a mask tuple
//  `[hudIntensity, reticle, flicker, alpha]` that nothing consumed — which also
//  leaves C poisoned for anything reading it as colour (the mask-as-colour trap
//  this pool has hit before). Display RGBA now goes to A and the masks to B.
//
//  TWO NEW STRUCTURES
//
//    1. Rolling-shutter scan skew — a CMOS sensor exposes rows sequentially, so
//       anything moving fast shears diagonally and the HUD tears along scan
//       boundaries. The lens now samples each row at its own exposure time
//       offset, which is the physically correct behaviour for the sensor this
//       effect is imitating and gives the readout genuine motion character
//       instead of a static overlay.
//
//    2. Per-band HUD telemetry rings — eight concentric arcs around the
//       reticle, one per FFT bin, each sweeping at its own rate with its own
//       arc length. The HUD reports the spectrum instead of flickering as one
//       undifferentiated mass.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  let c = x * 0.85 + 0.30;
  return clamp((a / b) * c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hudFlicker(t: f32, bass: f32) -> f32 {
  return 1.0 - step(0.92 + bass * 0.06, fract(sin(t * 37.0) * 43758.5453)) * 0.35;
}

fn hexDist(p: vec2<f32>) -> f32 {
  let s = vec2<f32>(1.0, 1.732);
  let h = s * 0.5;
  let a = fract(p) - 0.5;
  let b = abs(a) - h;
  return dot(max(b, vec2<f32>(0.0)), vec2<f32>(1.0)) + min(max(b.x, b.y), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Param mapping: x=HUDScale, y=TargetSize, z=GlitchIntensity, w=ChromaticAberration
  let hudScale = mix(0.06, 0.45, u.zoom_params.x);
  let targetSize = mix(0.02, 0.18, u.zoom_params.y);
  let glitchIntensity = u.zoom_params.z;
  let chroma = u.zoom_params.w * 0.06;

  // Bass drives HUD flicker frequency
  let flicker = hudFlicker(time, audio.x);
  let bassPulse = 1.0 + audio.x * 0.4;
  let timeWarp = time * bassPulse;

  // ── Structure 1: rolling-shutter scan skew ─────────────────────────────────
  // Each row is exposed at its own instant, so the readout shears with motion.
  let rowTime = uv.y * (0.012 + audio.y * 0.018);
  let shutterPhase = time - rowTime;
  let skew = sin(shutterPhase * 3.1 + uv.y * 24.0) * (0.002 + glitchIntensity * 0.010)
           * (0.4 + audio.z * 1.4);
  let shutterUV = clamp(uv + vec2<f32>(skew, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // Depth controls parallax between HUD layers
  let parallax1 = (uv - 0.5) * depth * 0.04;
  let parallax2 = (uv - 0.5) * depth * 0.015;
  let hudUV1 = uv - parallax1;
  let hudUV2 = uv - parallax2;

  // Cybernetic chromatic aberration around mouse
  let offset = uv - mouse;
  let delta = vec2<f32>(offset.x * aspect, offset.y);
  let dist = length(delta);
  let dir = offset / max(length(offset), 1e-4);
  let lensMask = 1.0 - smoothstep(hudScale, hudScale + 0.03, dist);

  let split = dir * chroma * lensMask * (1.0 + audio.z * 0.6);
  // Sampling happens through the rolling-shutter UV, so the per-row exposure
  // skew reaches the visible image.
  var lensColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(shutterUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, shutterUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(shutterUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // Glitch artifacts: horizontal slice displacement driven by bass
  let glitchSeed = floor(timeWarp * 4.0);
  let glitchLine = step(0.88, hash12(vec2<f32>(glitchSeed, uv.y * 40.0))) * glitchIntensity;
  let glitchOffset = (hash12(vec2<f32>(glitchSeed, floor(uv.y * 40.0))) - 0.5) * 0.08 * bassPulse;
  let glitchUV = vec2<f32>(shutterUV.x + glitchOffset * glitchLine, shutterUV.y);
  let glitchColor = textureSampleLevel(readTexture, u_sampler, clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  lensColor = mix(lensColor, glitchColor, glitchLine);

  // Primary HUD grid (layer 1)
  let gridUV = hudUV1 * 48.0;
  let lineX = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.x - timeWarp * 0.5) - 0.5));
  let lineY = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.y + timeWarp * 0.2) - 0.5));
  let grid = max(lineX, lineY) * flicker * (0.5 + audio.y * 0.7);

  // Scan lines
  let scan = 0.85 + 0.15 * sin(uv.y * dims.y * 0.5 + timeWarp * 9.0);

  // Targeting reticle at mouse (layer 1)
  let reticleDist = length((hudUV1 - mouse) * vec2<f32>(aspect, 1.0));
  let reticleRing = smoothstep(targetSize, targetSize - 0.005, reticleDist) - smoothstep(targetSize - 0.005, targetSize - 0.01, reticleDist);
  let reticleCrossH = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.y - mouse.y))) * step(reticleDist, targetSize * 1.3);
  let reticleCrossV = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.x - mouse.x))) * step(reticleDist, targetSize * 1.3);
  let reticle = (reticleRing + reticleCrossH + reticleCrossV) * flicker;

  // Corner brackets (layer 2)
  let cornerUV = abs(hudUV2 - 0.5);
  let cornerBracket = step(cornerUV.x, 0.04) * step(cornerUV.y, 0.003) + step(cornerUV.x, 0.003) * step(cornerUV.y, 0.04);
  let corner = cornerBracket * flicker;

  // Hexagonal threat zone around mouse (layer 2)
  let hexUV = (hudUV2 - mouse) * vec2<f32>(aspect, 1.0) * 14.0;
  let hex = 1.0 - smoothstep(0.0, 0.04, abs(hexDist(hexUV) - 0.42));
  let hexPulse = sin(timeWarp * 3.0 + audio.x * 6.0) * 0.5 + 0.5;
  let threat = hex * hexPulse * flicker;

  // Cyan holographic HUD composition
  let hudColor = vec3<f32>(0.05, 0.95, 0.95) * (grid + corner * 0.8) +
                 vec3<f32>(0.95, 0.35, 1.0) * reticle * 0.9 +
                 vec3<f32>(1.0, 0.2, 0.3) * threat * 0.7;

  // HDR bloom on active targets (reticle)
  let bloom = reticle * 0.5 * (1.0 + audio.y * 0.6);

  // Noise grain
  let grain = (hash13(vec3<f32>(uv * 300.0, time)) - 0.5) * 0.03;

  // Radial glow under lens
  let radialGlow = exp(-dist * 4.0) * 0.12 * bassPulse;

  // ── Structure 2: per-band HUD telemetry rings ──────────────────────────────
  // Eight arcs around the reticle, one per FFT bin, each with its own sweep
  // rate and arc length.
  let toReticle = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let ringR = length(toReticle);
  let ringA = atan2(toReticle.y, toReticle.x);
  var telemetry = 0.0;
  for (var b = 0u; b < 8u; b = b + 1u) {
    let fb = f32(b);
    let energy = plasmaBuffer[b + 1u].x;
    let radius = targetSize * (1.6 + fb * 0.42);
    let band = exp(-pow((ringR - radius) * 210.0, 2.0));
    // Arc length reports the bin level; sweep direction alternates per ring.
    let sweep = ringA + time * (0.6 + fb * 0.23) * select(1.0, -1.0, (b & 1u) == 1u);
    let arc = smoothstep(0.0, 0.35, sin(sweep) * 0.5 + 0.5 - (1.0 - energy) * 0.6);
    telemetry += band * arc * (0.25 + energy * 1.5);
  }
  telemetry = min(telemetry, 2.0);

  // ── Bounded click target-lock pings ────────────────────────────────────────
  var lockPing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.0) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let front = r - age * 0.45;
      lockPing += exp(-front * front * 320.0) * exp(-age * 1.6);
    }
  }
  lockPing = min(lockPing, 1.5);

  var finalColor = lensColor * scan + hudColor + vec3<f32>(bloom) + grain + radialGlow;
  finalColor += vec3<f32>(0.25, 1.0, 0.75) * telemetry * 0.35;
  finalColor += vec3<f32>(1.0, 0.55, 0.25) * lockPing * (0.5 + audio.x * 0.8);

  // Phosphor persistence (exact load — dataTextureC is rgba32float).
  let prevFrame = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  finalColor = max(finalColor, prevFrame.rgb * (0.70 + glitchIntensity * 0.14));

  finalColor = acesToneMap(finalColor);

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, dist) * 0.2;
  finalColor = finalColor * vignette;

  let hudIntensity = clamp(lensMask + grid * 0.5 + reticle * 0.8 + corner * 0.4
                           + telemetry * 0.3, 0.0, 1.0);
  let targetingConfidence = smoothstep(targetSize * 2.0, 0.0, reticleDist);
  let finalAlpha = clamp(hudIntensity * targetingConfidence * depth
                         + lockPing * 0.25 + telemetry * 0.15, 0.08, 0.98);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.3 + hudIntensity * 0.5, 0.25), 0.0, 1.0);

  let coord = vec2<i32>(gid.xy);
  let outColor = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  // A carries DISPLAY RGBA so the persistence read above is meaningful; the
  // mask tuple that used to live here (and that nothing read) moves to B.
  textureStore(dataTextureA, coord, outColor);
  textureStore(dataTextureB, coord, vec4<f32>(hudIntensity, reticle, flicker, telemetry));
}
