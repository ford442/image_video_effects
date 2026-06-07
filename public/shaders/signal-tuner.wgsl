// ═══════════════════════════════════════════════════════════════════
//  Signal Tuner
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let gid = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let time = u.config.x;

  let freq = mix(5.0, 100.0, u.zoom_params.x);
  let amp = u.zoom_params.y * 0.1;
  let speed = u.zoom_params.z * 5.0;
  let noiseAmt = u.zoom_params.w;

  let prevState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let rawBass = plasmaBuffer[0].x;
  let env = bass_env(prevState.r, rawBass, 0.8, 0.15);
  let targetMouse = u.zoom_config.yz;
  let smoothMouse = mix(prevState.gb, targetMouse, 0.12);

  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

  let dist = distance(uv_corrected, mouse_corrected);
  let mouseInfluence = smoothstep(0.5, 0.0, dist);
  let clickBoost = select(1.0, 1.5, u.zoom_config.w > 0.5);

  let freqRadius = mix(0.3, 1.0, mouseInfluence);
  let pulse = beat_pulse(env, time);
  let audioAmp = amp * (1.0 + env * clickBoost + mids * 0.2);
  let wave = sin(uv.y * freq * freqRadius + time * speed + pulse * 3.14) * audioAmp;
  let displacement = vec2<f32>(wave * mouseInfluence, 0.0);

  let noiseHash = hash(uv * time);
  let noiseVal = select(0.0, (noiseHash - 0.5) * noiseAmt * mouseInfluence, noiseAmt > 0.01);
  let finalUV = clamp(uv + displacement + vec2<f32>(noiseVal, noiseVal), vec2<f32>(0.0), vec2<f32>(1.0));

  let split = audioAmp * mouseInfluence * 0.5 * (1.0 + treble * 0.3);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  let prevColor = textureLoad(dataTextureC, gid, 0);
  let isOrigin = select(0.0, 1.0, global_id.x == 0u && global_id.y == 0u);
  let prevColorSafe = mix(prevColor, vec4<f32>(0.0, 0.0, 0.0, 0.0), isOrigin);
  let trailStrength = 0.15 + mouseInfluence * 0.25 + pulse * 0.15;
  let color = mix(prevColorSafe.rgb, vec3<f32>(r, g, b), trailStrength);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let effectStrength = clamp(mouseInfluence * audioAmp * 10.0, 0.0, 1.0);
  let depthFactor = mix(1.0, 0.85, depth * 0.5);
  let alphaBase = clamp(luminance * 1.2 + 0.2, 0.4, 1.0) * depthFactor;
  let alpha = mix(alphaBase, prevColorSafe.a * (0.88 + mouseInfluence * 0.08), 0.25);
  let finalAlpha = clamp(alpha, 0.2, 1.0);
  let finalColor = vec4<f32>(color, finalAlpha);

  let statePixel = vec4<f32>(env, smoothMouse.x, smoothMouse.y, 0.0);
  let dataAVal = mix(finalColor, statePixel, isOrigin);

  textureStore(writeTexture, gid, finalColor);
  textureStore(dataTextureA, gid, dataAVal);
  textureStore(writeDepthTexture, gid, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
