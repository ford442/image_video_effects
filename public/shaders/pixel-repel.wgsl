// ═══════════════════════════════════════════════════════════════════
//  Pixel Repel v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, curl-noise, spectral-ca, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: true spectral taps across the 7-tap spread; pile-up rim from disp divergence; drag wake from real pointer velocity
//  A packing: texel (0,0) = (prevMouse.xy, prevTime, valid); texel (1,0) = (smoothed pointer velocity uv/s .xy, 0, 0); other texels = ACES display RGBA (unread)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let n = dot(i, vec2<f32>(127.1, 311.7));
  return mix(mix(fract(sin(n) * 43758.5453), fract(sin(n + 127.1) * 43758.5453), w.x),
             mix(fract(sin(n + 311.7) * 43758.5453), fract(sin(n + 438.8) * 43758.5453), w.x), w.y);
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n0 = noise2(p + t * 0.3);
  return vec2<f32>(-(noise2(p + vec2<f32>(0.0, eps) + t * 0.3) - n0) / eps,
                    (noise2(p + vec2<f32>(eps, 0.0) + t * 0.3) - n0) / eps);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43); let d = vec3<f32>(0.59); let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sellipse(d: vec2<f32>, r: f32, e: f32) -> f32 {
  let p = pow(abs(d.x), e) + pow(abs(d.y), e);
  return 1.0 - smoothstep(0.0, pow(r, e), p);
}

// Four orbiting superellipse lobes around the cursor (HEAD kernel, now a
// function so the pile-up rim can take its divergence). Returns displacement
// in uv units (x divided by aspect — HEAD applied aspect-space vectors to uv).
fn lobe_disp(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, radius: f32, strength: f32,
             bass: f32, time: f32, vdir: vec2<f32>, stretch: f32) -> vec2<f32> {
  var disp = vec2<f32>(0.0);
  for (var i: u32 = 0u; i < 4u; i = i + 1u) {
    let fi = f32(i);
    let angle = time * (0.4 + fi * 0.15) + fi * 1.570796;
    let off = vec2<f32>(cos(angle), sin(angle)) * radius * (0.6 + fi * 0.25);
    var sd = (uv - mouse - off) * vec2<f32>(aspect, 1.0);
    // Idea 3: drag wake — the half of each lobe behind the pointer's motion is
    // stretched backwards by `stretch`, so a dragged repeller leaves a tail.
    let along = dot(sd, vdir);
    let alongW = select(along, along / stretch, along < 0.0);
    sd = sd + vdir * (alongW - along);
    let liss = vec2<f32>(sin(time * (1.1 + fi * 0.3) + fi) * 0.08, cos(time * (0.9 + fi * 0.2) + fi) * 0.06);
    let mask = sellipse(sd + liss, radius * (0.5 - fi * 0.08), 2.4 + fi * 0.4);
    let distL = length(sd + liss);
    let dir = select(vec2<f32>(0.0), (sd + liss) / max(distL, 0.0001), distL > 0.0001);
    disp = disp + dir * (1.0 - smoothstep(0.0, radius, distL)) * mask * strength * 0.12 * (1.0 + bass * 0.6);
  }
  return disp / vec2<f32>(aspect, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= res.x || global_id.y >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);

  let resF = vec2<f32>(res);
  let uv = vec2<f32>(global_id.xy) / resF;
  let aspect = u.config.z / u.config.w;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  let radius = max(u.zoom_params.x * 0.5, 0.05);
  let strength = u.zoom_params.y;
  let aberration = u.zoom_params.z;          // 0..0.2 → spectral fringe width/weight
  let smoothing = u.zoom_params.w;           // falloff softness + wake length/inertia

  // ── Pointer state from A texels (0,0)/(1,0), read back exactly from C ──
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let dt = time - st0.z;
  let stateOk = st0.w > 0.5 && dt > 1e-3 && dt < 0.5 && all(abs(st1.xy) < vec2<f32>(100.0));
  var instVel = select(vec2<f32>(0.0), (mouse - st0.xy) / max(dt, 1e-3), stateOk);
  let ivLen = length(instVel);
  instVel = instVel * min(1.0, 3.0 / max(ivLen, 1e-4));            // clamp 3 uv/s
  let tau = mix(0.03, 0.4, smoothing);                               // velocity inertia (s)
  let k = select(0.0, 1.0 - exp(-max(dt, 0.0) / tau), stateOk);
  let prevVel = select(vec2<f32>(0.0), st1.xy, stateOk);
  let ptrVel = mix(prevVel, instVel, k);
  let speed = length(ptrVel * vec2<f32>(aspect, 1.0));
  let vdir = select(vec2<f32>(1.0, 0.0), normalize(ptrVel * vec2<f32>(aspect, 1.0)), speed > 1e-3);
  let wakeTime = mix(0.05, 0.35, smoothing);                         // seconds of travel the tail spans
  let stretch = clamp(1.0 + speed * wakeTime / max(radius * 0.4, 0.02), 1.0, 6.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthGain = 1.0 + (1.0 - depth) * 0.5;

  var disp = lobe_disp(uv, mouse, aspect, radius, strength, bass, time, vdir, stretch);

  disp = disp + curl2(uv * 6.0 + mouse * 3.0, time * 0.5) * mids * 0.06 * (1.0 + bass);
  let dUV = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mainFalloff = 1.0 - smoothstep(radius * 0.3, radius * (1.0 - smoothing * 0.4), length(dUV));
  let idleWobble = vec2<f32>(cos(time * 2.3), sin(time * 1.7)) * 0.02;
  // Idea 3: drag wake — real pointer velocity drags the pixels under the cursor along.
  let dragRaw = ptrVel * wakeTime * 0.5;
  let drag = dragRaw * min(1.0, radius * 0.5 / max(length(dragRaw), 1e-5)); // a flick must not teleport content
  disp = disp + (idleWobble + drag) * mainFalloff * strength * (1.0 + bass);
  disp = disp * depthGain;

  let effStr = clamp(length(disp) * 15.0, 0.0, 1.0);

  // Idea 2: pile-up rim — where pushed pixels bunch up (negative divergence of
  // disp: output→source map compresses), the image brightens into a crest.
  let px = vec2<f32>(1.5 / resF.x, 0.0);
  let py = vec2<f32>(0.0, 1.5 / resF.y);
  let dR = lobe_disp(uv + px, mouse, aspect, radius, strength, bass, time, vdir, stretch);
  let dL = lobe_disp(uv - px, mouse, aspect, radius, strength, bass, time, vdir, stretch);
  let dD = lobe_disp(uv + py, mouse, aspect, radius, strength, bass, time, vdir, stretch);
  let dU = lobe_disp(uv - py, mouse, aspect, radius, strength, bass, time, vdir, stretch);
  let divg = ((dR.x - dL.x) / (2.0 * px.x) + (dD.y - dU.y) / (2.0 * py.y)) * depthGain;
  let pile = smoothstep(0.8, 4.0, -divg);

  // Idea 1: true spectral taps — the 7-tap spread along disp is split into
  // red→green→blue wavelength weights, so lobe edges throw prism fringes.
  // `aberration` sets the spread (width); weights renormalize per channel.
  let spread = aberration * 5.0;
  var acc = vec3<f32>(0.0);
  var wsum = vec3<f32>(0.0);
  var srcA = 0.0;
  for (var i: i32 = 0; i < 7; i = i + 1) {
    let s = f32(i) / 6.0;
    let fi = s * 2.0 - 1.0;
    let tapUV = clamp(uv - disp * (1.0 + fi * spread), vec2<f32>(0.0), vec2<f32>(1.0));
    let samp = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0);
    let dr = (s - 0.1) / 0.3; let dg = (s - 0.5) / 0.3; let db = (s - 0.9) / 0.3;
    let wv = vec3<f32>(exp(-dr * dr), exp(-dg * dg), exp(-db * db));
    acc = acc + samp.rgb * wv;
    wsum = wsum + wv;
    srcA = srcA + samp.a * wv.g;
  }
  let displaced = acc / max(wsum, vec3<f32>(1e-4));
  srcA = srcA / max(wsum.g, 1e-4);

  let lum = dot(displaced, vec3<f32>(0.299, 0.587, 0.114));
  let crest = vec3<f32>(1.0, 0.96, 0.88) * pile * (0.35 + lum * 0.4) * (1.0 + treble * 1.5);
  let boosted = displaced + crest + vec3<f32>(lum * 0.08 * mids);
  let tone = aces_tonemap(max(boosted * (1.0 + bass * 0.3), vec3<f32>(0.0)));
  // Coverage of the displaced sheet: opaque photo, slightly denser where pushed/piled.
  let alpha = clamp(srcA * mix(0.9, 1.0, max(effStr, pile)), 0.0, 1.0);

  // Truthful depth: the depth travels with the displaced content; crests lift.
  let movedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - disp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  textureStore(writeTexture, coord, vec4<f32>(tone, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(movedDepth + pile * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));

  var aOut = vec4<f32>(tone, alpha);
  if (coord.x == 0 && coord.y == 0) { aOut = vec4<f32>(mouse, time, 1.0); }
  if (coord.x == 1 && coord.y == 0) { aOut = vec4<f32>(ptrVel, 0.0, 0.0); }
  textureStore(dataTextureA, coord, aOut);
}
