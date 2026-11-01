// ═══════════════════════════════════════════════════════════════════
//  Sonic Distortion
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, superellipse, lissajous, fbm, echo-trails, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-01
//  Ideas: harmonic beat; rose-petal nulls
//  A packing: pre-ACES linear display RGBA (C is the echo colour)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn chaosWave(dist: f32, freq: f32, speed: f32, time: f32, harmonics: i32) -> vec2<f32> {
  var wave = 0.0;
  var ampH = 1.0;
  var first = 0.0;
  var second = 0.0;
  for(var h: i32 = 0; h < harmonics; h = h + 1) {
    let fh = f32(h) + 1.0;
    let partial = sin(dist * freq * fh - time * speed * fh * 0.7);
    first = select(first, partial, h == 0);
    second = select(second, partial, h == 1);
    wave = wave + ampH * partial;
    ampH = ampH * 0.5;
  }
  // .x is the sum the offset already used; .y is the beat of the first two partials.
  return vec2<f32>(wave, abs(first * second));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let bass = plasmaBuffer[0].x;
  let freq = u.zoom_params.x * 100.0;
  let speed = u.zoom_params.y * 10.0;
  let amp = u.zoom_params.z * 0.05 * (1.0 + bass * 0.35);
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
    let srcWave = chaosWave(srcDist, freq, speed, time + fSrc * 1.7, 3).x;
    let srcMask = 1.0 - smoothstep(radius * 0.4, radius, srcDist);
    let warp = fbm(uv * 4.0 + time * 0.2 + fSrc * 10.0, 3) * 2.0 - 1.0;
    totalOffset = totalOffset + srcDir * srcWave * roseAmp * srcMask * (1.0 + warp * 0.5);
  }

  let primaryField = chaosWave(pixelDist, freq, speed, time, 3);
  let primaryWave = primaryField.x;
  let beat = primaryField.y;
  let primaryDir = select(vec2<f32>(0.0, 0.0), toPixel / pixelDist, pixelDist > 0.001);
  totalOffset = totalOffset + primaryDir * primaryWave * roseAmp * mask;

  let domainWarp = vec2<f32>(
    fbm(uv * 3.0 + vec2<f32>(time * 0.1, 0.0), 3),
    fbm(uv * 3.0 + vec2<f32>(0.0, time * 0.12), 3)
  );
  let warpedUV = clamp(uv + totalOffset + domainWarp * amp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));

  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let c1 = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let c2 = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + totalOffset * 0.12, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let c3 = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + totalOffset * 0.24, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let prevColor = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  let echoFade = 0.82;
  let echoColor = prevColor * echoFade;

  let aberrationWeight = mask * c0.a;
  var color = c0;
  color.r = mix(c0.r, c1.r, aberrationWeight);
  color.g = mix(c0.g, c2.g, aberrationWeight);
  color.b = mix(c0.b, c3.b, aberrationWeight);
  color.a = mix(c0.a, c1.a, mask * 0.5);

  let trailMix = 0.25 * mask + 0.1;
  let echoed = mix(color.rgb, echoColor.rgb, trailMix);
  // ── Idea 2: rose-petal nulls
  // roseAmp = amp * |cos(3.5·angle)|. The gaps of that rose darken the photo.
  let petal = abs(cos(3.5 * pixelAngle));
  // ── Idea 1: harmonic beat
  // |first × second| partial of the primary chaosWave, inside the mask only.
  let beatGlow = vec3<f32>(0.12, 0.32, 0.50) * beat * mask * (0.35 + u.zoom_params.z * 0.8);
  let linearRGB = max(echoed * mix(0.68, 1.0, petal) + beatGlow, vec3<f32>(0.0));
  let finalAlpha = clamp(max(color.a, echoColor.a * mask * 0.6) * (0.75 + beat * mask * 0.25), 0.0, 1.0);
  let linearOut = vec4<f32>(linearRGB, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap(linearRGB), finalAlpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), linearOut);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
