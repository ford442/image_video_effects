// ═══════════════════════════════════════════════════════════════════
//  Turing Morphogenesis
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15, 2026-09-27, 2026-11-20
//  Ideas: inhibitor halo around spots; chemical-front ridges where activator ≈ scaled inhibitor; stripe coat-grain along the activator gradient; slow domain patches; chemical boundary from the activator gradient; stain aging along the organic ramp
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Feed Rate, y=Evolution Speed, z=Pattern Scale, w=Color Shift

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0;
  return mix(mix(hashf(n), hashf(n + 1.0), u.x), mix(hashf(n + 57.0), hashf(n + 58.0), u.x), u.y);
}

fn activatorInhibitor(uv: vec2<f32>, scale: f32, time: f32) -> vec2<f32> {
  let a = vnoise(uv * scale * 2.5 + vec2<f32>(time * 0.04, time * 0.03));
  let i = vnoise(uv * scale * 1.0 - vec2<f32>(time * 0.02, time * 0.025));
  let a2 = vnoise(uv * scale * 4.0 + vec2<f32>(3.7, 1.9) + time * 0.06);
  let i2 = vnoise(uv * scale * 1.5 + vec2<f32>(7.3, 4.1) - time * 0.015);
  return vec2<f32>(a * 0.6 + a2 * 0.4, i * 0.6 + i2 * 0.4);
}

fn organicColor(t: f32, p4: f32) -> vec3<f32> {
  let s = fract(t + p4);
  let colors = array<vec3<f32>, 5>(
    vec3<f32>(0.96, 0.94, 0.86), vec3<f32>(0.80, 0.52, 0.25),
    vec3<f32>(0.55, 0.27, 0.07), vec3<f32>(0.45, 0.60, 0.35),
    vec3<f32>(0.72, 0.45, 0.20)
  );
  let idx = s * 4.0;
  let i = i32(clamp(idx, 0.0, 3.0));
  return mix(colors[i], colors[i + 1], fract(idx));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }
  let uv = vec2<f32>(pixel) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let depthScale = mix(0.5, 1.5, depth);
  let scale = (3.0 + p3 * 10.0) * depthScale;
  let speed = p2 * 0.5;

  let feed = 0.03 + p1 * 0.05 + sin(time * speed * 0.1) * 0.008 + bass * 0.02;
  let kill = 0.055 + p1 * 0.03 + cos(time * speed * 0.12) * 0.005 - bass * 0.01;
  let fk = kill - feed;
  // Idea 4 — slow domain patches. A large inhibitor scale shifts the existing regime locally.
  let domain = vnoise(uv * scale * 0.35 - vec2<f32>(time * 0.01, time * 0.008));
  let fkLocal = fk + (domain - 0.5) * 0.014;
  // Idea 3 — coat grain. Stripe direction follows the activator gradient.
  let aXp = activatorInhibitor(uv + vec2<f32>(0.02, 0.0), scale, time).x;
  let aXm = activatorInhibitor(uv - vec2<f32>(0.02, 0.0), scale, time).x;
  let aYp = activatorInhibitor(uv + vec2<f32>(0.0, 0.02), scale, time).x;
  let aYm = activatorInhibitor(uv - vec2<f32>(0.0, 0.02), scale, time).x;
  let gA = vec2<f32>(aXp - aXm, aYp - aYm);
  let tangent = vec2<f32>(-gA.y, gA.x);
  let along = dot(uv * scale, tangent / max(length(tangent), 0.001));
  let grain = smoothstep(0.2, 0.8, 0.5 + 0.5 * sin(along * 14.0));
  // ── Idea 5: chemical boundary
  // The activator gradient already orients the coat grain. Where it is steep
  // the morphogen front is sharp, so the soft threshold tightens there only.
  let frontSharp = smoothstep(0.02, 0.25, length(gA));

  let caStr = 0.003 * (1.0 + bass) * depthScale;
  let rAI = activatorInhibitor(uv + vec2<f32>(caStr, 0.0), scale, time);
  let gAI = activatorInhibitor(uv, scale, time);
  let bAI = activatorInhibitor(uv - vec2<f32>(caStr, 0.0), scale, time);

  var pattern = vec3<f32>(0.0);
  var curvature = vec3<f32>(0.0);
  for (var ch = 0; ch < 3; ch++) {
    let ai = select(select(bAI, gAI, ch == 1), rAI, ch == 0);
    let diff = ai.x - ai.y * (kill / max(feed, 0.001));
    let spots = smoothstep(0.15, 0.35, diff) * (1.0 - smoothstep(0.35, 0.6, diff));
    let stripes = smoothstep(0.05, 0.25, diff) * (1.0 - smoothstep(0.25, 0.45, diff)) * 0.7 * mix(0.3, 1.0, grain);
    let labyrinth = smoothstep(-0.1, 0.1, diff) * (1.0 - smoothstep(0.1, 0.3, diff)) * 0.5;
    let c1 = step(fkLocal, 0.01);
    let c2 = step(0.01, fkLocal) * step(fkLocal, 0.02);
    let c3 = step(0.02, fkLocal);
    let pat = spots * c1 + stripes * c2 + labyrinth * c3;
    pattern[ch] = pat;
    curvature[ch] = abs(diff - vnoise(uv * scale * 3.0 + f32(ch) * 1.7));
  }

  pattern = mix(pattern, smoothstep(vec3<f32>(0.18), vec3<f32>(0.48), pattern), vec3<f32>(frontSharp * 0.65));

  let mDist = length(uv - mouse);
  let deposit = exp(-mDist * mDist * 2000.0) * 0.4 * f32(mouseDown);
  pattern += vec3<f32>(deposit);

  let patternDensity = clamp(dot(pattern, vec3<f32>(0.333)), 0.0, 1.0);
  let boundCurve = clamp(dot(curvature, vec3<f32>(0.333)), 0.0, 1.0);

  // Idea 1 — inhibitor halo around spots (Turing's inhibitor field, not a vignette).
  let gDiff = gAI.x - gAI.y * (kill / max(feed, 0.001));
  let spotMask = smoothstep(0.15, 0.35, gDiff) * (1.0 - smoothstep(0.35, 0.6, gDiff));
  let halo = smoothstep(0.18, 0.42, gAI.y) * (1.0 - spotMask) * (0.55 + mids * 0.35);

  // Idea 2 — chemical-front ridges where activator ≈ scaled inhibitor.
  let front = exp(-abs(gDiff) * 14.0) * (0.35 + treble * 0.4);

  // ── Idea 6: stain aging
  // Display history is the stain. Pigment that persisted last frame walks
  // the same organic ramp. Color Shift still sets the global offset.
  let stain = clamp(dot(prev.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
  let aged = p4 + stain * 0.16;
  var color = vec3<f32>(
    organicColor(pattern.r, aged).r,
    organicColor(pattern.g, aged + 0.05).g,
    organicColor(pattern.b, aged + 0.1).b
  );
  color = color * (1.0 - halo * 0.55) + vec3<f32>(0.12, 0.08, 0.05) * halo;
  color += vec3<f32>(0.95, 0.88, 0.62) * front;

  let bloom = smoothstep(0.3, 0.7, boundCurve) * 0.15 * (1.0 + bass);
  color += vec3<f32>(0.85, 0.75, 0.55) * bloom;

  let vignette = 1.0 - smoothstep(0.3, 0.75, length(uv - 0.5));
  color *= 0.8 + vignette * 0.2;

  let persistence = 0.94 + bass * 0.03;
  color = max(color, prev.rgb * persistence * 0.4);

  color = acesToneMap(color * 1.2);

  let alpha = clamp(patternDensity * boundCurve * max(depth, 0.15) + halo * 0.2 + front * 0.25, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(patternDensity, 0.0, 0.0, 0.0));

  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
}
