// ================================================================
//  Neural Resonance
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: Medium
//  Chunks From: neural-resonance
//  Created: 2026-05-31
//  By: Copilot
//  Upgraded: 2026-07-30 (Batch 18, Algorithmist)
//    - FIX: mask-as-color feedback bug. dataTextureA now stores the
//      DISPLAY color (what dataTextureC reads back next frame), and
//      the mask quad moved to dataTextureB (same fix as spore-galaxy).
//    - Spring-dampered mouse mask via extraBuffer[133..136].
//    - Click resonance rings from u.ripples injected into feedback.
// ================================================================

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
  config: vec4<f32>,       // x=time, y=rippleCount, z=resW, w=resH
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=Amplification, y=CurlStrength, z=FeedbackMix, w=ChromaticDrift
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.01;
  let n1 = noise(p + vec2<f32>(0.0, e) + t);
  let n2 = noise(p - vec2<f32>(0.0, e) + t);
  let n3 = noise(p + vec2<f32>(e, 0.0) - t);
  let n4 = noise(p - vec2<f32>(e, 0.0) - t);
  return vec2<f32>(n1 - n2, -(n3 - n4)) / (2.0 * e);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  // Slider contract (zoom_params.x/y/z/w -> updatedParams index 0..3):
  //   x Amplification  -> curl noise frequency + audio-reactive gain
  //   y Curl Strength  -> warp displacement amplitude
  //   z Feedback Mix   -> temporal blend toward previous frame color
  //   w Chromatic Drift-> RGB split distance along the curl vector
  let amplification = mix(0.15, 1.35, u.zoom_params.x) * (1.0 + audio.x * 0.45);
  let curlStrength = mix(0.005, 0.08, u.zoom_params.y);
  let feedbackMix = mix(0.25, 0.96, u.zoom_params.z);
  let chromaticDrift = mix(0.0, 0.03, u.zoom_params.w);

  // --- Spring-dampered mouse center (extraBuffer[133..136] = pos, vel) ---
  // Critically damped spring so the warp emphasis glides behind the raw
  // cursor instead of snapping. Thread (0,0) integrates the state; every
  // thread reads the (near-identical) persistent value.
  var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let lastTime = extraBuffer[137];
  // Snap on first frames or after a big teleport (e.g. window refocus).
  if (time < 0.1 || lastTime <= 0.0 || length(springPos - mouse) > 1.5) {
    springPos = mouse;
    springVel = vec2<f32>(0.0, 0.0);
  }
  if (gid.x == 0u && gid.y == 0u) {
    let dt = clamp(time - lastTime, 0.0, 0.1);
    let omega = 9.0; // spring natural frequency (rad/s)
    let accel = omega * omega * (mouse - springPos) - 2.0 * omega * springVel;
    let newVel = springVel + accel * dt;
    let newPos = springPos + newVel * dt;
    extraBuffer[133] = newPos.x;
    extraBuffer[134] = newPos.y;
    extraBuffer[135] = newVel.x;
    extraBuffer[136] = newVel.y;
    extraBuffer[137] = time;
  }

  let aspectUV = uv * vec2<f32>(aspect, 1.0);
  let mouseDelta = (uv - springPos) * vec2<f32>(aspect, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, length(mouseDelta));
  let curl = curlField(aspectUV * (2.0 + amplification), time * 0.15) * curlStrength;
  let warpedUV = clamp(uv + curl / vec2<f32>(aspect, 1.0) * (0.4 + mouseMask * 1.2), vec2<f32>(0.0), vec2<f32>(1.0));

  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  // dataTextureC = previous frame's dataTextureA = previous DISPLAY color
  // (after the Batch 18 plumbing fix this is real color, not masks).
  let feedback = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0);
  let split = curl * chromaticDrift * (0.8 + audio.z * 0.6);
  let chroma = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    source.g,
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let synapseTint = mix(vec3<f32>(0.10, 0.75, 1.0), vec3<f32>(1.0, 0.35, 0.85), 0.5 + 0.5 * sin(time * 0.7 + noise(aspectUV * 4.0) * 6.28318));
  var finalColor = mix(chroma, feedback.rgb, feedbackMix * (0.4 + mouseMask * 0.6));
  finalColor = mix(finalColor, finalColor + synapseTint * (0.08 + audio.y * 0.18), 0.55);

  // --- Click resonance rings ---
  // Each live ripple injects a decaying, expanding synapseTint band
  // (radius = age * 0.5, ~1.5s fade) into the feedback, so clicks ring
  // outward through the resonance field and linger via the temporal loop.
  var ringEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age > 0.0 && age < 1.5) {
      let ringRadius = age * 0.5;
      let ringDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let band = 1.0 - smoothstep(0.0, 0.04 + age * 0.05, abs(ringDist - ringRadius));
      ringEnergy = ringEnergy + band * (1.0 - age / 1.5);
    }
  }
  ringEnergy = min(ringEnergy, 1.5);
  finalColor = finalColor + synapseTint * ringEnergy * (0.35 + audio.y * 0.25);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let finalAlpha = clamp(mix(source.a, feedback.a, feedbackMix) + mouseMask * 0.12 + ringEnergy * 0.05, 0.02, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.24 + mouseMask * 0.58, 0.22) - ringEnergy * 0.03, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  // dataTextureA = DISPLAY color (raw, never tonemapped) -> read back as
  // dataTextureC next frame by the feedback path.
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  // dataTextureB = mask quad (same 4 values, same order as before).
  textureStore(dataTextureB, vec2<i32>(gid.xy), vec4<f32>(mouseMask, feedbackMix, length(curl) * 10.0, finalAlpha));
}
