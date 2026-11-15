// ═══════════════════════════════════════════════════════════════════
//  Spectral FBM Displace
//  Category: hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: Cauchy scale on the warp split (§12.2F); upwind C trail; flow-aligned filament
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm2(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
    fbm2(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
  );
  let r = vec2<f32>(
    fbm2(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
    fbm2(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
  );
  return uv + amount * r;
}

fn cauchyScale() -> vec3<f32> {
  let lam = vec3<f32>(0.650, 0.550, 0.450);
  let n = 1.0 + 0.15 / (lam * lam);
  return n / n.y;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = textureDimensions(writeTexture);
  if (any(pixel >= vec2<i32>(dims))) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let fbmScale = mix(2.0, 24.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let warpAmt = mix(0.0, 0.35, clamp(u.zoom_params.y, 0.0, 1.0)) * (1.0 + held * 0.25);
  let spectralSpread = mix(0.0, 0.08, clamp(u.zoom_params.z, 0.0, 1.0));
  let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

  let mousePull = (mouse - uv) * held * 0.04;
  let warpedUV = domainWarp(uv + mousePull, time, fbmScale, warpAmt);
  let dispVec = warpedUV - uv;
  let spread = dispVec * spectralSpread * (1.0 + bass * 0.2);

  // ── Idea 1: Cauchy scale on the existing ±spread (§12.2F) ─────
  // Green stays on the warp. Blue (higher n) leaves farther than red.
  // Spectral Spread still sets the magnitude.
  let cay = cauchyScale();
  let rUV = clamp(uv + spread * cay.x, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - spread * cay.z, vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = src.g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var displaced = vec3<f32>(r, g, b);

  let conveyor = smoothstep(0.05, 0.0, abs(fract(uv.x * 12.0 + time * (2.0 + mids)) - 0.5));
  let runner = smoothstep(0.06, 0.0, abs(fract(uv.y * 8.0 - time * (3.2 + treble * 0.5)) - 0.5));
  let waveT = clamp(fbm2(uv * fbmScale * 0.5 + vec2<f32>(time * 0.08), 4), 0.0, 1.0);
  let lambda = mix(440.0, 680.0, waveT + conveyor * 0.15);
  let tint = wavelengthToRGB(lambda);
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(uv.x * 3.0 + time * 0.4) + vec3<f32>(0.0, 0.33, 0.67)));
  displaced = displaced + oilSlick * (conveyor + runner) * 0.12;
  displaced = mix(displaced, displaced * tint * 1.8, 0.35);

  // ── Idea 3: flow-aligned filament ──────────────────────────────
  // A band across the warp, not another axis conveyor. It fades where
  // the domain warp did not move the pixel.
  let flowLen = length(dispVec);
  let flowDir = dispVec / max(flowLen, 1e-4);
  let across = vec2<f32>(-flowDir.y, flowDir.x);
  let band = abs(fract(dot(uv, across) * 16.0 + time * 0.35) - 0.5);
  let filament = smoothstep(0.06, 0.0, band) * clamp(flowLen * 10.0, 0.0, 1.0);
  displaced = displaced + tint * filament * 0.16;

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      let d = length(uv - rp.xy);
      clickRing = max(clickRing, exp(-abs(d - age * 0.35) * 48.0) * (1.0 - age / 1.5));
    }
  }
  displaced += tint * clickRing * 0.4;

  var outRGB = mix(src.rgb, displaced, effectMix);
  // ── Idea 2: upwind C trail ─────────────────────────────────────
  // The old mix read C at this pixel. Sample upstream of the warp so
  // the trail follows the displacement. Weight stays 0.08.
  let advPx = clamp(vec2<i32>(vec2<f32>(pixel) - dispVec * vec2<f32>(dims) * 0.65), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let adv = textureLoad(dataTextureC, advPx, 0);
  outRGB = mix(outRGB, adv.rgb, 0.08 * effectMix);
  let alpha = clamp(mix(src.a, 0.55 + 0.45 * clamp(flowLen * 8.0, 0.0, 1.0), effectMix), 0.0, 1.0);
  let finalPixel = vec4<f32>(aces(max(outRGB, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
