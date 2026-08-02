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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Frequency, y=Interference, z=DriftSpeed, w=Static
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn beat_pulse(env: f32, time: f32) -> f32 {
  return env * exp(-3.0 * fract(time * 2.0));
}

@compute @workgroup_size(16, 16, 1)
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

  let targetMouse = u.zoom_config.yz;

  // True critically damped pointer follow plus an attack/release bass envelope.
  // State lives only in shader-safe slots: pos [133..134], velocity [135..136],
  // time [137], initialized [138], envelope [139].
  let hasState = arrayLength(&extraBuffer) > 139u;
  var smoothMouse = targetMouse;
  var env = bass;
  if (hasState && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    env = extraBuffer[139];
  }
  if (global_id.x == 0u && global_id.y == 0u && hasState) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    var nextEnv = env;
    if (extraBuffer[138] <= 0.5) {
      springPos = targetMouse;
      springVel = vec2<f32>(0.0);
      nextEnv = bass;
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 8.0;
      let accel = (targetMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
      let envelopeRate = select(4.0, 18.0, bass > nextEnv);
      nextEnv = mix(nextEnv, bass, 1.0 - exp(-envelopeRate * dt));
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    extraBuffer[139] = nextEnv;
  }

  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

  let dist = distance(uv_corrected, mouse_corrected);
  let mouseInfluence = smoothstep(0.5, 0.0, dist);
  let clickBoost = select(1.0, 1.5, u.zoom_config.w > 0.5);

  // Clicks retune localized expanding bands instead of acting as another held
  // mouse state. Ripple positions are normalized canvas coordinates.
  var rippleTune = 0.0;
  var rippleRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.6, age));
    let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let ring = 1.0 - smoothstep(0.015, 0.05, abs(rd - safeAge * 0.38));
    let wave = ring * exp(-safeAge * 1.7) * live;
    rippleTune += wave * sin(rp.x * 31.0 + rp.y * 17.0);
    rippleRing = max(rippleRing, wave);
  }

  let freqRadius = mix(0.3, 1.0, mouseInfluence);
  let pulse = beat_pulse(env, time);
  let audioAmp = amp * (1.0 + env * clickBoost + mids * 0.2);
  let wave = sin(uv.y * freq * freqRadius + time * speed + pulse * 3.14 + rippleTune * 2.0) * audioAmp;
  let displacement = vec2<f32>(wave * max(mouseInfluence, rippleRing), 0.0);

  let regionBin = (u32(floor(uv.y * 64.0)) % 8u) + 1u;
  let fftRegion = plasmaBuffer[regionBin].x;
  let noiseHash = hash(uv * max(time, 0.001));
  let noiseVal = select(0.0, (noiseHash - 0.5) * noiseAmt * max(mouseInfluence, rippleRing) * (1.0 + fftRegion * 0.4), noiseAmt > 0.01);
  let finalUV = clamp(uv + displacement + vec2<f32>(noiseVal, noiseVal), vec2<f32>(0.0), vec2<f32>(1.0));

  let split = audioAmp * max(mouseInfluence, rippleRing) * 0.5 * (1.0 + treble * 0.25 + fftRegion * 0.20);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  let prevColor = textureLoad(dataTextureC, gid, 0);
  let trailStrength = 0.15 + max(mouseInfluence, rippleRing) * 0.25 + pulse * 0.15;
  let color = mix(prevColor.rgb, vec3<f32>(r, g, b), trailStrength);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let effectStrength = clamp(mouseInfluence * audioAmp * 10.0, 0.0, 1.0);
  let depthFactor = mix(1.0, 0.85, depth * 0.5);
  let alphaBase = clamp(luminance * 1.2 + 0.2, 0.4, 1.0) * depthFactor;
  let alpha = mix(alphaBase, prevColor.a * (0.88 + mouseInfluence * 0.08), 0.25);
  let finalAlpha = clamp(alpha, 0.2, 1.0);
  let finalColor = vec4<f32>(color, finalAlpha);

  let depthOut = clamp(depth - effectStrength * 0.025 - rippleRing * 0.02, 0.0, 1.0);

  textureStore(writeTexture, gid, finalColor);
  textureStore(dataTextureA, gid, finalColor);
  textureStore(writeDepthTexture, gid, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
