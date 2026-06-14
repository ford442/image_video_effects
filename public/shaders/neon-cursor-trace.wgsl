// ═══════════════════════════════════════════════════════════════════
//  Neon Cursor Trace
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, audio-reactive,
//            spring-physics, gravity-well, click-burst, phosphor-decay,
//            electric-arc, multi-point-trail, particle-spawn, velocity-smear,
//            ripple-spark, depth-aware, aces-tone-map
//  Complexity: High
//  Upgraded by: Interactivist Agent
//  Date: 2026-06-14
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn springDamp(targetPos: vec2<f32>, pos: vec2<f32>, vel: vec2<f32>, k: f32, damping: f32, dt: f32) -> vec4<f32> {
  let force = (targetPos - pos) * k;
  let newVel = (vel + force * dt) * (1.0 - damping);
  return vec4<f32>(pos + newVel * dt, newVel);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  return normalize(d) * strength / (dot(d, d) + 0.0001);
}

fn gauss(d2: f32, s2: f32) -> f32 { return exp(-d2 / (2.0 * s2)); }

fn neonColor(hue: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(hue * TAU, hue * TAU + 2.094, hue * TAU + 4.188));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let traceIntensity = u.zoom_params.x;
  let traceWidth = u.zoom_params.y * 0.12 + 0.005;
  let springK = u.zoom_params.z * 5.0 + 0.2;
  let chaos = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let prevOut = textureLoad(dataTextureC, pixel, 0);
  let bassEnv = mix(prevOut.a, bass, select(0.15, 0.8, bass > prevOut.a));

  let bufOff = (global_id.x + global_id.y * u32(res.x)) * 8u;
  var lagPos = vec2<f32>(extraBuffer[bufOff], extraBuffer[bufOff + 1u]);
  var lagVel = vec2<f32>(extraBuffer[bufOff + 2u], extraBuffer[bufOff + 3u]);
  var arcPhase = extraBuffer[bufOff + 4u];

  let dt = 0.016;
  let wellStrength = mouseDown * bassEnv * 0.0008;
  lagVel = lagVel + gravityWell(lagPos, mousePos, wellStrength);
  let spring = springDamp(mousePos, lagPos, lagVel, springK, 0.1, dt);
  lagPos = spring.xy;
  lagVel = spring.zw;
  let velMag = length(lagVel);
  arcPhase = arcPhase + (velMag * 8.0 + bassEnv * 2.0) * dt;

  extraBuffer[bufOff] = lagPos.x;
  extraBuffer[bufOff + 1u] = lagPos.y;
  extraBuffer[bufOff + 2u] = lagVel.x;
  extraBuffer[bufOff + 3u] = lagVel.y;
  extraBuffer[bufOff + 4u] = arcPhase;

  let stretchDir = select(vec2<f32>(0.0), lagVel / velMag, velMag > 0.001);

  var glow = vec3<f32>(0.0);
  var accum = 0.0;
  let segments = 12;

  for (var i: i32 = 0; i <= segments; i = i + 1) {
    let t = f32(i) / f32(segments);
    let n = valueNoise(vec2<f32>(t * 13.0, arcPhase)) - 0.5;
    let n2 = valueNoise(vec2<f32>(t * 17.0 + 50.0, arcPhase * 1.3)) - 0.5;
    let jitter = vec2<f32>(n, n2) * chaos * 0.24 * t * (1.0 - t);
    let well = gravityWell(mix(mousePos, lagPos, t), mousePos, wellStrength * 0.5);
    let velStretch = stretchDir * velMag * t * (1.0 - t) * chaos * 0.6;
    let trailPoint = mix(mousePos, lagPos, t) + jitter + velStretch + well;

    let dVec = uv - trailPoint;
    let d2 = dot(dVec, dVec);
    let w = traceWidth * (0.35 + 0.65 * t);
    let falloff = gauss(d2, w * w);

    accum = accum + falloff;
    let hue = fract(time * 0.07 + t * 0.2 + bassEnv * 0.25 + arcPhase * 0.015);
    let brightness = 1.0 + mids * 0.5 * sin(t * TAU + time * 3.0);
    glow = glow + neonColor(hue) * falloff * brightness;
  }

  let rippleCount = u32(u.config.y);
  for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 1.5) {
      let rd = distance(uv, ripple.xy);
      let rw = traceWidth * (1.0 + elapsed * 2.0);
      let rFalloff = gauss(rd * rd, rw * rw) * (1.0 - elapsed * 0.66);
      let rHue = fract(ripple.z * 0.13 + elapsed * 0.4 + bassEnv * 0.1);
      glow = glow + neonColor(rHue) * rFalloff * traceIntensity * 0.6;
      accum = accum + rFalloff;
    }
  }

  let clickPulse = mouseDown * bassEnv;
  var particleGlow = vec3<f32>(0.0);
  if (clickPulse > 0.02) {
    for (var i: i32 = 0; i < 7; i = i + 1) {
      let seed = vec2<f32>(f32(i), fract(time));
      let ang = hash21(seed) * TAU;
      let rad = hash21(seed + vec2<f32>(1.0, 0.0)) * traceWidth * 4.5 * (1.0 + bassEnv * 3.0);
      let pPos = mousePos + vec2<f32>(cos(ang), sin(ang)) * rad;
      let pd = distance(uv, pPos);
      let pFalloff = exp(-pd * pd / (traceWidth * traceWidth * 0.18));
      let pHue = fract(f32(i) / 7.0 + time * 0.1 + bassEnv);
      particleGlow = particleGlow + neonColor(pHue) * pFalloff * clickPulse;
    }
  }

  let rDecay = 0.88 + 0.1 * sin(time * 1.3);
  let gDecay = 0.86 + 0.1 * sin(time * 1.9 + 2.0);
  let bDecay = 0.84 + 0.1 * sin(time * 2.7 + 4.0);

  let baseVideo = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let baseLuma = dot(baseVideo.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = 1.0 + baseLuma * 0.3;

  var outRGB = vec3<f32>(
    prevOut.r * rDecay + glow.r * traceIntensity * 0.2 * lumaBoost + particleGlow.r,
    prevOut.g * gDecay + glow.g * traceIntensity * 0.2 * lumaBoost + particleGlow.g,
    prevOut.b * bDecay + glow.b * traceIntensity * 0.2 * lumaBoost + particleGlow.b
  );

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthMix = clamp(depth * 2.5, 0.0, 1.0);
  outRGB = mix(baseVideo.rgb * 0.15, outRGB, depthMix);

  let caStr = 0.003 * (1.0 + bassEnv) + depth * 0.001;
  let dir = normalize(uv - vec2<f32>(0.5) + vec2<f32>(0.0001));
  outRGB = vec3<f32>(
    outRGB.r + dir.x * caStr,
    outRGB.g,
    outRGB.b - dir.y * caStr * 0.5
  );

  outRGB = acesToneMap(outRGB * (0.9 + mids * 0.2));
  let alpha = clamp(luma(outRGB) * 1.5 * (0.5 + depthMix * 0.5), 0.15, 0.95);

  textureStore(writeTexture, pixel, vec4<f32>(outRGB, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(outRGB, bassEnv));
}
