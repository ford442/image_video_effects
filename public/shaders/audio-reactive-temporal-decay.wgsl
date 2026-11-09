// ═══════════════════════════════════════════════════════════════════
//  Audio Reactive Temporal Decay — Spectral Cinema Edition
//  Category: post-processing
//  Features: audio-reactive, temporal, fft-bins, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-11-09
//  Ideas: row bright-pass anamorphic smear (replaces a fixed x=0.5 line); spectral persistence (bin range split in thirds -> separate R/G/B decay); bass push (trails re-sampled with a bass-scaled outward zoom)
//  A packing: linear trail RGBA (pre-grade blended history, exact C loads)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=DecayBase, y=AudioDrive, z=BinLo, w=BinHi

// Return normalised [0,1] magnitude for FFT bin `idx` (0-127).
fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

// Average FFT energy over bins [lo, hi] (inclusive).
fn avgBins(lo: u32, hi: u32) -> f32 {
  if (hi < lo) { return 0.0; }
  var acc = 0.0;
  for (var b = lo; b <= hi; b++) {
    acc += fftBin(b);
  }
  return acc / f32(hi - lo + 1u);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Temporal grain
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid * 1.3 + fract(time * 0.3) * 100.0);
    return (mix(t1, t2, 0.5) - 0.5) * (1.0 + treble * 0.3);
}

// Chromatic aberration on trails
fn trailChromatic(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let center = uv - vec2<f32>(0.5);
    let r2 = dot(center, center);
    return center * r2 * strength;
}

// Scanlines
fn scanlines(y: f32, time: f32, intensity: f32) -> f32 {
    let freq = 800.0;
    let scan = sin(y * freq) * 0.5 + 0.5;
    let fade = sin(y * freq * 0.5 + time * 2.0) * 0.3 + 0.7;
    return 1.0 - scan * intensity * fade;
}

// Vignette
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// IDEA 1: anamorphic streaks — bright-pass smear along the row, so every bright point
// spills sideways like a 2:1 anamorphic front element (HEAD drew one fixed line at x=0.5).
fn anamorphicStreaks(uv: vec2<f32>, px: f32, strength: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    for (var i: i32 = -6; i <= 6; i = i + 1) {
        if (i == 0) { continue; }
        let x = f32(i);
        let su = vec2<f32>(clamp(uv.x + x * px * 6.0, 0.0, 1.0), uv.y);
        let c = textureSampleLevel(readTexture, u_sampler, su, 0.0).rgb;
        let b = smoothstep(0.6, 0.95, dot(c, vec3<f32>(0.299, 0.587, 0.114)));
        acc = acc + c * b * exp(-abs(x) * 0.35);
    }
    return acc * vec3<f32>(0.6, 0.75, 1.0) * strength * 0.25;
}

// Bloom on bright areas (simple Gaussian approximation)
fn bloomApprox(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let blurSize = 0.003 * amount;
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    for (var i: i32 = -2; i <= 2; i = i + 1) {
        for (var j: i32 = -2; j <= 2; j = j + 1) {
            let offset = vec2<f32>(f32(i), f32(j)) * blurSize;
            let weight = exp(-f32(i * i + j * j) / 2.0);
            let sample = textureSampleLevel(tex, samp, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            let bright = smoothstep(0.5, 0.9, luma);
            bloom = bloom + sample * bright * weight;
            totalWeight = totalWeight + weight * bright;
        }
    }
    return bloom / max(totalWeight, 0.001);
}

// Spectral color from FFT bin energy
fn spectralColor(energy: f32, binIndex: f32) -> vec3<f32> {
    // Map bin index to hue (low freq = red, high freq = violet)
    let hue = binIndex / 127.0;
    var spec: vec3<f32>;
    if (hue < 0.17) {
        spec = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 0.5, 0.0), hue / 0.17);
    } else if (hue < 0.33) {
        spec = mix(vec3<f32>(1.0, 0.5, 0.0), vec3<f32>(1.0, 1.0, 0.0), (hue - 0.17) / 0.16);
    } else if (hue < 0.5) {
        spec = mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), (hue - 0.33) / 0.17);
    } else if (hue < 0.67) {
        spec = mix(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.5, 1.0), (hue - 0.5) / 0.17);
    } else if (hue < 0.83) {
        spec = mix(vec3<f32>(0.0, 0.5, 1.0), vec3<f32>(0.0, 0.0, 1.0), (hue - 0.67) / 0.16);
    } else {
        spec = mix(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.5, 0.0, 1.0), (hue - 0.83) / 0.17);
    }
    return spec * energy;
}

// Color grading: lift/gamma/gain
fn colorGrade(color: vec3<f32>, lift: vec3<f32>, gamma: vec3<f32>, gain: vec3<f32>) -> vec3<f32> {
    var c = color;
    c = c + lift * (1.0 - c);
    c = pow(c, gamma);
    c = c * gain;
    return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Parameters ──────────────────────────────────────────────────
  let decayBase  = mix(0.01, 0.30, u.zoom_params.x);
  let audioDrive = mix(0.0,  1.0,  u.zoom_params.y);
  let binLo      = u32(clamp(u.zoom_params.z * 127.0, 0.0, 127.0));
  let binHi      = u32(clamp(u.zoom_params.w * 127.0, f32(binLo), 127.0));

  // ── Frequency energy in the selected bin range ───────────────────
  let energy = avgBins(binLo, binHi);
  // IDEA 2: spectral persistence — split the chosen range into thirds; the low third
  // drives the red channel's decay, the middle green, the top blue.
  let span = binHi - binLo;
  let t1 = binLo + span / 3u;
  let t2 = binLo + (2u * span) / 3u;
  let eBand = vec3<f32>(avgBins(binLo, t1), avgBins(t1, t2), avgBins(t2, binHi));

  let AUDIO_DRIVE_CEILING = 0.4;
  let decay = clamp(decayBase + energy * audioDrive * AUDIO_DRIVE_CEILING, 0.001, 0.99);
  let decayRgb = clamp(vec3<f32>(decayBase) + mix(vec3<f32>(energy), eBand, 0.7) * audioDrive * AUDIO_DRIVE_CEILING,
                       vec3<f32>(0.001), vec3<f32>(0.99));

  // ── Cinematic params ──
  let caStrength = 0.01 + bass * 0.02;
  let scanlineIntensity = 0.04 + treble * 0.03;
  let vignetteStrength = 0.4 + bass * 0.15;
  let anamorphicStrength = 0.2 + bass * 0.3;
  let bloomAmount = 0.3 + mids * 0.4;
  let spectralAmount = 0.2 + energy * 0.3;

  // ── Sample current and previous-frame colour ─────────────────────
  let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // IDEA 3: bass push — history is fetched from slightly closer to the centre, so the
  // trail image grows outward each frame while bass is up.
  let push = 1.0 - bass * 0.012 * (0.5 + audioDrive);
  let histUv = (uv - 0.5) * push + 0.5;
  let caOffset = trailChromatic(uv, caStrength);
  let resI = vec2<i32>(res) - vec2<i32>(1);
  let pc = clamp(vec2<i32>(histUv * res), vec2<i32>(0), resI);
  let pr = clamp(vec2<i32>((histUv + caOffset) * res), vec2<i32>(0), resI);
  let pb = clamp(vec2<i32>((histUv - caOffset) * res), vec2<i32>(0), resI);
  // Exact C loads (rgba32float is not filterable); CA on trails kept from HEAD.
  let prevC = textureLoad(dataTextureC, pc, 0);
  var previous = vec4<f32>(textureLoad(dataTextureC, pr, 0).r, prevC.g, textureLoad(dataTextureC, pb, 0).b, prevC.a);
  previous = select(vec4<f32>(0.0), clamp(previous, vec4<f32>(0.0), vec4<f32>(4.0)), previous == previous);
  // first frame / shader switch: empty history adopts the live frame
  if (previous.a <= 0.0) { previous = current; }

  // ── Blend: per-channel decay toward the live frame ──
  var blended = vec4<f32>(mix(previous.rgb, current.rgb, decayRgb), mix(previous.a, current.a, decay));
  let trail = blended;

  // ── Spectral visualization overlay ──
  let midBin = f32(binLo + binHi) / 2.0;
  let specColor = spectralColor(energy, midBin) * spectralAmount;
  let specBlend = smoothstep(0.2, 0.8, energy) * 0.3;
  blended = vec4<f32>(blended.rgb + specColor * specBlend, blended.a);

  var color = blended.rgb;

  // ── Bloom on bright trail areas ──
  let bloom = bloomApprox(readTexture, u_sampler, uv, bloomAmount) * bloomAmount;
  color = color + bloom * vec3<f32>(0.5, 0.75, 1.0);

  // ── Film grain ──
  let grain = temporalGrain(vec2<f32>(global_id.xy), time, treble);
  color = color + grain * 0.05;

  // ── Scanlines ──
  let scan = scanlines(uv.y, time, scanlineIntensity);
  color = color * scan;

  // ── Vignette ──
  let vig = vignette(uv, vignetteStrength * 0.7);
  color = color * mix(0.5, 1.0, vig);

  // ── Color grading ──
  let lift = vec3<f32>(0.01, 0.005, -0.005) * (1.0 + bass * 0.1);
  let gamma = vec3<f32>(0.97, 0.98, 1.03) - mids * 0.03;
  let gain = vec3<f32>(1.03, 1.0, 0.97) * (1.0 + treble * 0.03);
  color = colorGrade(color, lift, gamma, gain);

  // ── Anamorphic streaks from bright points ──
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let brightMask = smoothstep(0.5, 0.9, luma);
  let streaks = anamorphicStreaks(uv, 1.0 / res.x, anamorphicStrength) * (0.5 + brightMask);
  color = color + streaks;

  color = max(color, vec3<f32>(0.0));
  let display = clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(blended.a + energy * 0.1, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(display, alpha));

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  // Persist blended frame in dataTextureA for next-frame access via dataTextureC
  // A keeps the ungraded trail so grade/vignette/scanlines never compound frame to frame.
  textureStore(dataTextureA, global_id.xy, vec4<f32>(trail.rgb, max(trail.a, 0.004)));
}