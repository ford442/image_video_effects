// ═══════════════════════════════════════════════════════════════════
//  Sonar Pulse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-echo, depth-attenuation, interference, click-pings, upgraded-rgba
//  Complexity: High
//  Chunks From: sonar-pulse, bass_env, depth-aware-fog
//  Upgraded: 2026-05-31, 2026-10-27
//  Ideas: deep-water dispersion (§12.2D); cylindrical spreading
//  A packing: ACES display RGBA (C not read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001, 0.001));
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let waveSpeed = mix(1.0, 10.0, u.zoom_params.x) * bass_env(bass, mids);
  let waveFreq = mix(10.0, 100.0, u.zoom_params.y) + mids * 10.0;
  let intensity = clamp(u.zoom_params.z + treble * 0.1, 0.0, 1.0);
  let waveWidth = max(mix(0.1, 0.5, u.zoom_params.w), 0.001);

  let aspect = resolution.x / max(resolution.y, 0.001);
  let mousePos = u.zoom_config.yz;

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // ── Idea: deep-water dispersion (§12.2D) — long waves (low Frequency) outrun short ones.
  // Phase speed ∝ sqrt(tanh(k) / k). Wave Speed still scales every ring.
  let kNorm = clamp(waveFreq / 100.0, 0.05, 1.0);
  let phaseSpeed = waveSpeed * sqrt(tanh(kNorm * 3.0) / kNorm);
  let phase = dist * waveFreq - time * phaseSpeed;
  let wave = sin(phase);
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);
  // ── Idea: cylindrical spreading — 1/sqrt(r), finite at the origin.
  let falloff = inverseSqrt(1.0 + dist * dist * 6.0);

  // Interference beats from secondary wave. The overtone is shorter, so it lags.
  let k2 = clamp(kNorm * 1.03, 0.05, 1.0);
  let phaseSpeed2 = waveSpeed * 0.97 * sqrt(tanh(k2 * 3.0) / k2);
  let phase2 = dist * waveFreq * 1.03 - time * phaseSpeed2;
  let beat = sin(phase) * sin(phase2);
  let beatMask = smoothstep(0.5, 1.0, abs(beat)) * 0.3;

  let audioBoost = bass_env(bass, mids);
  let pulseStrength = pulse * intensity * falloff * audioBoost;

  // ── Click pings: every live ripple is a sonar emitter ──────────
  // Expanding ring at radius age * 0.6 with the shader's own pulse
  // smoothstep profile (reuses waveWidth), intensity exp(-age * 2.0),
  // ~2s life. Pings add to the pulse, the distortion, and the
  // chromatic echo, so every click fires a visible sweep.
  var pingStrength = 0.0;
  var pingOffset = vec2<f32>(0.0, 0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rpCenter = vec2<f32>(rp.x * aspect, rp.y);
    let rpDist = distance(uv_corrected, rpCenter);
    let ringRadius = age * 0.6;
    // Same smoothstep pulse profile as the main emitter (waveWidth).
    let ringWave = 1.0 - abs(rpDist - ringRadius) / max(waveWidth * 0.5, 0.001);
    let ringPulse = smoothstep(1.0 - waveWidth, 1.0, ringWave);
    let pingEnv = exp(-age * 2.0);
    let ping = ringPulse * pingEnv * intensity;
    pingStrength = pingStrength + ping;
    pingOffset = pingOffset + ((uv_corrected - rpCenter) / max(rpDist, 0.001)) * ping;
  }
  let totalPulse = pulseStrength + pingStrength;

  let safeDist = max(dist, 0.001);
  let offsetDir = (uv_corrected - mouse_corrected) / safeDist;
  let distortAmt = 0.02 * pulse * intensity;
  let distortedUV = clamp(uv - (offsetDir * distortAmt + pingOffset * 0.02), vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic echo: R/G/B sample at different distances
  let chromaOffset = totalPulse * 0.015;
  let rUV = clamp(distortedUV + offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = distortedUV;
  let bUV = clamp(distortedUV - offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  // Treble phase of the ring (plasmaBuffer[1..] is never uploaded).
  let sonarGreen = vec3<f32>(0.0, 1.0, 0.5);
  let beatViolet = vec3<f32>(0.5, 0.2, 0.8);
  let shimmer = 0.5 + 0.5 * sin(phase * 0.17 + treble * 6.0);
  let pulseColor = mix(sonarGreen, beatViolet, shimmer * (0.2 + treble * 0.8));

  var finalColor = vec3<f32>(rCol, gCol, bCol) + pulseColor * totalPulse;
  finalColor = finalColor + vec3<f32>(0.5, 0.2, 0.8) * beatMask * intensity;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAtten = mix(1.0, 0.5, depth);
  finalColor = finalColor * depthAtten;

  let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luminance * 0.35 + totalPulse * 0.45 + beatMask * 0.2, 0.0, 1.0);
  finalColor = aces(max(finalColor, vec3<f32>(0.0)));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
