// ═══════════════════════════════════════════════════════════════════
//  Particle Physics Trace
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, audio-reactive,
//            spring-physics, phosphor-decay, electric-arc, multi-point-trail,
//            particle-spawn, velocity-smear, ripple-spark
//  Complexity: High
//  Upgraded by: Interactivist Agent
//  Date: 2026-05-03
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn springDamp(target: vec2<f32>, pos: vec2<f32>, vel: vec2<f32>, k: f32, d: f32, dt: f32) -> vec4<f32> {
  let force = (target - pos) * k;
  let newVel = (vel + force * dt) * (1.0 - d);
  let newPos = pos + newVel * dt;
  return vec4<f32>(newPos, newVel);
}

fn gauss(d2: f32, s2: f32) -> f32 {
  return exp(-d2 / (2.0 * s2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let traceIntensity = u.zoom_params.x;
  let traceWidth = u.zoom_params.y * 0.12 + 0.005;
  let springK = u.zoom_params.z * 5.0 + 0.2;
  let chaos = u.zoom_params.w;

  let audioBass = plasmaBuffer[0].x;
  let audioMids = plasmaBuffer[0].y;
  let audioReactivity = 1.0 + audioBass * 3.0 + audioMids;

  let bufOff = (global_id.x + global_id.y * u32(resolution.x)) * 8u;
  var lagPos = vec2<f32>(extraBuffer[bufOff], extraBuffer[bufOff + 1u]);
  var lagVel = vec2<f32>(extraBuffer[bufOff + 2u], extraBuffer[bufOff + 3u]);
  var arcPhase = extraBuffer[bufOff + 4u];

  let dt = 0.016;
  let spring = springDamp(mousePos, lagPos, lagVel, springK, 0.1, dt);
  lagPos = spring.xy;
  lagVel = spring.zw;
  let velMag = length(lagVel);
  arcPhase = arcPhase + (velMag * 8.0 + audioBass * 2.0) * dt;

  extraBuffer[bufOff] = lagPos.x;
  extraBuffer[bufOff + 1u] = lagPos.y;
  extraBuffer[bufOff + 2u] = lagVel.x;
  extraBuffer[bufOff + 3u] = lagVel.y;
  extraBuffer[bufOff + 4u] = arcPhase;

  let prevOut = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  let stretchDir = select(vec2<f32>(0.0), lagVel / velMag, velMag > 0.001);

  var glow = vec3<f32>(0.0);
  var accum = 0.0;
  let segments = 12;

  for (var i: i32 = 0; i <= segments; i = i + 1) {
    let t = f32(i) / f32(segments);

    let arcNoise = valueNoise2D(vec2<f32>(t * 13.0, arcPhase)) - 0.5;
    let arcNoise2 = valueNoise2D(vec2<f32>(t * 17.0 + 50.0, arcPhase * 1.3)) - 0.5;
    let jitter = vec2<f32>(arcNoise, arcNoise2) * chaos * 0.06 * t * (1.0 - t) * 4.0;

    let velStretch = stretchDir * velMag * t * (1.0 - t) * chaos * 0.6;
    let trailPoint = mix(mousePos, lagPos, t) + jitter + velStretch;

    let dVec = uv - trailPoint;
    let d2 = dot(dVec, dVec);
    let w = traceWidth * (0.35 + 0.65 * t);
    let falloff = gauss(d2, w * w);

    accum = accum + falloff;

    let hue = fract(time * 0.07 + t * 0.2 + audioBass * 0.25 + arcPhase * 0.015);
    let neon = 0.5 + 0.5 * cos(vec3<f32>(hue * 6.283, hue * 6.283 + 2.094, hue * 6.283 + 4.188));
    let brightness = 1.0 + audioMids * 0.5 * sin(t * 6.283 + time * 3.0);
    glow = glow + neon * falloff * brightness;
  }

  let rippleCount = u32(u.config.y);
  for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 1.5) {
      let rd = distance(uv, ripple.xy);
      let rw = traceWidth * (1.0 + elapsed * 2.0);
      let rFalloff = gauss(rd * rd, rw * rw) * (1.0 - elapsed * 0.66);
      let rHue = fract(ripple.z * 0.13 + elapsed * 0.4 + audioBass * 0.1);
      let rCol = 0.5 + 0.5 * cos(vec3<f32>(rHue * 6.283, rHue * 6.283 + 2.094, rHue * 6.283 + 4.188));
      glow = glow + rCol * rFalloff * traceIntensity * 0.6;
      accum = accum + rFalloff;
    }
  }

  let bassPulse = audioBass * mouseDown;
  var particleGlow = vec3<f32>(0.0);
  if (bassPulse > 0.02) {
    for (var i: i32 = 0; i < 7; i = i + 1) {
      let seed = vec2<f32>(f32(i), fract(time));
      let ang = hash12(seed) * 6.283;
      let rad = hash12(seed + vec2<f32>(1.0, 0.0)) * traceWidth * 4.5 * audioReactivity;
      let pPos = mousePos + vec2<f32>(cos(ang), sin(ang)) * rad;
      let pd = distance(uv, pPos);
      let pFalloff = exp(-pd * pd / (traceWidth * traceWidth * 0.18));
      let pHue = fract(f32(i) / 7.0 + time * 0.1 + audioBass);
      let pCol = 0.5 + 0.5 * cos(vec3<f32>(pHue * 6.283, pHue * 6.283 + 2.094, pHue * 6.283 + 4.188));
      particleGlow = particleGlow + pCol * pFalloff * bassPulse;
    }
  }

  let rDecay = 0.88 + 0.1 * sin(time * 1.3 + 0.0);
  let gDecay = 0.86 + 0.1 * sin(time * 1.9 + 2.0);
  let bDecay = 0.84 + 0.1 * sin(time * 2.7 + 4.0);

  let baseVideo = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let baseLuma = dot(baseVideo.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = 1.0 + baseLuma * 0.3;

  let outR = prevOut.r * rDecay + glow.r * traceIntensity * 0.2 * lumaBoost + particleGlow.r;
  let outG = prevOut.g * gDecay + glow.g * traceIntensity * 0.2 * lumaBoost + particleGlow.g;
  let outB = prevOut.b * bDecay + glow.b * traceIntensity * 0.2 * lumaBoost + particleGlow.b;

  let outRGB = vec3<f32>(outR, outG, outB);
  let alpha = clamp(max(max(outRGB.r, outRGB.g), outRGB.b), 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outRGB, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(outRGB, alpha));
}
