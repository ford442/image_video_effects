// ═══════════════════════════════════════════════════════════════════
//  Fractal Kaleidoscope
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware,
//            facet-seams, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) nested mirror chambers (Detail = recursive fold levels);
//         2) reflection loss (reflectance^bounces dimming + cool tint per bounce);
//         3) integer wedge crossfade (floor/ceil segment counts, no atan2 tear)
//  A packing: ACES display RGBA (alpha = mirror-path transmission)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rotate2D(uv: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Wedge fold about the origin (p is already centred). Same fold as HEAD's
// kaleidoscopeFractal; .z = number of mirror reflections that map this
// wedge onto the fundamental half-wedge [0, segAngle/2] (shortest path).
fn wedgeFold(p: vec2<f32>, segments: f32) -> vec3<f32> {
  let radius = length(p);
  let a = atan2(p.y, p.x);
  let segmentAngle = 6.28318530718 / max(segments, 1.0);
  let folded = abs(fract(a / segmentAngle + 0.5) - 0.5) * segmentAngle;
  // Idea 2: reflection count. Half-wedge index going CCW from the
  // fundamental domain; the shorter way round is the real bounce count.
  let halfSeg = segmentAngle * 0.5;
  let aw = a + select(0.0, 6.28318530718, a < 0.0);
  let idx = floor(aw / halfSeg);
  let bounces = max(min(idx, 2.0 * segments - idx), 0.0);
  return vec3<f32>(vec2<f32>(cos(folded), sin(folded)) * radius, bounces);
}

struct Chamber {
  uv: vec2<f32>,      // final warped sample uv
  foldUv: vec2<f32>,  // first (screen-space) fold, used for feedback
  bounces: f32,       // accumulated mirror reflections
  seam: f32,          // facet seam strength for this integer count
};

// One full kaleidoscope evaluation for an INTEGER segment count.
fn chamberChain(uv: vec2<f32>, pivot: vec2<f32>, segments: f32, iterations: i32,
                foldLevels: i32, time: f32, speed: f32, scaleP: f32, depth: f32) -> Chamber {
  var ch: Chamber;
  let f0 = wedgeFold(uv - pivot, segments);
  var coord = f0.xy + 0.5;
  ch.foldUv = coord;
  var bounces = f0.z;
  // Idea 1: nested chambers use half the mirrors (integer, >= 2).
  let nestedSegs = max(2.0, floor(segments * 0.5));
  for (var i: i32 = 0; i < 5; i = i + 1) {
    if (i >= iterations) { break; }
    let level = f32(i);
    let zoomAmt = (1.0 + sin(time * (0.25 + speed) + level * 1.5) * mix(0.12, 0.38, scaleP));
    coord = rotate2D(coord - 0.5, time * 0.1 * (1.0 + level * 0.5)) * zoomAmt + 0.5;
    coord += vec2<f32>(sin(time * 0.5 + level + depth * 2.0), cos(time * 0.5 + level + depth * 2.0)) * 0.02;
    // Idea 1: nested mirror chambers — refold the polar wedge inside this
    // pass around a sub-chamber centre pushed out along the wedge, so each
    // facet holds its own smaller kaleidoscope (fold, translate, fold).
    if (i < foldLevels) {
      let chamberShift = vec2<f32>(0.16 / (1.0 + level), 0.0);
      let g = wedgeFold(coord - 0.5 - chamberShift, nestedSegs);
      coord = g.xy + 0.5 + chamberShift;
      bounces += g.z * 0.5;
    }
  }
  ch.uv = clamp(coord, vec2<f32>(0.0), vec2<f32>(1.0));
  ch.bounces = bounces;
  let folded = abs(fract(atan2(uv.y - pivot.y, uv.x - pivot.x) / 6.28318530718 * segments) - 0.5);
  let sb = 1.0 - folded * 2.0;
  ch.seam = sb * sb * sb;
  return ch;
}

fn sampleSplit(finalUV: vec2<f32>, chromaticOffset: f32) -> vec3<f32> {
  let colorR = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(chromaticOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(chromaticOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec3<f32>(colorR, colorG, colorB);
}

// Idea 2: light lost per mirror bounce, slightly cool (silvered glass
// reflects blue a touch better than red).
fn reflectionLoss(bounces: f32) -> vec3<f32> {
  return pow(vec3<f32>(0.942, 0.95, 0.958), vec3<f32>(bounces));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let held = f32(u.zoom_config.w > 0.5);
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scaleP = u.zoom_params.z;
  let detail = u.zoom_params.w;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let segments = mix(4.0, 14.0, intensity) + sin(time * mix(0.12, 0.55, speed)) * 1.5;
  let pivot = mix(vec2<f32>(0.5), mouse, 0.35 + held * 0.4);
  let iterations = 2 + i32(detail * 3.0 + depth);
  // Idea 1: Detail also picks how many passes refold (1..3).
  let foldLevels = 1 + i32(detail * 2.0);

  // Idea 3: integer wedge crossfade — evaluate the two neighbouring integer
  // mirror counts and blend, so the animated count never tears at atan2's cut.
  let segLo = max(floor(segments), 2.0);
  let segHi = segLo + 1.0;
  let segT = smoothstep(0.0, 1.0, clamp(segments - segLo, 0.0, 1.0));
  let chLo = chamberChain(uv, pivot, segLo, iterations, foldLevels, time, speed, scaleP, depth);
  let chHi = chamberChain(uv, pivot, segHi, iterations, foldLevels, time, speed, scaleP, depth);

  let chromaticOffset = 0.003 * (1.0 - depth) * (0.6 + intensity);
  // Idea 2: each branch carries its own reflection loss before blending.
  let transLo = reflectionLoss(chLo.bounces);
  let transHi = reflectionLoss(chHi.bounces);
  let colLo = sampleSplit(chLo.uv, chromaticOffset) * transLo;
  let colHi = sampleSplit(chHi.uv, chromaticOffset) * transHi;
  let transmission = mix(transLo, transHi, segT);
  var finalColor = mix(colLo, colHi, segT) * (0.8 + depth * 0.4);

  let seam = mix(chLo.seam, chHi.seam, segT);
  let conveyor = smoothstep(0.09, 0.0, abs(fract(length(uv - pivot) * 8.0 - time * 1.8 - bass * 0.6) - 0.5));
  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 64.0) * (1.0 - age / 1.5));
    }
  }
  let folded = abs(fract(atan2(uv.y - pivot.y, uv.x - pivot.x) / 6.28318530718 * mix(segLo, segHi, segT)) - 0.5);
  let slick = hsv2rgb(vec3<f32>(fract(folded * 2.0 + time * 0.12 + mids * 0.25), 0.75, 0.95));
  finalColor = mix(finalColor, finalColor * slick * 1.3, 0.28 + treble * 0.2);
  finalColor += slick * (seam * 0.22 + conveyor * 0.26 + click * 0.55);

  // ACES on display RGB (negatives clamped first); feedback mixes display
  // to display, read at the folded uv so trails stay mirror-symmetric.
  let display = acesToneMap(max(finalColor, vec3<f32>(0.0)));
  let foldUv = select(chLo.foldUv, chHi.foldUv, segT > 0.5);
  let fbPix = clamp(vec2<i32>(foldUv * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, fbPix, 0);
  // Semantic alpha: how much light survives the mirror path (+ seam glow).
  let trans = dot(transmission, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(0.35 + trans * 0.6 + seam * 0.05 + click * 0.12, 0.0, 1.0);
  let outCol = vec4<f32>(mix(display, prev.rgb * 0.86, 0.26), mix(alpha, prev.a * 0.86, 0.26));
  textureStore(writeTexture, pixel, outCol);
  textureStore(dataTextureA, pixel, outCol);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + seam * 0.08 + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
