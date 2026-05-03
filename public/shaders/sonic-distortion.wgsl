// ═══════════════════════════════════════════════════════════════════
//  Superellipse Sonic Chaos
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, superellipse, lissajous, fbm, temporal, echo-trails
//  Complexity: Very High
//  Upgraded by: Algorithmist Agent
//  Date: 2026-05-03
// ═══════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

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

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}

fn superellipseMask(d: vec2<f32>, a: f32, b: f32, n: f32) -> f32 {
  let xn = pow(abs(d.x) / max(a, 0.001), n);
  let yn = pow(abs(d.y) / max(b, 0.001), n);
  return 1.0 - smoothstep(0.8, 1.0, xn + yn);
}

fn lissajousOffset(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32> {
  return vec2<f32>(A * sin(a * t + delta), B * sin(b * t));
}

fn roseModulation(angle: f32, n: f32, a: f32) -> f32 {
  return a * abs(cos(n * angle * 0.5));
}

fn chaosWave(dist: f32, freq: f32, speed: f32, time: f32, harmonics: i32) -> f32 {
  var wave = 0.0;
  var amp = 1.0;
  for(var h: i32 = 0; h < harmonics; h = h + 1) {
    let fh = f32(h) + 1.0;
    wave = wave + amp * sin(dist * freq * fh - time * speed * fh * 0.7);
    amp = amp * 0.5;
  }
  return wave;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let freq = u.zoom_params.x * 100.0;
  let speed = u.zoom_params.y * 10.0;
  let amp = u.zoom_params.z * 0.05;
  let radius = max(u.zoom_params.w, 0.001);

  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let toPixel = uvAspect - mouseAspect;
  let pixelAngle = atan2(toPixel.y, toPixel.x);
  let pixelDist = length(toPixel);

  let seN = 2.0 + sin(time * 0.3) * 0.8;
  let seA = radius * aspect * (0.8 + sin(time * 0.5) * 0.2);
  let seB = radius * (0.8 + cos(time * 0.4) * 0.2);
  let mask = superellipseMask(toPixel, seA, seB, seN);

  let roseAmp = roseModulation(pixelAngle, 7.0, amp);

  var totalOffset = vec2<f32>(0.0);

  for(var src: i32 = 0; src < 4; src = src + 1) {
    let fSrc = f32(src);
    let liss = lissajousOffset(
      time * speed * 0.12 + fSrc * 2.1,
      radius * 0.35 * aspect,
      radius * 0.35,
      3.0 + fSrc,
      2.0 + fSrc * 0.5,
      fSrc * 1.047
    );
    let srcPos = mouseAspect + liss;
    let srcVec = uvAspect - srcPos;
    let srcDist = length(srcVec);
    let srcDir = select(vec2<f32>(0.0, 0.0), srcVec / srcDist, srcDist > 0.001);
    let srcWave = chaosWave(srcDist, freq, speed, time + fSrc * 1.7, 3);
    let srcMask = 1.0 - smoothstep(radius * 0.4, radius, srcDist);
    let warp = fbm(uv * 4.0 + time * 0.2 + fSrc * 10.0, 3) * 2.0 - 1.0;
    totalOffset = totalOffset + srcDir * srcWave * roseAmp * srcMask * (1.0 + warp * 0.5);
  }

  let primaryWave = chaosWave(pixelDist, freq, speed, time, 3);
  let primaryDir = select(vec2<f32>(0.0, 0.0), toPixel / pixelDist, pixelDist > 0.001);
  totalOffset = totalOffset + primaryDir * primaryWave * roseAmp * mask;

  let domainWarp = vec2<f32>(
    fbm(uv * 3.0 + vec2<f32>(time * 0.1, 0.0), 3),
    fbm(uv * 3.0 + vec2<f32>(0.0, time * 0.12), 3)
  );
  let warpedUV = uv + totalOffset + domainWarp * amp * 0.3;

  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let c1 = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let c2 = textureSampleLevel(readTexture, u_sampler, warpedUV + totalOffset * 0.12, 0.0);
  let c3 = textureSampleLevel(readTexture, u_sampler, warpedUV + totalOffset * 0.24, 0.0);

  let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let echoFade = 0.82;
  let echoColor = prevColor * echoFade;

  let aberrationWeight = mask * c0.a;
  var color = c0;
  color.r = mix(c0.r, c1.r, aberrationWeight);
  color.g = mix(c0.g, c2.g, aberrationWeight);
  color.b = mix(c0.b, c3.b, aberrationWeight);
  color.a = mix(c0.a, c1.a, mask * 0.5);

  let trailMix = 0.25 * mask + 0.1;
  let finalRGB = mix(color.rgb, echoColor.rgb, trailMix);
  let finalAlpha = max(color.a, echoColor.a * mask * 0.6);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
