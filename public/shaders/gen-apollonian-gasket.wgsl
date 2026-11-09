// ═══════════════════════════════════════════════════════════════════
//  Apollonian Gasket
//  Category: generative
//  Features: procedural, fractal, apollonian-gasket, circle-inversion,
//            descartes-theorem, audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-11, 2026-11-09
//  Ideas: packing rims on seed circles; curvature tint from last inverted k; generation stipple; tangent kisses; interior wash; soddy spark;
//         conformal hairlines (distance / accumulated inversion derivative = constant-width line on every nested copy);
//         generation-delayed pulse (a beat of light cascades inward through the inversion depth)
//  A packing: linear RGB + alpha, pre-ACES (C read as colour); texel (0,0) = (pointer glide.xy, 7, fract(time)), skipped by the feedback mix
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn circle_inv(p: vec2<f32>, c: vec2<f32>, r: f32) -> vec2<f32> {
  let d = p - c;
  let l2 = dot(d, d) + 1e-8;
  return c + d * (r * r) / l2;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x * 2.6;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  // Rescue R1 — HEAD's spring state lived in extraBuffer[133..138]; the host re-uploads that
  // buffer as zero every frame, so the spring never persisted and the pointer lens was the raw
  // cursor (plus a same-dispatch write race). The eased pointer now lives in texel (0,0) of A,
  // read back through an exact C load: every pixel computes the same glide, only (0,0) stores
  // it, and that texel skips the temporal-feedback read. Rate 8 = HEAD's omega.
  let isWriter = gid.x == 0u && gid.y == 0u;
  let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let hasGlide = abs(glideState.z - 7.0) < 0.01;
  let frameT = fract(u.config.x);
  let glideDt = clamp(frameT - glideState.w + select(0.0, 1.0, frameT < glideState.w), 0.0, 0.1);
  let glideK = 1.0 - exp(-8.0 * glideDt);
  let mouse = select(rawMouse, glideState.xy + (rawMouse - glideState.xy) * glideK, hasGlide);
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(1.0, 1.5, mouseDown);

  let recursion = i32(mix(3.0, 10.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let invIntensity = u.zoom_params.y;
  let circleSize = mix(0.5, 2.0, u.zoom_params.z);
  let rainbow = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;

  // Descartes theorem: k4 = k1+k2+k3 ± 2*sqrt(k1k2+k2k3+k3k1)
  // Curvature k = 1/r. For r=0.5, k=2.0; for r=0.155, k≈6.45; for r=0.3, k≈3.33
  let circles = array<vec3<f32>, 5>(
    vec3<f32>(0.5, 0.0, 0.5),    // center=(0.5,0), r=0.5, k=2.0
    vec3<f32>(-0.5, 0.0, 0.5),   // center=(-0.5,0), r=0.5, k=2.0
    vec3<f32>(0.0, 0.866, 0.5),  // center=(0,0.866), r=0.5, k=2.0
    vec3<f32>(0.0, 0.289, 0.155),// center=(0,0.289), r=0.155, k≈6.45
    vec3<f32>(0.0, -0.5, 0.3)    // center=(0,-0.5), r=0.3, k≈3.33
  );

  var q = p;
  var invCount = 0.0;
  var lastK = 2.0;
  let spin = mat2x2<f32>(cos(time * 0.35 + mids), sin(time * 0.35), -sin(time * 0.35), cos(time * 0.35 + mids));
  q = spin * q;

  // Idea 7 bookkeeping: |dq/dp|, the accumulated derivative of the whole inversion chain. The
  // spin matrix is a complex multiplication, i.e. a similarity with scale sqrt(c'^2 + s^2); each
  // circle inversion scales distances by r^2 / |q - c|^2.
  let spinC = cos(time * 0.35 + mids);
  let spinS = sin(time * 0.35);
  var dScale = max(sqrt(spinC * spinC + spinS * spinS), 0.05);

  for (var i = 0; i < recursion; i = i + 1) {
    var inverted = false;
    for (var j = 0; j < 5; j = j + 1) {
      let c = circles[j].xy;
      let r = circles[j].z;
      if (distance(q, c) < r) {
        let dInv = q - c;
        dScale = min(dScale * (r * r / (dot(dInv, dInv) + 1e-8)), 1e12);
        q = circle_inv(q, c, r);
        invCount = invCount + 1.0;
        lastK = 1.0 / max(r, 0.05);
        inverted = true;
        break;
      }
    }
    if (!inverted) { break; }
  }

  let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;
  let mr = (0.18 + invIntensity * 0.35) * held;
  if (distance(q, mp) < mr * 1.4) {
    let dInvM = q - mp;
    dScale = min(dScale * (mr * mr / (dot(dInvM, dInvM) + 1e-8)), 1e12);
    q = circle_inv(q, mp, mr);
    invCount = invCount + 1.0;
  }

  var minDist = 1e9;
  for (var j = 0; j < 5; j = j + 1) {
    let d = abs(distance(q, circles[j].xy) - circles[j].z);
    minDist = min(minDist, d);
  }

  let density = exp(-minDist * 15.0);

  // Idea 7 — conformal hairlines. `minDist` lives in the inverted plane, so its width changes
  // with the local inversion scale. Dividing by the accumulated derivative gives the distance
  // to the true preimage of the nearest seed circle in the p plane: a line of constant screen
  // width (1.2 px) on every nested copy of every circle, at every generation. It fades where the
  // derivative is so large that the copies pack tighter than a pixel (it would only be a fill).
  let pxP = 3.0 / (circleSize * max(f32(dims.y), 1.0));
  let hairDist = minDist / dScale;
  let hairFade = 1.0 - smoothstep(150.0, 4.0e3, dScale);
  let hair = (1.0 - smoothstep(0.0, 1.2 * pxP, hairDist)) * hairFade;

  // Idea 8 — generation-delayed pulse. Generations are built one inversion at a time, so light
  // arrives one generation at a time: each deeper copy flashes a beat after the previous one
  // and a pulse cascades inward through the nesting. Bass raises the amplitude, never the phase.
  let genPulse = pow(0.5 + 0.5 * sin(u.config.x * 1.6 - invCount * 0.9), 5.0) * (0.6 + bass * 0.8);

  // Idea 1 — packing rims on the five seed circles (pre-inversion plane)
  var packRim = 0.0;
  for (var j = 0; j < 5; j = j + 1) {
    packRim += exp(-abs(distance(p, circles[j].xy) - circles[j].z) * 72.0);
  }
  // Interior wash — faint glass inside each seed circle, stronger in the larger ones.
  var interior = 0.0;
  var smallR = 1e9;
  var smallC = vec2<f32>(0.0);
  for (var j = 0; j < 5; j = j + 1) {
    let inside = circles[j].z - distance(p, circles[j].xy);
    interior += smoothstep(0.0, 0.05, inside) * (0.22 / max(circles[j].z, 0.15));
    if (circles[j].z < smallR) {
      smallR = circles[j].z;
      smallC = circles[j].xy;
    }
  }

  // Idea 2 — Descartes curvature tint from last inverted k
  let hue = fract(invCount * 0.14 + lastK * 0.08 + length(q) * 0.3 + time * 0.12 + treble * 0.2);
  let sat = 0.55 + density * 0.45 + mids * 0.15;
  let val = (0.18 + density * 0.85) * (1.0 + 0.3 * genPulse);

  var color = vec3<f32>(
    val * (0.5 + sat * cos(hue * 6.283) * 0.5),
    val * (0.5 + sat * cos((hue - 0.33) * 6.283) * 0.5),
    val * (0.5 + sat * cos((hue - 0.66) * 6.283) * 0.5)
  );
  // Idea 3 — generation stipple: deeper inversions draw finer rings
  let ringFreq = 18.0 * (1.0 + invCount * 0.85);
  let ring = abs(fract(minDist * ringFreq + time * 2.0) - 0.5);
  color += vec3<f32>(1.0, 0.2, 0.85) * (1.0 - smoothstep(0.0, 0.08, ring)) * 0.35;
  color += vec3<f32>(0.92, 0.88, 0.72) * clamp(packRim, 0.0, 1.0) * 0.32;
  color += vec3<f32>(0.35, 0.5, 0.7) * clamp(interior, 0.0, 1.0) * 0.28;
  // Soddy spark — bright center of the smallest seed circle.
  color += vec3<f32>(1.0, 0.96, 0.82) * exp(-dot(p - smallC, p - smallC) / max(smallR * smallR * 0.08, 1e-4)) * 0.45;
  // Idea 4 — tangent kisses where two seed circles nearly touch
  var kisses = 0.0;
  for (var j = 0; j < 5; j = j + 1) {
    for (var k = j + 1; k < 5; k = k + 1) {
      let gap = abs(distance(circles[j].xy, circles[k].xy) - (circles[j].z + circles[k].z));
      let dir = circles[k].xy - circles[j].xy;
      let contact = circles[j].xy + dir / max(length(dir), 1e-4) * circles[j].z;
      let near = exp(-dot(p - contact, p - contact) * 220.0);
      kisses += near * exp(-gap * 28.0);
    }
  }
  color += vec3<f32>(1.0, 0.95, 0.75) * clamp(kisses, 0.0, 1.2) * 0.7;
  // Idea 7 (cont.): the hairline, brightest on the generation the pulse is passing through (Idea 8).
  color += vec3<f32>(1.0, 0.93, 0.78) * hair * (0.55 + 0.9 * genPulse);

  let ca = smoothstep(0.0, 0.4, density) * rainbow;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.2),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.1)
  );

  let alpha = max(density * clamp(invCount / 8.0, 0.0, 1.0) * (0.7 + bass * 0.3), hair * 0.6);
  let depth = clamp(1.0 - minDist * 2.0, 0.0, 1.0);

  // Temporal feedback
  let hist = textureLoad(dataTextureC, coord, 0).rgb;
  // (texel (0,0) holds the pointer glide, not colour: it skips the feedback mix)
  color = mix(color, hist * 0.94, 0.05 * select(1.0, 0.0, isWriter));

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // Write temporal feedback before ACES so next frame reads untonemapped color
  textureStore(dataTextureA, coord, select(vec4<f32>(color, alpha), vec4<f32>(mouse, 7.0, frameT), isWriter));

  // Single ACES tonemap
  color = acesToneMap(color * 2.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
