// ═══════════════════════════════════════════════════════════════════
//  Chromatic Mosaic Projector
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-09, 2026-11-09
//  Ideas: cell-boundary diffraction fringe (now on the true border); wavelength step on the projection vector;
//         lenslet lateral colour; lenslet dome glint; unlensed grout window
//  A packing: pre-ACES display RGBA trail (C is color history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ────────────────────────────────────────────────
fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── Color & tone ────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ── Voronoi mosaic ──────────────────────────────────────────────
// d1   = distance to the nearest SEED; edge = exact distance to the cell BORDER (bisector of the two nearest
// seeds); lc = seed→pixel vector (the lenslet-local coordinate). All in cell units.
struct Vor {
  d1: f32,
  id: vec2<f32>,
  edge: f32,
  lc: vec2<f32>,
};

fn voronoi(uv: vec2<f32>, cellSize: f32, distort: f32, time: f32) -> Vor {
  let scaled = uv * cellSize;
  let cellId = floor(scaled);
  let fracPos = fract(scaled);
  var d1 = 8.0;
  var d2 = 8.0;
  var p1 = vec2<f32>(0.0);              // pixel→seed vectors of the nearest / second-nearest seed
  var p2 = vec2<f32>(1.0, 0.0);
  var nearCell = cellId;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = cellId + vec2<f32>(f32(x), f32(y));
      let h = hash22(neighbor);
      let anim = vec2<f32>(
        sin(time * 0.8 + h.x * TAU) * distort,
        cos(time * 0.6 + h.y * TAU) * distort
      );
      let point = h + anim + vec2<f32>(f32(x), f32(y)) - fracPos;
      let d = length(point);
      let closer = d < d1;
      let between = (!closer) && (d < d2);
      p2 = select(select(p2, point, between), p1, closer);
      d2 = select(select(d2, d, between), d1, closer);
      p1 = select(p1, point, closer);
      nearCell = select(nearCell, neighbor, closer);
      d1 = select(d1, d, closer);
    }
  }
  // RESCUE R1: HEAD returned only distance-to-seed and used it for every "edge" term (edgeFade, edgeLayer,
  // fringe) → a dark dot at each seed and rings around it, never a border. Exact bisector distance:
  let sep = p2 - p1;
  let edge = max(dot(0.5 * (p1 + p2), sep / max(length(sep), 1e-4)), 0.0);
  return Vor(d1, nearCell, edge, -p1);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  // Review fix 1: C is another shader's leftover on a late start / direct switch. Out-of-range or non-finite
  // history is invalid → zero (a NaN fails every comparison); in-range history decays in ~12 frames.
  let prevRaw = textureLoad(dataTextureC, pixel, 0);
  let prevOk = all(prevRaw.rgb >= vec3<f32>(-0.01)) && all(prevRaw.rgb <= vec3<f32>(8.0))
            && prevRaw.a >= -0.01 && prevRaw.a <= 1.01;
  let prev = select(vec4<f32>(0.0),
                    vec4<f32>(max(prevRaw.rgb, vec3<f32>(0.0)), clamp(prevRaw.a, 0.0, 1.0)),
                    prevOk);

  // Parameters
  let cellSizeBase = mix(8.0, 80.0, u.zoom_params.x);
  // RESCUE R2: HEAD scaled the lattice by (1 + bass·0.25), which re-hashes every cell (colour temperature,
  // chroma gain, projection rotation): bass 0.4 changed 21% of pixels by >0.1 (0.3% without the term).
  // Bass now jostles the seeds instead (bounded, no relabelling) — same "bass pulses the mosaic" role.
  let cellSize = cellSizeBase;
  let chromaticStrength = u.zoom_params.y * 0.08 * (1.0 + mids * 2.0);
  // Review fix 2: the 3×3 Voronoi search only finds the true nearest seed up to ≈0.5–0.6 seed jostle (above that
  // F1/F2, the bisector edge, grout and edgeFade are wrong). Linear up to 0.45 (slider 1 with no audio = 0.496,
  // as before), then tanh-compressed to a 0.55 ceiling so audio still moves it but the search stays valid
  // (3×3 vs 7×7 mismatch ≤3.6% at the extreme, was 20–44% with an uncapped 1.0–1.35).
  let distortRaw = u.zoom_params.z * 0.5 * (1.0 + treble) * (1.0 + bass * 0.35);
  let voronoiDistort = min(distortRaw, 0.45) + 0.10 * tanh(max(distortRaw - 0.45, 0.0) / 0.10);
  let projectionAngle = (u.zoom_params.w - 0.5) * 1.5;

  // Two smooth mosaic conveyors cross-feed the animated Voronoi cells.
  let conveyor = vec2<f32>(sin(time * 0.9), cos(time * 0.73)) * (0.01 + u.zoom_params.z * 0.025);
  let conveyorUV = uv01 + conveyor;
  let voro = voronoi(conveyorUV, cellSize, voronoiDistort, time);
  let cellHash = hash21(voro.id);
  let cellCenter = (voro.id + 0.5) / cellSize - conveyor;

  // Mouse gravity warp
  let toMouse = (mouse - uv01) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let gravity = 0.25;
  let warp = select(vec2<f32>(0.0), normalize(toMouse) * gravity / (1.0 + mouseDist * 3.0), mouseDist > 0.0001);
  let warpedUV = uv01 + warp * (0.025 + held * 0.045);

  var clickWave = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.35) {
      clickWave = max(clickWave,
        // RESCUE R3: aspect-corrected distance (HEAD's ring was an ellipse on non-square canvases)
        exp(-abs(length((uv01 - rp.xy) * vec2<f32>(aspect, 1.0)) - age * 0.5) * 76.0) * (1.0 - age / 1.35));
    }
  }

  // Projection direction with per-cell rotation
  let dirVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dirVec);
  var dir = select(vec2<f32>(1.0, 0.0), normalize(dirVec), dist > 0.0001);
  let angleRot = projectionAngle + cellHash * 0.6;
  let ca = cos(angleRot);
  let sa = sin(angleRot);
  dir = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

  // Chromatic channel offsets
  let cellChroma = chromaticStrength * (0.5 + cellHash);
  let baseOffset = dir * dist * 0.1;
  let rOff = baseOffset + dir * cellChroma * (1.0 + bass * 0.6);
  let gOff = baseOffset + dir * cellChroma * 0.35;
  let bOff = baseOffset - dir * cellChroma * 0.8;
  // Wavelength step: red and blue leave the cell at different quantized
  // distances along the existing projection vector.
  let stepLen = max(cellChroma, 0.0015);
  let rOffStepped = rOff + dir * (ceil(dist / stepLen) * stepLen * 0.22);
  let bOffStepped = bOff - dir * (floor(dist / stepLen) * stepLen * 0.18);

  // ── Idea 3: lenslet lateral colour. Transverse chromatic aberration is radial about each lenslet's own
  // axis (red image slightly larger than blue): R / B are displaced ± along the seed→pixel vector, scaled
  // by the existing per-cell chromatic strength; G stays on the axis.
  let lcUV = voro.lc / cellSize;                               // seed→pixel, uv units
  let latOff = lcUV * (cellChroma * cellSize * 1.3);
  let src = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + rOffStepped + latOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + bOffStepped - latOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Mosaic edge shaping + radial falloff (now on the true border distance — RESCUE R1)
  let edgeFade = smoothstep(0.0, 0.18, voro.edge);
  color = color * (0.65 + 0.35 * edgeFade);
  // ── Idea 5: unlensed grout window. The gap between two lenslets is a plain window: in the border band the
  // source passes undisplaced (`src`, already fetched for alpha) instead of the old dark seed dots.
  let groutMask = 1.0 - smoothstep(0.0, 0.07, voro.edge);
  color = mix(color, src.rgb * 0.9, groutMask * 0.65);
  // Diffraction fringe on the existing cell boundary (idea 2026-10-09, now measured from the border).
  // Review fix 3: HEAD's fixed 78 rad/cell gave a ~1 px period at 576 px and ~2 px at 1024 px (aliased
  // stripes), and nothing resolvable at 192 px. Period is now ≥ ~3.5 px (78 only on big cells) and the fringe
  // fades out as the cell's pixel size drops below ~12 px.
  let cellPx = min(res.x, res.y) / cellSize;
  let fringeFreq = clamp(TAU * cellPx / 3.5, 20.0, 78.0);
  let fringeFade = smoothstep(5.0, 12.0, cellPx);
  let fringeEnv = smoothstep(0.04, 0.10, voro.edge) * (1.0 - smoothstep(0.16, 0.30, voro.edge)) * fringeFade;
  let fringePhase = voro.edge * fringeFreq;
  color.r = color.r + sin(fringePhase) * fringeEnv * cellChroma * 5.5;
  color.g = color.g + sin(fringePhase + 1.15) * fringeEnv * cellChroma * 5.5;
  color.b = color.b + sin(fringePhase + 2.35) * fringeEnv * cellChroma * 5.5;
  color = max(color, vec3<f32>(0.0));                         // floor: nothing negative into the trail / ACES
  let beltRunner = pow(0.5 + 0.5 * sin((voro.id.x + voro.id.y) * 0.7 - time * 7.0), 10.0);
  color += vec3<f32>(0.12, 0.45, 1.0) * beltRunner * edgeFade * (0.2 + treble * 0.3);
  let falloff = 1.0 / (1.0 + dist * 2.5);
  color = color * falloff;

  // Audio brightness + dynamic color temperature per cell
  color = color * (1.0 + bass * 0.25);
  let temp = mix(3500.0, 7500.0, clamp(cellHash + mids * 0.3, 0.0, 1.0));
  let tint = blackbodyRGB(temp);
  color = mix(color, color * tint * 1.5, 0.35);
  // ── Idea 4: lenslet dome glint. Each lenslet is a tiny dome and the projector lamp sits on the cursor
  // axis: the dome normal tilts with the seed→pixel vector, so the lamp's highlight lands where
  // lc ≈ −dir·0.22 (toward the lamp, against the projection direction) — one specular dot per cell, dimmed by
  // the same lamp falloff, kept off the grout (edgeFade) and brightened by treble. Static (no strobe).
  let glintD = voro.lc + dir * 0.22;
  let glint = exp(-dot(glintD, glintD) / 0.016) * edgeFade;
  color += vec3<f32>(1.0, 0.96, 0.9) * glint * (0.6 + treble * 0.8) * falloff;
  let blastPalette = 0.5 + 0.5 * cos(TAU * (vec3<f32>(cellHash + time * 0.08)
                                        + vec3<f32>(0.0, 0.33, 0.67)));
  color += blastPalette * clickWave * (0.28 + chromaticStrength * 1.8);

  // Temporal feedback trail
  let decay = 0.96 - u.zoom_params.w * 0.03;
  let trail = mix(prev.rgb * decay, color, 0.22 + treble * 0.08);

  // ACES tone map + IGN dither
  color = acesToneMap(trail * 1.15);
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // ── Advanced alpha compositor (Phase B) ────────────────────────
  // Layered alpha: depth layering + edge preservation + luminance key +
  // displacement/chromatic intensity, blended with source alpha and bloom.
  let lum = luma(color);
  let lumaKey = smoothstep(0.06, 0.30, lum);
  let depthLayer = mix(0.25, 1.0, depth);
  let edgeLayer = smoothstep(0.0, 0.22, voro.edge);
  let warpMag = length(warp);
  let chromaMag = cellChroma * (1.0 + bass * 0.6);
  let intensityAlpha = clamp(warpMag * 14.0 + chromaMag * 8.0, 0.0, 1.0);
  let baseAlpha = mix(lumaKey, depthLayer, 0.5);
  let cellAlpha = baseAlpha * edgeLayer * (0.4 + 0.6 * intensityAlpha);
  let bloomWeight = pow(max(0.0, lum - 0.55), 2.0) * 2.5;
  let alphaCell = clamp(src.a * 0.5 + cellAlpha * 0.5 + bloomWeight * 0.35, 0.1, 1.0);
  let alpha = mix(alphaCell, clamp(src.a, 0.1, 1.0), groutMask * 0.65);   // grout window passes the source coverage

  // Accumulative alpha trail for temporal consistency in the 3-slot chain
  let feedbackAlpha = clamp(mix(prev.a * decay, alpha, 0.25 + treble * 0.08), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(trail, feedbackAlpha));

  textureStore(writeTexture, pixel, vec4<f32>(color * feedbackAlpha, feedbackAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
