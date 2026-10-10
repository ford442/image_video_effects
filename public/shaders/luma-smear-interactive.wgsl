// ═══════════════════════════════════════════════════════════════════
//  Luma Smear Interactive (Kinetic Echo)
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-06
//  Ideas: luma-gradient slide (bright bleeds downhill into dark); wet-edge pigment ridge where trail energy ends
//  A packing: linear pre-ACES trail RGB (pre-audio/boost/ridge) + A.a = trail energy; (0,0) = state texel (prev mouse xy, prev time, sentinel -7)
//  Motion: chromatic R-lag / B-lead streaks + curl-advected exact-C trails (2026-08-30)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 3; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.012;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t);
  return vec2<f32>((n3 - n4) / (2.0 * eps), -(n1 - n2) / (2.0 * eps));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(uv: vec2<f32>, dims: vec2<f32>) -> vec4<f32> {
  var c = vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(0.999)) * dims);
  // (0,0) holds the pointer state texel, never trail colour.
  if (c.x == 0 && c.y == 0) { c.x = 1; }
  let v = textureLoad(dataTextureC, c, 0);
  return select(vec4<f32>(0.0), clamp(v, vec4<f32>(0.0), vec4<f32>(16.0)), all(v == v));
}

fn lumaOf(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Pointer velocity from the (0,0) state texel (replaces the extraBuffer spring, which never
  // persisted): xy = last frame's mouse, z = last frame's time, w = -7 sentinel.
  let state = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stateOk = state.w == -7.0 && all(state == state);
  let stateDt = clamp(time - state.z, 0.004, 0.1);
  let mouseVel = select(vec2<f32>(0.0), clamp((mouse - state.xy) / stateDt, vec2<f32>(-3.0), vec2<f32>(3.0)), stateOk);
  let spring = mouse;

  let decay = u.zoom_params.x;
  let lumaThreshold = u.zoom_params.y;
  let colorShift = u.zoom_params.z;
  let eraser = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = lumaOf(src.rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let viscosity = mix(1.45, 0.28, depth);

  let aUv = vec2<f32>(uv.x * aspect, uv.y);
  let aMouse = vec2<f32>(spring.x * aspect, spring.y);
  let dist = distance(aUv, aMouse);
  let eraserMask = smoothstep(eraser * 0.28 + 0.02, eraser * 0.08, dist);
  let mouseGust = smoothstep(0.28, 0.0, dist);

  let smearAmt = max(0.0, luma - lumaThreshold) * (0.7 + decay * 1.4) * (1.0 + bass * 0.45);
  let curl = curl2D(uv * 3.2 + time * 0.16, time * 0.28) * (0.006 + mids * 0.004);
  let toPix = aUv - aMouse;
  let dir = toPix / max(length(toPix), 1e-4);
  var velocity = dir * smearAmt * viscosity * 0.018 + curl;
  velocity = velocity + dir * bass * 0.012 * mouseGust;
  // Drag: pointer velocity pushes trails under the cursor gust.
  velocity = velocity + clamp(mouseVel * 0.04, vec2<f32>(-0.08), vec2<f32>(0.08)) * mouseGust;

  // IDEA 1 — luma-gradient slide: the smear also runs downhill on the luma slope (bright
  // bleeds into dark), faster where the slope is steep. Central differences over ±2 px.
  let px = 2.0 / dims;
  let lR = lumaOf(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb);
  let lL = lumaOf(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb);
  let lD = lumaOf(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb);
  let lU = lumaOf(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb);
  let lumaGrad = vec2<f32>(lR - lL, lD - lU) * 0.5;
  velocity = velocity - lumaGrad * smearAmt * viscosity * 0.06;
  velocity = select(velocity, vec2<f32>(0.0), held && eraserMask > 0.55);

  var clickKick = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 1.8;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    clickKick = clickKick + select(0.0, exp(-abs(rd - age * 0.7) * 14.0) * exp(-age * 1.6), alive);
  }
  velocity = clamp(velocity * (1.0 + clickKick * 0.8), vec2<f32>(-0.09), vec2<f32>(0.09));

  let persist = mix(0.35, 0.92, decay);
  let shift = 0.55 + colorShift * 1.35;
  let prev = loadC(uv - velocity, dims);
  let rTrail = loadC(uv - velocity * (1.15 + shift * 0.25), dims).r;
  let bTrail = loadC(uv - velocity * (0.72 - colorShift * 0.12), dims).b;
  let chromaPrev = vec3<f32>(rTrail, prev.g, bTrail);

  var trail = mix(src.rgb, chromaPrev, persist * smearAmt / max(smearAmt + 0.15, 0.001));
  trail = mix(trail, src.rgb, eraserMask * select(0.35, 1.0, held));
  var hdr = trail + vec3<f32>(treble * 0.08, treble * 0.05, clickKick * 0.12);
  let luma2 = lumaOf(hdr);
  hdr = luma2 + (hdr - vec3<f32>(luma2)) * (1.15 + colorShift * 0.35);

  // IDEA 2 — wet-edge ridge: where last frame's trail energy (C.a) drops sharply — the end or
  // rim of a smear — pigment piles up into a darker, denser ridge (display only).
  let eR = loadC(uv + vec2<f32>(px.x, 0.0), dims).a;
  let eL = loadC(uv - vec2<f32>(px.x, 0.0), dims).a;
  let eD = loadC(uv + vec2<f32>(0.0, px.y), dims).a;
  let eU = loadC(uv - vec2<f32>(0.0, px.y), dims).a;
  let ridge = smoothstep(0.03, 0.25, length(vec2<f32>(eR - eL, eD - eU))) * (1.0 - eraserMask);
  let lumaR = lumaOf(hdr);
  hdr = (lumaR + (hdr - vec3<f32>(lumaR)) * (1.0 + 0.4 * ridge)) * (1.0 - 0.28 * ridge);

  let rgb = acesToneMap(max(hdr, vec3<f32>(0.0)) * 1.06);
  let energy = clamp(smearAmt * 0.55 + persist * 0.25 + clickKick * 0.3 + prev.a * persist * 0.4, 0.08, 0.98);

  textureStore(writeTexture, coord, vec4<f32>(rgb, clamp(energy + ridge * 0.15, 0.0, 1.0)));
  if (gid.x == 0u && gid.y == 0u) {
    textureStore(dataTextureA, coord, vec4<f32>(mouse, time, -7.0));
  } else {
    textureStore(dataTextureA, coord, vec4<f32>(clamp(trail, vec3<f32>(0.0), vec3<f32>(16.0)), energy));
  }
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
