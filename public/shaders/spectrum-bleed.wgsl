// ═══════════════════════════════════════════════════════════════════
//  Spectrum Bleed
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-21
//  Ideas: wavelength-ordered bleed distance; chromatographic advance front;
//         dry-edge rim; chroma delay line (§12.2B);
//         paper-fibre wicking (§12.2C paper granulation)
//  A packing: ACES display RGBA (C is read as colour through an advected coord)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let mx = max(max(c.r, c.g), c.b); let mn = min(min(c.r, c.g), c.b); let d = mx - mn;
  var h = 0.0;
  if (d > 0.00001) {
    if (mx == c.r) { h = (c.g - c.b) / d + select(0.0, 6.0, c.g < c.b); }
    else if (mx == c.g) { h = (c.b - c.r) / d + 2.0; }
    else { h = (c.r - c.g) / d + 4.0; }
    h /= 6.0;
  }
  return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = abs(fract(hsv.x + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0));
  return hsv.z * mix(vec3<f32>(1.0), clamp(k - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

// Integer PCG hash + quintic value noise — copied verbatim from
// public/shaders/_std/_std_hash.wgsl (pcg2d, u32ToUnit, hashCell21) and
// _std_noise.wgsl (fade2, valueNoise).
fn pcg2d(v_in: vec2<u32>) -> vec2<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  return v;
}

fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}

fn hashCell21(c: vec2<i32>) -> f32 {
  return u32ToUnit(pcg2d(bitcast<vec2<u32>>(c)).x);
}

fn fade2(t: vec2<f32>) -> vec2<f32> {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = vec2<i32>(floor(p));
  let u = fade2(fract(p));
  let a = hashCell21(i);
  let b = hashCell21(i + vec2<i32>(1, 0));
  let c = hashCell21(i + vec2<i32>(0, 1));
  let d = hashCell21(i + vec2<i32>(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn blurSource(uv: vec2<f32>, radius: f32) -> vec3<f32> {
  let texel = radius / u.config.zw;
  var sum = vec3<f32>(0.0);
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return sum * 0.25;
}

// ── Idea 1: wavelength-ordered bleed distance ──────────────────────
// A spectrum bleed has to separate BY wavelength. Short wavelengths scatter
// further in a wet medium, so blue must travel further than green and green
// further than red. HEAD ran all three channels through one radius, which
// is a blur — the fringes that make this effect its own thing never formed.
fn spectralBleed(uv: vec2<f32>, radius: f32) -> vec3<f32> {
  return vec3<f32>(
    blurSource(uv, radius * 0.55).r,
    blurSource(uv, radius * 1.00).g,
    blurSource(uv, radius * 1.70).b
  );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let time = u.config.x;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: intensity, hue speed, blur scale, saturation detail.
  var blendFactor = u.zoom_params.x * 0.6;
  let hueSpeed = u.zoom_params.y;
  let blurRadius = mix(1.0, 4.0, u.zoom_params.z);
  let saturationBoost = u.zoom_params.w * 0.5;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 9.5; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lensDist = length((uv - springPos) * aspectVec);
  let lens = smoothstep(0.36, 0.0, lensDist) * select(0.5, 1.0, u.zoom_config.w > 0.5);
  blendFactor = clamp(blendFactor + lens * 0.3, 0.0, 1.0);

  // ── Idea 5: paper-fibre wicking (§12.2C paper granulation) ────────
  // Ink does not creep evenly across a sheet: it runs further down open
  // fibres and stalls on tight ones. A static (time-free), vertically
  // stretched value-noise grain scales this pixel's bleed radius, so the
  // fringes and the advancing front come out fibrous instead of a clean blur.
  let fibre = valueNoise(vec2<f32>(pixel) / vec2<f32>(2.0, 10.0));
  let localRadius = blurRadius * (0.55 + 0.9 * fibre);

  // ── Idea 4: chroma delay line (§12.2B, 4:2:0-style) ───────────────
  // Colour is carried on a narrower, later channel than brightness: the
  // wavelength-ordered bleed is fetched `delay` texels LEFT of this pixel so
  // colour trails to the right of an edge, then half of the luma is taken
  // back from the crisp source. Edges stay firm, the colour smears after
  // them. The delay rides the existing scale slider (via the local radius).
  let chromaDelay = vec2<f32>(localRadius * 1.6 / res.x, 0.0);
  let bleedRaw = spectralBleed(clamp(uv - chromaDelay, vec2<f32>(0.0), vec2<f32>(1.0)), localRadius);
  let lumaW = vec3<f32>(0.299, 0.587, 0.114);
  let bleedYC = max(bleedRaw + (dot(source.rgb, lumaW) - dot(bleedRaw, lumaW)) * 0.5, vec3<f32>(0.0));
  var hsv = rgb2hsv(bleedYC);
  var clickInk = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 1.5) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let ink = smoothstep(0.30 + age * 0.04, 0.0, dist) * exp(-age * 2.0);
    clickInk += ink; hsv.y = min(hsv.y + ink * 0.4, 1.0);
  }

  let band = min(u32(clamp(uv.x * 128.0, 0.0, 127.0)), 7u);
  let fftVoice = plasmaBuffer[band + 1u].x;
  hsv.x = fract(hsv.x + hueSpeed * time * 0.1 + fftVoice * 0.2 + mids * 0.04);
  hsv.y = min(hsv.y + saturationBoost + treble * 0.08, 1.0);
  var hdr = mix(source.rgb, hsv2rgb(hsv), blendFactor);

  let historyUv = clamp(uv - springVel * lens * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);

  // ── Idea 2: chromatographic advance front ─────────────────────────
  // Ink on paper does not smear evenly — it piles into a travelling band
  // whose leading edge is wherever concentration is still climbing. Gating
  // the history weight on the saturation gradient makes the bleed gather
  // into a front, instead of the flat wash a constant weight produced.
  let satNow = rgb2hsv(max(hdr, vec3<f32>(0.0))).y;
  let satPrev = rgb2hsv(max(previous.rgb, vec3<f32>(0.0))).y;
  let advance = clamp((satNow - satPrev) * 2.5, -1.0, 1.0);
  let frontGate = 1.0 + advance * 0.75;
  let persistence = clamp((0.12 + u.zoom_params.x * 0.2 + clickInk * 0.22) * frontGate * (0.8 + 0.4 * fibre), 0.0, 0.72);
  hdr = mix(hdr, previous.rgb * (0.93 + bass * 0.02), persistence);

  // ── Idea 3: dry-edge rim ──────────────────────────────────────────
  // Where the front halts, solute concentrates and leaves the darker,
  // more saturated ring every chromatogram and every coffee stain has. It
  // lives exactly where the advance term goes negative — where the ink
  // stopped moving — so it costs no extra state.
  let dryRim = clamp(-advance, 0.0, 1.0) * smoothstep(0.08, 0.35, satPrev);
  let rimHsv = rgb2hsv(max(hdr, vec3<f32>(0.0)));
  let rimmed = hsv2rgb(vec3<f32>(rimHsv.x, min(rimHsv.y + dryRim * 0.5, 1.0), rimHsv.z * (1.0 - dryRim * 0.45)));
  hdr = mix(hdr, rimmed, blendFactor);

  hdr += vec3<f32>(0.10, 0.02, 0.16) * fftVoice * treble * blendFactor;
  let effectEnergy = clamp(blendFactor * 0.65 + clickInk * 0.35 + previous.a * persistence * 0.3 + dryRim * 0.15, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
