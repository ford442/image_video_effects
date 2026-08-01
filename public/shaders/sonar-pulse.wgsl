// ═══════════════════════════════════════════════════════════════════
//  Sonar Pulse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-echo, depth-attenuation, interference, click-pings, spring-origin, spectral-shimmer, upgraded-rgba
//  Complexity: High
//  Chunks From: sonar-pulse, bass_env, depth-aware-fog
//  Upgraded: 2026-05-31
//  Batch-20: click pings (ripples), spring-damped origin, FFT ring shimmer
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
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
  let mousePos = u.zoom_config.yz;  // raw cursor = spring target

  // ── Spring-damped sonar origin ─────────────────────────────────
  // Persistent state in extraBuffer[133..137] ([0..4] reserved,
  // [5..132] = engine FFT bins): 133/134 = sprung origin (uv space),
  // 135/136 = spring velocity, 137 = last update time.
  var sprungPos = mousePos;
  let hasState = arrayLength(&extraBuffer) > 137u;
  if (hasState) {
    sprungPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasState) {
    let prevTime = extraBuffer[137];
    let dt = clamp(time - prevTime, 0.001, 0.05);
    var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (prevTime <= 0.0) {
      // First touch: seed the spring at the cursor so it never snaps.
      sPos = mousePos;
      sVel = vec2<f32>(0.0, 0.0);
    }
    // Critically damped spring: stiffness = omega^2, damping = 2*omega.
    let omega = 8.0;
    let accel = (mousePos - sPos) * (omega * omega) - sVel * (2.0 * omega);
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
  }

  // Aspect correction applied to the SPRUNG position.
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(sprungPos.x * aspect, sprungPos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Multi-ring sonar with chromatic separation
  let phase = dist * waveFreq - time * waveSpeed;
  let wave = sin(phase);
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);
  let falloff = 1.0 / (1.0 + dist * 2.0);

  // Interference beats from secondary wave
  let phase2 = dist * waveFreq * 1.03 - time * waveSpeed * 0.97;
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

  // Per-ring spectral shimmer: ring phase proximity picks FFT bins 1-8,
  // tinting the pulse between the green sonar and violet beat colors.
  let sonarGreen = vec3<f32>(0.0, 1.0, 0.5);
  let beatViolet = vec3<f32>(0.5, 0.2, 0.8);
  let ringIdx = u32(floor(abs(phase) / 6.28318));
  let shimmerBin = plasmaBuffer[(ringIdx % 8u) + 1u].x;
  let shimmer = clamp(shimmerBin, 0.0, 1.0);
  let pulseColor = mix(sonarGreen, beatViolet, shimmer);

  var finalColor = vec3<f32>(rCol, gCol, bCol) + pulseColor * totalPulse;
  finalColor = finalColor + vec3<f32>(0.5, 0.2, 0.8) * beatMask * intensity;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAtten = mix(1.0, 0.5, depth);
  finalColor = finalColor * depthAtten;

  let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luminance + totalPulse * 0.3 + beatMask * 0.2, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
