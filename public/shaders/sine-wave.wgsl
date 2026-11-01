// ═══════════════════════════════════════════════════════════════════
//  Sine Wave
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-01
//  Ideas: standing-wave nodes around the pointer; Stokes second-order drift; deep-water dispersion (§12.2D); group shade
//  A packing: telemetry (offset.xy, crest, alpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let intensity = u.zoom_params.x * 0.06 * (1.0 + bass * 0.6);
  let speed = 0.15 + u.zoom_params.y * 3.5;
  let scale = 1.5 + u.zoom_params.z * 18.0;
  let detail = u.zoom_params.w;

  // Mouse creates wave sources
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.75, mouseDist);

  // Multi-frequency interference with fast, closed-form packet envelopes.
  let phase = uv.y * scale * 6.28318 + time * speed * 2.5;
  // ── Idea 1: deep-water dispersion (§12.2D)
  // The cross-wave's wavenumber is 0.7× the primary. Deep water: phase
  // speed ∝ 1/sqrt(k), so the longer cross-wave outruns the primary.
  // The speed slider still sets the primary rate (phase is unchanged).
  let crossK = 0.7;
  let cRatio = sqrt(1.0 / crossK);
  let phase2 = uv.x * (scale * crossK) * 6.28318 - time * speed * 1.7 * cRatio;
  let packetPhaseX = fract(uv.y * (1.5 + scale * 0.12) - time * speed * 0.42);
  let packetPhaseY = fract(uv.x * (1.2 + scale * 0.09) + time * speed * 0.31);
  let packX = (packetPhaseX - 0.5) / 0.16;
  let packY = (packetPhaseY - 0.5) / 0.18;
  let packetX = exp(-packX * packX);
  let packetY = exp(-packY * packY);
  let groupVel = sin(phase * 0.5 + time * speed * 0.8) * 0.5 + 0.5;

  var clickWave = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let front = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.30 + speed * 0.04));
      clickWave += (1.0 - smoothstep(0.0, 0.025, front)) * (1.0 - age / 2.4);
    }
  }

  // Standing-wave nodes: concentric zeros around the pointer (this is a wave).
  let node = 0.28 + 0.72 * abs(sin(mouseDist * scale * 2.4 + time * speed * 0.15));

  let waveX = sin(phase + clickWave * 2.2) * groupVel * (0.55 + packetX * 0.9) * node;
  let waveY = cos(phase2 - clickWave * 1.7) * (1.0 - groupVel * 0.3) * (0.60 + packetY * 0.75) * node;

  // Amplitude modulation from audio + mouse
  let am = 1.0 + bass * 0.5 + mouseMask * 0.8;
  let micro = sin((uv.x + uv.y) * scale * 12.0 + time * (2.0 + audio.z * 2.0)) * detail * 0.008;

  // Depth controls wave attenuation
  let depthAtten = mix(1.0, 0.2, depth);

  // Stokes drift: second-order mass transport along the first-harmonic crest.
  let stokesAmp = (waveX * waveX + waveY * waveY) * intensity * 0.22;
  let stokes = vec2<f32>(waveX, waveY) * stokesAmp;

  let offset = vec2<f32>(
    (waveX + waveY * 0.45) * intensity * am + micro,
    (waveY - waveX * 0.35) * intensity * 0.45 * (1.0 + mouseMask)
  ) * depthAtten + stokes * depthAtten;

  let coord = vec2<i32>(gid.xy);
  let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
  let stateOffset = vec2<i32>(round(vec2<f32>(waveX, waveY) * (2.0 + detail * 5.0)));
  let previousState = textureLoad(dataTextureC, clamp(coord - stateOffset, vec2<i32>(0), maxCoord), 0);
  let historyOffset = clamp(previousState.xy, vec2<f32>(-0.12), vec2<f32>(0.12));
  let sampleUV = clamp(uv + offset + historyOffset * (0.08 + detail * 0.12), vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic dispersion on wave crests
  let crest = clamp(abs(waveX) * 0.6 + abs(waveY) * 0.4, 0.0, 1.0);
  let dispersion = detail * 0.01 * (0.5 + audio.z) * (1.0 + crest * 2.0);
  let split = vec2<f32>(dispersion, 0.0);

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // Water surface caustics from wave interference
  let interference = abs(waveX * waveY) * 2.0;
  let causticTint = mix(vec3<f32>(0.0, 0.55, 0.95), vec3<f32>(0.75, 0.25, 1.0), detail * 0.6 + audio.y * 0.2);
  finalColor = finalColor + causticTint * interference * (0.04 + bass * 0.12);

  // HDR specular highlights on crests
  let crestStreak = clamp(previousState.z, 0.0, 1.0) * (packetX + packetY) * 0.5;
  let specular = pow(crest, 8.0) * (0.3 + bass * 0.4) + crestStreak * (0.12 + detail * 0.22);
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * specular;

  // ── Idea 2: group shade
  // packetX/packetY are the traveling envelopes. Between packets the photo
  // sits in the group trough — a darkening, not a new wave.
  let groupShade = clamp(packetX * 0.65 + packetY * 0.35, 0.0, 1.0);
  finalColor = finalColor * (0.84 + 0.16 * groupShade);

  // ACES tone mapping
  finalColor = acesToneMap(max(finalColor, vec3<f32>(0.0)) * 1.15);

  // Semantic alpha: wave_amplitude * interference_intensity * depth
  let interferenceIntensity = interference + crest * 0.5;
  let finalAlpha = clamp(intensity * 12.0 * interferenceIntensity * depth * 2.5, 0.15, 0.95);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + crest * 0.60, 0.18 + intensity * 8.0), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(offset.x, offset.y, crest, finalAlpha));
}
