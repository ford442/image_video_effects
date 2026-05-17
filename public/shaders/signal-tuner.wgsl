// ═══════════════════════════════════════════════════════════════════
//  Signal Tuner
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Pixelocity Shader Upgrade Swarm — Phase A
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn beat_pulse(env: f32, time: f32) -> f32 {
  return env * exp(-3.0 * fract(time * 2.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);
  let gid = vec2<i32>(i32(global_id.x), i32(global_id.y));

  // Parameters
  let freq = mix(5.0, 100.0, u.zoom_params.x);
  let amp = u.zoom_params.y * 0.1;
  let speed = u.zoom_params.z * 5.0;
  let noiseAmt = u.zoom_params.w;
  let time = u.config.x;

  // ---- Attack/Release Audio Envelope ----
  // Persist smoothed bass in dataTextureA/C at pixel (0,0)
  let prevState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let rawBass = plasmaBuffer[0].x;
  let env = bass_env(prevState.r, rawBass, 0.8, 0.15);

  // ---- Spring-Damper Mouse Follow ----
  // Smooth mouse position stored in dataTextureA/C
  let targetMouse = u.zoom_config.yz;
  let smoothMouse = mix(prevState.gb, targetMouse, 0.12);

  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(env, smoothMouse.x, smoothMouse.y, 0.0));
  }

  // ---- Mouse Influence (≥2 parameters) ----
  let aspect = u.config.z / u.config.w;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

  let dist = distance(uv_corrected, mouse_corrected);
  let mouseInfluence = smoothstep(0.5, 0.0, dist);
  let clickBoost = select(1.0, 1.5, u.zoom_config.w > 0.5);

  // Mouse modulates local frequency radius
  let freqRadius = mix(0.3, 1.0, mouseInfluence);

  // ---- Audio-Reactive Wave (smoothed envelope) ----
  let pulse = beat_pulse(env, time);
  let audioAmp = amp * (1.0 + env * clickBoost);
  let wave = sin(uv.y * freq * freqRadius + time * speed + pulse * 3.14) * audioAmp;
  let displacement = vec2<f32>(wave * mouseInfluence, 0.0);

  // ---- Noise ----
  let noiseHash = hash(uv * time);
  let noiseVal = select(0.0, (noiseHash - 0.5) * noiseAmt * mouseInfluence, noiseAmt > 0.01);
  let finalUV = uv + displacement + vec2<f32>(noiseVal, noiseVal);

  // ---- RGB Split (Chromatic Aberration) ----
  let split = audioAmp * mouseInfluence * 0.5;
  let r = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(split, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(split, 0.0), 0.0).b;

  // ---- Temporal Feedback Trails ----
  var prevColor = textureLoad(dataTextureC, gid, 0);
  if (global_id.x == 0u && global_id.y == 0u) {
    prevColor = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  }
  let trailStrength = 0.15 + mouseInfluence * 0.25 + pulse * 0.15;
  var color = mix(prevColor.rgb, vec3<f32>(r, g, b), trailStrength);

  // ---- Depth & Alpha (encodes trail age / intensity) ----
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let effectStrength = clamp(mouseInfluence * audioAmp * 10.0, 0.0, 1.0);
  let depthFactor = mix(1.0, 0.85, depth * 0.5);

  var alpha = mix(1.0, clamp(luminance * 1.2 + 0.2, 0.4, 1.0) * depthFactor, effectStrength);
  let trailDecay = 0.88 + mouseInfluence * 0.08;
  alpha = mix(alpha, prevColor.a * trailDecay, 0.25);
  alpha = clamp(alpha, 0.2, 1.0);

  textureStore(writeTexture, gid, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, gid, vec4<f32>(depth, 0.0, 0.0, 0.0));

  // Persist color to dataTextureA for next-frame trails
  if (global_id.x != 0u || global_id.y != 0u) {
    textureStore(dataTextureA, gid, vec4<f32>(color, alpha));
  }
}
