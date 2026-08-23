// ═══════════════════════════════════════════════════════════════════
//  Liquid Rainbow — Spectral Gerstner Sea with Spring-Damped Drag
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, spring-damper-pointer,
//            bounded-click-ripples, audio-reactive, per-band-fft,
//            gerstner-spectrum, thin-film, chromatic-dispersion, fresnel,
//            depth-aware, temporal, upgraded-rgba, semantic-alpha, aces
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════
//  This shader already met the batch standard (ACES, exact-load feedback,
//  guarded 50-ripple loop, plasmaBuffer audio, dataTextureA writeback), so this
//  pass adds structure rather than compliance:
//
//    1. Per-band Gerstner spectrum — the surface was two fixed trochoidal wave
//       trains with hardcoded directions and wavenumbers. It is now an eight-
//       train spectrum, one per plasmaBuffer[1..8] bin, with directions fanned
//       across a spreading angle and deep-water dispersion (omega = sqrt(g·k))
//       so long swells genuinely travel slower than short chop. A real sea
//       surface is a spectrum; two waves can only ever beat against each other.
//
//    2. Spring-damped pointer drag — the drag vortex previously locked to the
//       raw cursor, so it teleported on every mouse jump. The smoothed pointer
//       and its velocity now live in extraBuffer[133..136] (written by
//       invocation (0,0) only), and the drag is applied along the pointer's
//       actual travel direction with its speed as the gain, so sweeping the
//       cursor shears the surface along the stroke.
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

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn spectralPalette(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 * (t + vec3<f32>(0.0, 0.333, 0.667)));
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Trochoidal Gerstner wave displacement
fn trochoidalWave(p: vec2<f32>, dir: vec2<f32>, k: f32, amp: f32, speed: f32, time: f32) -> vec3<f32> {
  let phase = dot(dir, p) * k - time * speed;
  let s = sin(phase);
  let c = cos(phase);
  // Returns (dx, dy, dz_height)
  return vec3<f32>(-dir.x * amp * s, -dir.y * amp * s, amp * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.18, 0.94, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.003, 0.042, u.zoom_params.z);
  let dispersion = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // ── Structure 1: eight-train Gerstner spectrum, one per FFT bin ─────────
  // Deep-water dispersion omega = sqrt(g*k): long swells run slow, short chop
  // runs fast. Directions fan across a spreading angle so the sea is confused
  // rather than a single marching front.
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  var dispSum = vec2<f32>(0.0);
  var crestSum = 0.0;
  for (var b: u32 = 0u; b < 8u; b = b + 1u) {
    let fb = f32(b);
    let energy = plasmaBuffer[b + 1u].x;
    let k = (8.0 + fb * 5.5) * (1.0 + turbulence * 1.2);
    let omega = sqrt(9.81 * k) * 0.12;                 // deep-water dispersion
    let spread = (fb - 3.5) * 0.34;                    // fan the wave normals
    let baseAng = 0.54 + spread + sin(time * 0.05 + fb) * 0.12;
    let dirW = vec2<f32>(cos(baseAng), sin(baseAng));
    // Longer waves carry more amplitude, as a real spectrum does.
    let amp = (0.0032 / (1.0 + fb * 0.55)) * depthFactor * (0.45 + energy * 1.9);
    let w = trochoidalWave(pAspect, dirW, k, amp, omega, time);
    dispSum += w.xy;
    crestSum += w.z;
  }

  var totalDisp = dispSum * mix(1.25, 0.55, viscosity);
  var waveCrest = crestSum * 150.0;

  // ── Structure 2: spring-damped pointer drag ────────────────────────────
  // extraBuffer[133..134] = smoothed position, [135..136] = smoothed velocity;
  // only invocation (0,0) writes, per the house pattern.
  let rawMouse = u.zoom_config.yz;
  if (gid.x == 0u && gid.y == 0u) {
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (sm.x == 0.0 && sm.y == 0.0) { sm = rawMouse; }
    let dt = 0.016;
    let kSpring = 1.0 - exp(-8.0 * dt);
    let next = sm + (rawMouse - sm) * kSpring;
    var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    sv = mix(sv, (next - sm) / dt, 0.28);
    extraBuffer[133] = next.x;
    extraBuffer[134] = next.y;
    extraBuffer[135] = sv.x;
    extraBuffer[136] = sv.y;
  }
  let mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  let pointerVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let isMouseDown = u.zoom_config.w;

  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * mix(8.0, 3.5, viscosity));
  let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  // Tangential swirl plus a shear along the pointer's actual travel.
  let strokeSpeed = clamp(length(pointerVel), 0.0, 4.0);
  let dragForce = dragTangent * dragCore * (0.008 + turbulence * 0.015) * (1.0 + isMouseDown * 2.2)
                + pointerVel * dragCore * strokeSpeed * 0.004 * (1.0 + isMouseDown);
  totalDisp += vec2<f32>(dragForce.x / aspect, dragForce.y);

  // 50-ripple shockwaves with dispersion
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 3.5) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let life = 1.0 - smoothstep(0.0, 3.5, age);
      let kWave = sin(rDist * (26.0 + turbulence * 22.0) - age * (4.0 + audio.x * 6.5));
      let envelope = exp(-rDist * mix(10.0, 4.0, viscosity)) * life;
      let rDisp = rDir * kWave * envelope * rippleStrength * (1.0 + audio.x * 0.75);

      totalDisp += vec2<f32>(rDisp.x / aspect, rDisp.y);
      waveCrest += pow(max(kWave, 0.0), 3.5) * envelope * 12.0;
    }
  }

  // 2.5D surface normal & Fresnel rim
  let normal = normalize(vec3<f32>(-totalDisp.x * 36.0, -totalDisp.y * 36.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.038);

  // Thin-film interference phase calculation
  let filmAngle = time * (0.12 + audio.y * 0.2) + dot(uv, vec2<f32>(3.0, 5.0));
  let filmThickness = waveCrest * 0.15 + length(totalDisp) * 12.0 + dispersion * 0.5;
  let phaseShift = filmThickness + filmAngle * 0.1;
  let iridescentColor = spectralPalette(fract(phaseShift));

  // Chromatic dispersion splitting for R, G, B channels
  let dispDir = totalDisp / max(length(totalDisp), 0.0001);
  let spectralSpread = dispDir * (0.0012 + dispersion * 0.02 + audio.z * 0.005);
  let baseUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  let uvR = clamp(baseUV + spectralSpread, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = baseUV;
  let uvB = clamp(baseUV - spectralSpread, vec2<f32>(0.0), vec2<f32>(1.0));

  let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(uvG * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  let spectralMask = clamp(waveCrest * 0.18 + fresnel * (0.6 + dispersion * 0.8), 0.0, 1.0);
  let sampledRGB = vec3<f32>(cR.r, cG.g, cB.b);
  var rgb = mix(sampledRGB, sampledRGB * (0.7 + iridescentColor * 0.9), spectralMask);
  rgb += iridescentColor * fresnel * (0.18 + audio.z * 0.35);

  let feedbackMix = clamp((0.08 + viscosity * 0.2) * history.a, 0.04, 0.32);
  rgb = mix(rgb, history.rgb, feedbackMix);
  rgb = acesToneMapping(rgb);

  let sourceAlpha = max(cR.a, max(cG.a, cB.a));
  let alpha = clamp(sourceAlpha * (0.84 + viscosity * 0.16) + spectralMask * 0.16 + fresnel * 0.1, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r;
  let outDepth = clamp(displacedDepth + waveCrest * 0.02 - length(totalDisp) * 0.15, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
