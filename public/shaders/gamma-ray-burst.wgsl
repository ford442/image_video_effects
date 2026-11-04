// ═══════════════════════════════════════════════════════════════════
//  Gamma Ray Burst v2
//  Category: image
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: gamma-ray-burst, relativistic-jet
//  Upgraded: 2026-08-02 (Batch 30), 2026-11-01
//  Ideas: synchrotron cooling through the burst cycle; jet break past 6/jetSpread
//  A packing: diagnostic (burst, dopplerBeaming, magneticSpiral, alpha)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn synchrotron_spectrum(t: f32, freq: f32) -> vec3<f32> {
  let peak = 0.55 + t * 0.25;
  let dr = (freq - peak) * 3.5;
  let dg = (freq - peak + 0.12) * 4.0;
  let db = (freq - peak + 0.22) * 5.0;
  let r = exp(-dr * dr);
  let g = exp(-dg * dg);
  let b = exp(-db * db);
  return vec3<f32>(r, g * 0.85, b * 0.65);
}

fn film_grain(uv: vec2<f32>, t: f32) -> f32 {
  return hash12(uv * 512.0 + t * 73.0) * 0.06 - 0.03;
}

fn fft_voice(angle: f32) -> f32 {
  let sector = u32(fract(angle / 6.2831853 + 1.0) * 8.0) % 8u;
  return clamp(plasmaBuffer[sector + 1u].x, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) {
    mouse = rawMouse;
    mouseVelocity = vec2<f32>(0.0);
  }
  let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let springOmega = 9.0;
  mouseVelocity += ((rawMouse - mouse) * (springOmega * springOmega) - mouseVelocity * (2.0 * springOmega)) * springDt;
  mouse += mouseVelocity * springDt;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = mouse.x;
    extraBuffer[134] = mouse.y;
    extraBuffer[135] = mouseVelocity.x;
    extraBuffer[136] = mouseVelocity.y;
    extraBuffer[137] = 1.0;
    extraBuffer[138] = time;
  }
  let aspect = resolution.x / resolution.y;
  let intensity = u.zoom_params.x;
  let decay = max(u.zoom_params.y, 0.02);
  let jetSpread = mix(2.0, 24.0, u.zoom_params.z);
  let exposure = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let p = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = max(length(p), 0.0005);
  let angle = atan2(p.y, p.x);

  let burstPhase = floor(time * 1.5);
  let burstDecay = exp(-fract(time * 1.5) * 3.0);
  let burstTrigger = step(0.65, bass) * burstDecay;

  let beta2 = clamp(dist * dist * 0.8, 0.0, 0.98);
  let lorentz = inverseSqrt(max(1.0 - beta2, 0.02));
  let dopplerBeaming = min(pow(lorentz, 2.0), 12.0);
  let magneticSpiral = sin(angle * jetSpread + dist * 12.0 - time * 3.0 + burstPhase);
  let jetCore = exp(-dist * (4.0 + decay * 16.0)) * min(dopplerBeaming, 4.0);
  let jetWings0 = exp(-abs(magneticSpiral) * (1.5 + decay * 6.0) - dist * (1.2 + decay * 4.0)) * 0.6;
  // ── Idea 2: jet break. Tighter Jet Spread breaks closer in; the core falloff stays.
  let breakR = 6.0 / max(jetSpread, 0.001);
  let pastBreak = smoothstep(breakR, breakR + 0.2, dist);
  let jetWings = jetWings0 * (1.0 - pastBreak * 0.8);
  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let radius = length(delta);
      let shell = exp(-abs(radius - age * 0.22) * 70.0);
      let corePulse = smoothstep(0.09, 0.0, radius) * exp(-age * 4.0);
      clickBurst = max(clickBurst, (shell * 0.7 + corePulse) * exp(-age * 1.2));
    }
  }
  let spectralVoice = fft_voice(angle);
  let burst = min(intensity * (jetCore * 0.5 + jetWings * 0.5) * (0.4 + burstTrigger * 1.6 + clickBurst * 1.4), 5.0);

  let aberrationMag = burst * 0.025 * (1.0 + bass * 0.5) * (1.0 + dist * 0.5);
  let chromaDir = normalize(p + vec2<f32>(0.0001));
  let uvR = clamp(uv + chromaDir * aberrationMag * 1.2 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = clamp(uv + chromaDir * aberrationMag * 0.6 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(uv - chromaDir * aberrationMag * 0.9 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));

  let sampled = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  let freq = dist * 2.0 + mids * 0.3;
  let cycle = fract(time * 1.5);
  // ── Idea 1: synchrotron cooling. Blue dies as the existing burst cycle ages.
  let synchroRaw = synchrotron_spectrum(treble, freq);
  let synchro = synchroRaw * vec3<f32>(1.0, mix(1.0, 0.42, cycle), mix(1.0, 0.12, cycle)) * burst * (3.2 + spectralVoice * 1.6);
  let hdrFlare = vec3<f32>(1.0, 0.78 + mids * 0.18, 0.35 + treble * 0.25) * burst * (1.2 + exposure * 1.5);
  let core = smoothstep(0.06, 0.0, dist) * vec3<f32>(1.0, 0.95, 0.85) * (0.6 + burstTrigger);

  let extinction = depth * 0.35 * (1.0 - burst * 0.3);
  let scattered = sampled * (0.7 + exposure * 0.5) * (1.0 - extinction);
  var hdr = scattered + synchro + hdrFlare + core * (0.5 + bass * 0.35);
  hdr = hdr + film_grain(uv, time);

  let tonemapped = aces_tonemap(hdr);
  let jetIntensity = min(burst * dopplerBeaming, 12.0);
  let alpha = clamp((1.0 - extinction) * (0.12 + jetIntensity * 0.5 + burstTrigger * 0.2), 0.06, 0.92);
  let outDepth = clamp(depth + jetIntensity * 0.08, 0.0, 1.0);
  let finalPixel = vec4<f32>(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(min(burst, 5.0), dopplerBeaming, magneticSpiral, alpha));
}
