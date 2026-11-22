// ═══════════════════════════════════════════════════════════════════
//  DLA Crystals — Render
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: tip glow; facet glint; growth rings
//  A packing: raw sim (frozen, time, hue, facet angle). ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  Reads the frozen field after the walker pass (dataA → dataC barrier),
//  plants seeds (centre on ring re-arm, pointer, ripples), draws crystal +
//  fading walker trails, and carries the field forward in dataA.

#include "_prelude.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(2) var<uniform> simParams: SimParams;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  let y = max(x, vec3<f32>(0.0));
  return clamp((y * (a * y + b)) / (y * (c * y + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hueToRgb(hue: f32, c: f32) -> vec3<f32> {
  let h = fract(hue) * 6.0;
  let x = c * (1.0 - abs((h % 2.0) - 1.0));
  if (h < 1.0) { return vec3<f32>(c, x, 0.0); }
  if (h < 2.0) { return vec3<f32>(x, c, 0.0); }
  if (h < 3.0) { return vec3<f32>(0.0, c, x); }
  if (h < 4.0) { return vec3<f32>(0.0, x, c); }
  if (h < 5.0) { return vec3<f32>(x, 0.0, c); }
  return vec3<f32>(c, 0.0, x);
}

fn neighborFrozen(p: vec2<i32>, resI: vec2<i32>) -> f32 {
  var maxF = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let n = textureLoad(dataTextureC, clamp(p + vec2<i32>(dx, dy), vec2<i32>(0), resI - vec2<i32>(1)), 0);
      maxF = max(maxF, n.r);
    }
  }
  return maxF;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let treble = plasmaBuffer[0].z;
  let attractStrength = mix(0.0, 0.5, u.zoom_params.y);
  var st = textureLoad(dataTextureC, pixel, 0);

  // Ring (re)armed → clear the previous shader's field and plant a centre seed.
  if (simParams.frame == 0u) {
    st = vec4<f32>(0.0);
    if (length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0)) < 0.006) {
      st = vec4<f32>(1.0, time, 0.55, 0.0);
    }
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let ageR = time - rp.z;
    if (ageR > 0.0 && ageR < 0.5 && length((uv - rp.xy) * vec2<f32>(aspect, 1.0)) < 0.02 && st.r < 0.5) {
      st = vec4<f32>(1.0, time, hash21(rp.xy) * 0.3 + 0.6, f32(i) / 50.0);
    }
  }

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  if (mouseDown && length((uv - mouse) * vec2<f32>(aspect, 1.0)) < 0.012 + attractStrength * 0.02 && st.r < 0.5) {
    st = vec4<f32>(1.0, time, 0.55, 0.0);
  }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var col = src.rgb * 0.65;
  var edge = 0.0;
  var trail = 0.0;
  if (st.r > 0.5) {
    let rgb = hueToRgb(st.b + st.a * 0.2, 0.8);
    let glow = exp(-max(time - st.g, 0.0) * 0.4) * 0.4 + 0.6;
    edge = 1.0 - neighborFrozen(pixel, resI);
    col = rgb * glow;
    // ── Idea 1: tip glow — exposed tips take a cool highlight; the interior stays the body
    col = col + vec3<f32>(0.72, 0.88, 1.0) * edge * 0.55;
    // ── Idea 2: facet glint — the growth angle the walker stored catches a fixed light
    let facetAng = st.a * 6.2831853;
    let glint = pow(max(cos(facetAng - 0.9), 0.0), 8.0);
    col = col + vec3<f32>(1.0) * glint * (0.15 + edge * 0.45);
    // ── Idea 3: growth rings — freeze age lays faint annuli, one shell per generation
    let age = max(time - st.g, 0.0);
    let rings = 0.5 + 0.5 * sin(age * 7.0);
    col = col + rgb * rings * 0.12;
    let sparkle = pow(max(hash21(uv * 1000.0 + vec2<f32>(time * 10.0)), 0.0), 8.0) * (0.35 + treble * 0.25);
    col += vec3<f32>(sparkle);
  } else if (st.g > 0.0) {
    // Walker trail: brightest where a walker just passed, fading over ~0.3 s.
    trail = exp(-max(time - st.g, 0.0) * 8.0);
    col += hueToRgb(st.b, 0.6) * trail * 0.45;
  }

  let frozenA = step(0.5, st.r);
  let alpha = clamp(src.a * 0.35 + frozenA * (0.55 + edge * 0.4) + trail * 0.5, 0.0, 1.0);
  let display = aces(col);
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));
  let depthOut = clamp(mix(depth, 0.2 + edge * 0.45, frozenA), 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, st);
}
