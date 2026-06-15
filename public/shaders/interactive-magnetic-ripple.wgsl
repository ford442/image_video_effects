// ═══════════════════════════════════════════════════════════════════
//  Interactive Magnetic Ripple — Interactivist Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, temporal-feedback,
//            motion-trails, chromatic-aberration, aces-tone-map
//  Upgraded: 2026-06-14
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
             u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let n0 = fbm(p + vec2<f32>(0.0,  e) + t * 0.12, 3);
  let n1 = fbm(p + vec2<f32>(0.0, -e) + t * 0.12, 3);
  let n2 = fbm(p + vec2<f32>( e, 0.0) + t * 0.12, 3);
  let n3 = fbm(p + vec2<f32>(-e, 0.0) + t * 0.12, 3);
  return vec2<f32>(n0 - n1, n3 - n2) / (2.0 * e);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let freq = u.zoom_params.x * 40.0;
  let decay = u.zoom_params.y * 3.0 + 0.5;
  let fieldStrength = u.zoom_params.z;
  let chromaticSplit = u.zoom_params.w * 0.08;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  // Attack/release bass envelope + spring-smoothed mouse
  let env = mix(prev.r, bass, select(0.15, 0.85, bass > prev.r));
  let k = 0.12 + env * 0.08;
  let mSmooth = mix(prev.gb, mouse, vec2<f32>(k));
  let mVel = mSmooth - prev.gb;

  let pulseStrength = fieldStrength * (1.0 + env * 0.7);
  let clickBurst = select(0.0, 1.0, mouseDown) * (1.0 + env);

  var totalDisp = vec2<f32>(0.0);
  var rippleIntensity = 0.0;

  // Mouse-driven magnetic field
  if (mouse.x >= 0.0) {
    let dMouse = mSmooth - uv01;
    let dAspect = vec2<f32>(dMouse.x * aspect, dMouse.y);
    let dist = length(dAspect);
    let dir = select(vec2<f32>(0.0), dMouse / dist, dist > 0.001);

    let curl = curlNoise(uv01 * 3.0 + time * 0.3, time) * 0.25;

    let phase = dist * freq - time * 4.0;
    let fbmWarp = fbm(vec2<f32>(dist * 4.0, time * 0.4), 3) * 2.5;
    let ripple = cos(phase + fbmWarp) * 0.55 + sin(phase * 1.618) * 0.45;
    let rippleAtten = exp(-dist * decay);
    totalDisp += dir * ripple * rippleAtten * 0.06;
    rippleIntensity += abs(ripple) * rippleAtten;

    let velBoost = 1.0 + length(mVel) * 5.0;
    let magFalloff = fbm(vec2<f32>(dist * 6.0, time * 0.2), 3) * 0.3 + 0.7;
    let magPull = dir * pulseStrength * velBoost * magFalloff / (dist * dist + 0.04) * 0.06;
    totalDisp += magPull + curl * 0.04;
    rippleIntensity += length(magPull) * 10.0;

    let fieldLine = sin(atan2(dAspect.y, dAspect.x) * 12.0 + fbm(uv01 * 5.0, 3) * 3.0);
    let fieldLineMask = smoothstep(0.3, 0.0, abs(fieldLine)) * exp(-dist * 3.0);
    totalDisp += dir * fieldLineMask * pulseStrength * 0.02;
    rippleIntensity += fieldLineMask * pulseStrength;
  }

  // Click burst shockwave
  totalDisp += normalize(uv01 - mSmooth + vec2<f32>(0.0001)) * clickBurst * 0.03 * sin(length(uv01 - mSmooth) * 40.0 - time * 10.0);

  // Process stored ripple points
  for (var i: u32 = 0u; i < 50u; i = i + 1u) {
    let rp = u.ripples[i];
    if (rp.z <= 0.0) { continue; }
    let rPos = rp.xy;
    let rAge = time - rp.z;
    let rDiff = vec2<f32>((rPos.x - uv01.x) * aspect, rPos.y - uv01.y);
    let rDist = length(rDiff);
    let rDir = select(vec2<f32>(0.0), vec2<f32>(rDiff.x / aspect, rDiff.y) / rDist, rDist > 0.001);
    let rRipple = cos(rDist * freq * 0.6 - rAge * 5.0) * exp(-rDist * decay - rAge * 1.2);
    totalDisp += rDir * rRipple * 0.035;
    rippleIntensity += abs(rRipple) * 0.5;
  }

  // Domain warp + depth-aware displacement scaling
  let warp = fbm(uv01 * 4.0 + time * 0.2, 3) * 0.015;
  totalDisp = totalDisp * (1.0 + warp);
  totalDisp *= 0.6 + depth * 0.8;

  // Chromatic aberration
  let abNoise = fbm(uv01 * 6.0 + vec2<f32>(time * 0.1, 0.0), 3) * 0.015;
  let abScale = 1.0 + chromaticSplit + abNoise;
  let rUV = clamp(uv01 - totalDisp * abScale, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv01 - totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv01 - totalDisp * (2.0 - abScale), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Audio-reactive glow at ripple peaks
  let glow = smoothstep(0.2, 0.8, rippleIntensity) * (1.0 + env * 0.5);
  color += vec3<f32>(0.3 + mids * 0.3, 0.5 + treble * 0.3, 0.8) * glow * 0.4;

  // Temporal feedback trail
  let trailDecay = 0.94 + env * 0.04;
  color = mix(prev.rgb * trailDecay, color, 0.18 + rippleIntensity * 0.15);

  // Tone map + depth-aware compositing
  color = acesToneMap(color * (0.95 + mids * 0.15));
  let fog = 1.0 - exp(-depth * fieldStrength * 2.0);
  let bgLuma = luma(color) * (1.0 - fog * 0.3);
  color = mix(color, vec3<f32>(bgLuma), fog * 0.25);

  // Semantic alpha: intensity × depth
  let alpha = clamp(luma(color) * 1.4 + rippleIntensity * 0.35, 0.15, 0.95) * (0.6 + depth * 0.4);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(env, mSmooth.x, mSmooth.y, rippleIntensity));
}
