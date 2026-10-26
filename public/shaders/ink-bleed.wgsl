// ═══════════════════════════════════════════════════════════════════════════════
//  Ink Bleed — Anisotropic Capillary Diffusion on Paper
//  Category: interactive-mouse
//  Features: mouse-driven, held-drag, spring-damper-pointer,
//            bounded-click-ripples, audio-reactive, per-band-fft,
//            anisotropic-diffusion, paper-fibre, chromatic-aberration,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23, 2026-10-26
//  Ideas: wet-edge bead (§12.2C); paper granulation (§12.2C)
//  A packing: raw ink in A.r and A.a; ACES on display only
// ═══════════════════════════════════════════════════════════════════════════════
//  BUG FIXED IN THIS PASS — filtered reads of a float32 texture. All five reads
//  of the ink field went through `non_filtering_sampler`:
//
//      textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r
//
//  `dataTextureC` is rgba32float and `float32-filterable` is only requested when
//  the adapter offers it (src/renderer/webgpu/device.ts), so binding a filtering
//  sampler to it is invalid wherever the feature is absent. All state reads now
//  use exact `textureLoad`. The depth pass-through was also using the filtering
//  sampler and is now on `non_filtering_sampler`.
//
//  Also: the shader had no audio (never touched plasmaBuffer), no click
//  response, and no tone mapping.
//
//  TWO NEW STRUCTURES
//
//    1. Anisotropic diffusion along paper fibres — the old spread was an
//       isotropic 4-neighbour box average, which is why the ink grew as round
//       blobs. Real paper has a fibre grain, and ink wicks ALONG the fibres far
//       faster than across them. The diffusion is now a tensor weighted by a
//       procedural fibre direction field, so blots elongate along the grain and
//       feather at their ends the way ink on paper actually does.
//
//    2. Per-band FFT wicking + spring-damped nib — the fibre angle and wicking
//       rate are modulated by the eight spectrum bins, and the brush position
//       comes from a spring-damped pointer in extraBuffer[133..136] whose
//       velocity widens the stroke, so fast strokes lay down thinner ink.
//       Clicks drop bounded ink splats through the ripple queue.
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=InkHue, y=SpreadSpeed, z=FadeSpeed, w=Density

// Helper for hue to rgb
fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
  var t_ = t;
  if(t_ < 0.0) { t_ += 1.0; }
  if(t_ > 1.0) { t_ -= 1.0; }
  if(t_ < 1.0/6.0) { return p + (q - p) * 6.0 * t_; }
  if(t_ < 1.0/2.0) { return q; }
  if(t_ < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t_) * 6.0; }
  return p;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  var r: f32;
  var g: f32;
  var b: f32;

  if(s == 0.0) {
    r = l;
    g = l;
    b = l;
  } else {
    var q: f32;
    if(l < 0.5) { q = l * (1.0 + s); } else { q = l + s - l * s; }
    var p = 2.0 * l - q;
    r = hue2rgb(p, q, h + 1.0/3.0);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1.0/3.0);
  }
  return vec3<f32>(r, g, b);
}

// Paper texture simulation
// Smooth procedural paper-fibre direction field (radians).
fn fibreField(uv: vec2<f32>, mids: f32) -> f32 {
  let a = sin(uv.y * 21.0 + uv.x * 7.0) * 0.9;
  let b = cos(uv.x * 17.0 - uv.y * 5.0) * 0.6;
  return a + b + mids * 0.4;
}

fn paperTexture(uv: vec2<f32>) -> f32 {
  let noise = fract(sin(dot(uv * 100.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  return 0.9 + 0.1 * noise;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Params
  let ink_hue = u.zoom_params.x;
  let spread_speed = u.zoom_params.y;
  let fade_speed = u.zoom_params.z;
  let density = u.zoom_params.w;

  var mouse = u.zoom_config.yz;
  let mouse_down = u.zoom_config.w;

  let time = u.config.x;
  let aspect = f32(dims.x) / f32(dims.y);
  let maxC = dims - vec2<i32>(1);

  // ── Audio ────────────────────────────────────────────────────────────────
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Spring-damped nib in extraBuffer[133..136] ───────────────────────────
  // Position in [133..134], velocity in [135..136]; invocation (0,0) writes.
  if (global_id.x == 0u && global_id.y == 0u) {
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (sm.x == 0.0 && sm.y == 0.0) { sm = mouse; }
    let dt = 0.016;
    let k = 1.0 - exp(-12.0 * dt);
    let next = sm + (mouse - sm) * k;
    var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    sv = mix(sv, (next - sm) / dt, 0.3);
    extraBuffer[133] = next.x;
    extraBuffer[134] = next.y;
    extraBuffer[135] = sv.x;
    extraBuffer[136] = sv.y;
  }
  let nib = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  let nibVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);

  // 1. Read previous ink state — exact load (see header: C is rgba32float).
  let prev_ink = textureLoad(dataTextureC, coord, 0).r;

  // 2. Lay down new ink under the nib. A fast stroke deposits less ink per
  //    pixel, as a real pen does.
  let d = length((uv - nib) * vec2<f32>(aspect, 1.0));
  let strokeSpeed = clamp(length(nibVel), 0.0, 4.0);
  let brush_size = 0.05 * (1.0 + strokeSpeed * 0.10);
  var new_ink_add = 0.0;
  if (mouse_down > 0.5 && d < brush_size) {
    new_ink_add = smoothstep(brush_size, 0.0, d) / (1.0 + strokeSpeed * 0.6);
  }

  // 2b. Bounded click splats.
  var splat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.0) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      splat += exp(-r * r * 900.0) * exp(-age * 2.2) * (0.5 + bass * 0.9);
    }
  }
  splat = min(splat, 1.0);

  // ── Structure 1: anisotropic diffusion along paper fibres ────────────────
  // Fibre direction is a smooth procedural field; ink wicks along it much
  // faster than across it, so blots elongate with the grain instead of
  // spreading as isotropic discs (the old (n+s+e+w)*0.25 box average).
  let fibreAngle = fibreField(uv, mids)
                 + plasmaBuffer[u32(clamp(uv.y * 8.0, 0.0, 7.999)) + 1u].x * 0.9;
  let along = vec2<f32>(cos(fibreAngle), sin(fibreAngle));
  let across = vec2<f32>(-along.y, along.x);

  let n = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0,  1), vec2<i32>(0), maxC), 0).r;
  let s = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), maxC), 0).r;
  let e = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1, 0), vec2<i32>(0), maxC), 0).r;
  let w = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), maxC), 0).r;

  // Project the 4-neighbourhood onto the fibre frame. Weights are the squared
  // direction cosines, so the stencil stays a partition of unity.
  let ax = along.x * along.x;
  let ay = along.y * along.y;
  let cx = across.x * across.x;
  let cy = across.y * across.y;
  // Wicking is ~4x faster along the grain than across it.
  let kAlong = 0.8;
  let kAcross = 0.2;
  let wE = kAlong * ax + kAcross * cx;
  let wW = wE;
  let wN = kAlong * ay + kAcross * cy;
  let wS = wN;
  let wSum = max(wE + wW + wN + wS, 1e-4);
  let average = (e * wE + w * wW + n * wN + s * wS) / wSum;

  // Treble loosens the sizing so ink runs faster on loud transients.
  let wickRate = spread_speed * 0.1 * (1.0 + treble * 0.6);
  var current_ink = mix(prev_ink, average, clamp(wickRate, 0.0, 0.9));
  current_ink = min(current_ink + new_ink_add + splat, 1.0);

  // ── Idea 1: wet-edge bead (§12.2C) ──────────────────────────────────
  // Pigment concentrates where the ink gradient is steep and the wash is
  // neither empty nor solid. Spread Speed still owns how fast it runs.
  let inkGrad = length(vec2<f32>(e - w, n - s));
  let wetEdge = clamp(inkGrad * 1.8, 0.0, 1.0) * current_ink * (1.0 - current_ink);
  current_ink = min(current_ink + wetEdge * spread_speed * 0.55, 1.0);

  // 4. Fade
  current_ink *= (1.0 - fade_speed * 0.01);
  if (current_ink < 0.001) { current_ink = 0.0; }

  // 5. Store state
  textureStore(dataTextureA, coord, vec4<f32>(current_ink, 0.0, 0.0, current_ink));

  // 6. Render with PHYSICAL MEDIA ALPHA
  let video_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let ink_color_rgb = hslToRgb(ink_hue, 0.8, 0.25);
  
  // Paper texture affects absorption (paper_tex computed with the granulation).

  // INK DENSITY → ALPHA MAPPING
  // Ink concentration determines opacity
  // - High ink density = thick layer = opaque (alpha ~ 0.9-1.0)
  // - Low ink density = thin wash = semi-transparent (alpha ~ 0.3-0.6)
  // - No ink = paper visible (alpha ~ 0.0)
  
  // ── Idea 2: paper granulation (§12.2C) ─────────────────────────────
  // Thin, watery washes lose pigment on the peaks of the existing paper hash
  // and keep it in the pits. Thick ink (high density, high coverage) stays smooth.
  // The stored field above is the ungranulated diffusion state.
  let paper_tex = paperTexture(uv);
  let grainN = clamp((paper_tex - 0.9) / 0.1, 0.0, 1.0);
  let wash = (1.0 - smoothstep(0.35, 0.85, current_ink)) * (1.0 - density);
  let granInk = current_ink * (1.0 - wash * grainN * 0.75);
  let ink_thickness = max(granInk, 0.0) * density; // 0-1 range
  
  // Dilution factor: more water (lower density) = more transparent
  let dilution = 1.0 - density * 0.5;
  
  // Base alpha from ink thickness
  var ink_alpha = ink_thickness * (0.9 - dilution * 0.4) + 0.1;
  
  // Paper absorption: ink soaks in differently based on texture
  // Rough paper areas absorb more ink, creating variations
  let absorption = mix(0.7, 1.0, paper_tex);
  ink_alpha *= absorption;
  
  // Feather edges for bleeding effect
  let feather = smoothstep(0.0, 0.3, ink_thickness);
  ink_alpha *= feather;
  
  // Final RGBA output
  // RGB = ink color blended with video
  // A = ink coverage/thickness
  var final_rgb = mix(video_color, ink_color_rgb * video_color, ink_thickness);
  
  // Add paper texture visibility in thin areas
  let paper_color = vec3<f32>(0.98, 0.97, 0.95) * paper_tex;
  final_rgb = mix(paper_color, final_rgb, ink_alpha);
  
  final_rgb += vec3<f32>(0.25, 0.12, 0.35) * splat * 0.6;
  final_rgb = mix(final_rgb, final_rgb * vec3<f32>(0.55, 0.48, 0.5), clamp(wetEdge * 3.0, 0.0, 1.0));
  final_rgb = acesFilm(final_rgb);
  textureStore(writeTexture, coord, vec4<f32>(final_rgb, clamp(ink_alpha, 0.0, 1.0)));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
