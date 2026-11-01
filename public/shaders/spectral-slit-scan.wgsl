// ═══════════════════════════════════════════════════════════════════
//  Spectral Slit Scan
//  Category: artistic
//  Features: audio-reactive, mouse-driven, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-01
//  Ideas: wavelength-staggered slits; luma-hold; Cauchy bend (§12.2F); second diffraction order
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: aces_approx (filmic tone mapping) ═══
fn aces_approx(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 (deterministic noise) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn cauchyScale(bend: f32) -> vec3<f32> {
  let lam = vec3<f32>(0.650, 0.550, 0.450);
  let n = vec3<f32>(1.0) + vec3<f32>(bend) / (lam * lam);
  return n / max(n.y, 1e-4);
}

fn loadHistory(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(uv * resolution), vec2<i32>(0), maxCoord);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = step(0.5, u.zoom_config.w);
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let aspect = resolution.x / resolution.y;

  let slitCount = 3u + u32(round(u.zoom_params.x * 4.0));
  let trailDecay = 0.75 + u.zoom_params.y * 0.24;
  let chromaShift = u.zoom_params.z * 0.04;
  let curveAmp = u.zoom_params.w * 0.06;

  // Velocity driven by bass
  let velo = 1.0 + bass * 2.5;

  var accum = vec3<f32>(0.0);
  var totalWeight = 0.0;
  var maxAge = 0.0;

  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseFalloff = 1.0 - smoothstep(0.04, 0.42, length(mouseDelta));
  let mouseCurl = vec2<f32>(-mouseDelta.y, mouseDelta.x) * mouseFalloff * held * 0.08;

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.9) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickFront += smoothstep(0.024, 0.0, abs(length(delta) - age * 0.48)) * exp(-age * 1.45);
    }
  }

  for (var s: u32 = 0u; s < slitCount; s = s + 1u) {
    let fi = f32(s);
    let slitPhase = fi * 6.28318 / f32(slitCount);

    // Parametric slit curves: sine, spiral, radial
    var curveOff = vec2<f32>(0.0);
    if (s == 0u) {
      curveOff.x = sin(uv.y * 6.28 + time * velo * 0.7 + slitPhase) * curveAmp;
    } else if (s == 1u) {
      let ang = time * velo * 0.5 + fi * 2.094;
      curveOff = vec2<f32>(cos(ang), sin(ang)) * curveAmp * (0.5 + uv.y);
    } else {
      let rd = length(uv - 0.5);
      curveOff = normalize(uv - 0.5 + 0.001) * sin(rd * 12.0 - time * velo) * curveAmp;
    }

    // Mouse adds parallax offset per slit
    let mousePull = (mouse - 0.5) * 0.02 * (fi + 1.0) + mouseCurl;
    let parallax = (depth - 0.5) * 0.03 * (fi + 1.0);
    let slitRunner = pow(max(0.0, sin(uv.y * 74.0 + slitPhase - time * (14.0 + fi))), 14.0);

    let baseUV = uv + mousePull + parallax + vec2<f32>(slitRunner * 0.012 + clickFront * 0.018, 0.0);
    // ── Idea 3: Cauchy bend (§12.2F) ─────────────────────────────
    // The curve itself disperses: blue bends more than green, red less.
    // The linear R/G/B stagger below is unchanged.
    let disp = cauchyScale(chromaShift * 40.0);
    let sampleR = clamp(baseUV + curveOff * disp.x, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleG = clamp(baseUV + curveOff * disp.y, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleB = clamp(baseUV + curveOff * disp.z, vec2<f32>(0.0), vec2<f32>(1.0));

    // Idea 1 — wavelength-staggered slits (R/G/B ride neighboring slit offsets).
    let wr = chromaShift * (1.0 + fi * 0.18);
    let wb = chromaShift * max(0.35, 1.0 - fi * 0.12);
    let histR = loadHistory(sampleR + vec2<f32>(wr, 0.0), resolution);
    let histG = loadHistory(sampleG, resolution);
    let histB = loadHistory(sampleB - vec2<f32>(wb, 0.0), resolution);

    let age = clamp(1.0 - (histR.a + histG.a + histB.a) * 0.333, 0.0, 1.0);
    let decay = pow(trailDecay, fi + 1.0);
    let w = decay * (1.0 + bass * 0.5 + slitRunner * 0.25 + clickFront * 0.4);

    // Idea 2 — luma-hold: dark history keeps more of C (slit does not eat shadows).
    let histLuma = dot(histG.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let hold = 1.0 - smoothstep(0.0, 0.22, histLuma);
    accum.r = accum.r + mix(mix(histR.r, histG.r, 0.3), histG.r, hold * 0.45) * w;
    accum.g = accum.g + mix(mix(histG.g, histB.g, 0.3), histG.g, hold * 0.45) * w;
    accum.b = accum.b + mix(mix(histB.b, histR.b, 0.3), histG.b, hold * 0.45) * w;
    // ── Idea 4: second diffraction order ─────────────────────────
    // A fainter copy one grating-step further out. Weight tracks Chromatic Shift.
    let orderUV = clamp(sampleG + vec2<f32>(chromaShift * 2.5, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let order2 = loadHistory(orderUV, resolution).rgb;
    let orderW = w * 0.35 * clamp(chromaShift / 0.04, 0.0, 1.0);
    accum = accum + order2 * orderW;
    totalWeight = totalWeight + w + orderW;
    maxAge = max(maxAge, age);
  }

  if (totalWeight > 0.0) {
    accum = accum / totalWeight;
  }

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let feedback = mix(inputColor.rgb, accum, clamp(0.6 + mouseFalloff * held * 0.15 + clickFront * 0.2, 0.0, 0.9));

  // HDR streak accumulation with tone mapping
  let spectralPacket = vec3<f32>(0.25 + audio.z, 0.15 + audio.y, 0.4 + audio.x) * pow(max(0.0, sin(uv.x * 48.0 + uv.y * 19.0 - time * 17.0)), 16.0);
  var hdr = feedback * (1.0 + bass * 0.4) + spectralPacket * (0.12 + clickFront * 0.25);
  hdr = aces_approx(hdr);

  // Alpha: slit intensity × temporal accumulation age
  let slitIntensity = smoothstep(0.1, 0.9, totalWeight / f32(slitCount));
  let alpha = clamp(slitIntensity * (0.3 + maxAge * 0.7), 0.0, 1.0);

  let finalColor = vec4<f32>(hdr, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
