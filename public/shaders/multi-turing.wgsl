// Multiscale Turing Patterns - Multiple reaction-diffusion systems combined
// Based on Jonathan McCabe's multiscale patterns
//  Rescue: 2026-10-05 — HEAD ran Gray-Scott with D·dt = 1 on an unnormalised 5-point Laplacian
//          (explicit Euler needs ≤ 0.25), so every texel clamped into a per-pixel checkerboard;
//          a stable kernel then relaxed to a uniform field because the seed was b ≈ 0.4 everywhere.
//          Now: Karl Sims' 3x3 Laplacian (stable at DA 1, DB 0.5, dt 1), sparse spot seeds
//          weighted by image luminance, and kill rates measured from the centre of the
//          pattern-forming band (it runs diagonally in F/K), so every slider position makes
//          patterns. Numpy-gated: scripts/sim_models/mt_rescue.py
//  A packing: (a1, b1, a2, b2) — scale 1 at 1 px, scale 2 at 2 px

#include "_prelude.wgsl"
// zoom_params: x=Feed1, y=Kill1, z=Feed2, w=Kill2

const DA: f32 = 1.0;
const DB: f32 = 0.5;
const DT: f32 = 1.0;

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453);
}

fn stateAt(pixel: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, (pixel % size + size) % size, 0);
}

// Karl Sims' kernel (0.2 edges, 0.05 corners, -1 centre) with taps `s` px apart.
fn sims(pixel: vec2<i32>, size: vec2<i32>, s: i32, c: vec4<f32>) -> vec4<f32> {
  let edges = stateAt(pixel + vec2<i32>(s, 0), size) + stateAt(pixel - vec2<i32>(s, 0), size)
            + stateAt(pixel + vec2<i32>(0, s), size) + stateAt(pixel - vec2<i32>(0, s), size);
  let corners = stateAt(pixel + vec2<i32>(s, s), size) + stateAt(pixel + vec2<i32>(-s, s), size)
              + stateAt(pixel + vec2<i32>(s, -s), size) + stateAt(pixel - vec2<i32>(s, s), size);
  return 0.2 * edges + 0.05 * corners - c;
}

// Centre of the pattern-forming kill band for a feed rate (measured, see mt_rescue.py).
fn killCentre(feed: f32) -> f32 {
  return 0.064 - 0.35 * max(0.05 - feed, 0.0);
}

// Gray-Scott reaction-diffusion step
fn grayScottStep(ab: vec2<f32>, lap: vec2<f32>, feed: f32, kill: f32) -> vec2<f32> {
  let a = ab.x;
  let b = ab.y;

  let reaction = a * b * b;

  let da = DA * lap.x - reaction + feed * (1.0 - a);
  let db = DB * lap.y + reaction - (kill + feed) * b;

  return vec2<f32>(
    clamp(a + da * DT, 0.0, 1.0),
    clamp(b + db * DT, 0.0, 1.0)
  );
}

// HSV to RGB helper
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  var c = v * s;
  var x = c * (1.0 - abs((h % 2.0) - 1.0));
  let m = v - c;
  var rgb: vec3<f32>;
  if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(m);
}

// Sparse seed: an 8 px cell holds a spot with probability rising with luminance.
fn seedSpot(p: vec2<f32>, lum: f32, salt: f32) -> f32 {
  let cell = floor(p / 8.0) + vec2<f32>(salt, 0.0);
  if (hash2(cell) >= 0.12 + 0.25 * lum) { return 0.0; }
  let d = length(p - (floor(p / 8.0) * 8.0 + 4.0));
  return select(0.0, 0.5 + 0.5 * hash2(p + salt), d < 2.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let pixel = vec2<i32>(coord);
  let sizeI = vec2<i32>(textureDimensions(dataTextureC));
  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;

  // Kill is an offset from the band centre, so no slider combination leaves the band.
  let feed1 = mix(0.025, 0.065, u.zoom_params.x);
  let kill1 = killCentre(feed1) + mix(-0.0025, 0.0025, u.zoom_params.y);
  let feed2 = mix(0.030, 0.060, u.zoom_params.z);
  let kill2 = killCentre(feed2) + mix(-0.0015, 0.0015, u.zoom_params.w);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let state = stateAt(pixel, sizeI);
  var scale1 = state.xy;
  var scale2 = state.zw;
  var lap1 = sims(pixel, sizeI, 1, state);
  // Scale 2: 2 px taps make bigger features; a quarter of the 1 px kernel keeps the
  // four pixel sub-lattices coupled (2 px taps alone leave a checker).
  var lap2 = 0.75 * sims(pixel, sizeI, 2, state) + 0.25 * lap1;

  // C starts at zero (a is ~1 wherever this shader has run): seed sparse spots.
  if (state.x + state.z < 0.001) {
    let p = vec2<f32>(pixel);
    scale1 = vec2<f32>(1.0, seedSpot(p, sourceLum, 0.0));
    scale2 = vec2<f32>(1.0, seedSpot(p, sourceLum, 17.0));
    lap1 = vec4<f32>(0.0);
    lap2 = vec4<f32>(0.0);
  }

  scale1 = grayScottStep(scale1, lap1.xy, feed1, kill1);
  scale2 = grayScottStep(scale2, lap2.zw, feed2, kill2);

  // Cross-scale coupling: a light pull between the two b fields.
  let coupling = 0.002;
  scale1.y = scale1.y + (scale2.y - scale1.y) * coupling;
  scale2.y = scale2.y + (scale1.y - scale2.y) * coupling * 0.5;

  // Mouse interaction - seed new patterns
  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.05) {
    var strength = 1.0 - mouseDist / 0.05;
    scale1.y = scale1.y + strength * 0.3;
    scale2.y = scale2.y + strength * 0.2;
  }

  // Ripple seeding
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = time - ripple.z;
    if (rippleAge > 0.0 && rippleAge < 1.0) {
      var dist = length(uv - ripple.xy);
      if (dist < 0.04) {
        var strength = (1.0 - rippleAge) * (1.0 - dist / 0.04);
        scale1.y = scale1.y + strength * 0.5;
        scale2.y = scale2.y + strength * 0.3;
      }
    }
  }
  scale1 = clamp(scale1, vec2<f32>(0.0), vec2<f32>(1.0));
  scale2 = clamp(scale2, vec2<f32>(0.0), vec2<f32>(1.0));

  // Store state
  textureStore(dataTextureA, pixel, vec4<f32>(scale1, scale2));

  // Colour: different hues for the two scales. Stable Gray-Scott keeps b in ~0.1..0.35
  // (HEAD's 0..1 range was the checkerboard), so stretch it for display.
  let patternValue1 = smoothstep(0.04, 0.32, scale1.y);
  let patternValue2 = smoothstep(0.04, 0.32, scale2.y);
  let combinedPattern = patternValue1 * 0.6 + patternValue2 * 0.4;
  let hue1 = 0.55 + patternValue1 * 0.1; // Cyan-ish
  let hue2 = 0.15 + patternValue2 * 0.1; // Orange-ish
  let color1 = hsv2rgb(hue1 * 6.0, 0.7, patternValue1);
  let color2 = hsv2rgb(hue2 * 6.0, 0.6, patternValue2);

  // Blend with source image
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let patternColor = color1 * 0.6 + color2 * 0.4;
  let finalColor = mix(sourceColor.rgb, patternColor, combinedPattern * 0.7 + 0.1);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
