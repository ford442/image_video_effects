// ═══════════════════════════════════════════════════════════════════
//  Chromatic Crawler — Upgraded with Alpha-Channel Translucency
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal-feedback, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: cell membranes tinted by the neighbour's wavelength; trails stream behind the crawl; cursor joins the crawl
//  A packing: linear pre-ACES display RGB (≥0) + coverage alpha; C read as colour
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ Math Snippets ═══
fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var p3 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.9))
  );
  p3 = fract(sin(p3) * 43758.5453);
  return p3;
}

fn hash1(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

struct VoronoiCells {
  region: vec2<f32>,     // HEAD's region key (cell id + seed offset) — drives flash phase
  cellId: vec2<f32>,     // nearest seed's cell
  neighId: vec2<f32>,    // second-nearest seed's cell (Idea 1)
  cellUV: vec2<f32>,     // nearest seed position in uv
  edge: f32,             // F2 - F1 in cell units (Idea 1)
  grid: vec2<f32>,
};

// Seeds wander smoothly inside their cells. HEAD hashed continuous time
// (hash3(id, time*0.5)), which re-rolled every seed every frame → per-frame noise.
fn voronoiRegions(uv: vec2<f32>, time: f32, regionSize: f32) -> VoronoiCells {
  let grid = vec2<f32>(10.0 + regionSize * 20.0, 8.0 + regionSize * 15.0);
  let id = floor(uv * grid);
  let fuv = fract(uv * grid);
  var minDist = 100.0;
  var secDist = 100.0;
  var minPoint = vec2<f32>(0.0);
  var minId = id;
  var secId = id;
  var minSeed = vec2<f32>(0.5);
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let pointId = id + neighbor;
      let rp = hash3(vec3<f32>(pointId.x, pointId.y, 0.0));
      let point = neighbor + 0.5 + 0.45 * sin(time * 0.5 + rp.xy * 6.28318);
      let dist = length(point - fuv);
      if (dist < minDist) {
        secDist = minDist;
        secId = minId;
        minDist = dist;
        minId = pointId;
        minSeed = point;
        minPoint = pointId + point / max(grid, vec2<f32>(0.0001));
      } else if (dist < secDist) {
        secDist = dist;
        secId = pointId;
      }
    }
  }
  var cells: VoronoiCells;
  cells.region = minPoint;
  cells.cellId = minId;
  cells.neighId = secId;
  cells.cellUV = (id + minSeed) / max(grid, vec2<f32>(0.0001));
  cells.edge = secDist - minDist;
  cells.grid = grid;
  return cells;
}

// Idea 3: Cursor joins the crawl — the pointer is a 4th crawl centre. Its term has
// no +0.5 bias, so away from the cursor the field is exactly HEAD's.
fn createCrawlingRegions(uv: vec2<f32>, time: f32, crawlSpeed: f32, mouse: vec2<f32>, mouseHeld: f32) -> vec2<f32> {
  let t = time * crawlSpeed;
  let center1 = vec2<f32>(0.5 + sin(t * 0.3) * 0.4, 0.5 + cos(t * 0.2) * 0.4);
  let center2 = vec2<f32>(0.5 + cos(t * 0.4) * 0.3, 0.5 + sin(t * 0.5) * 0.3);
  let center3 = vec2<f32>(0.5 + sin(t * 0.6) * 0.35, 0.5 + cos(t * 0.7) * 0.35);
  let d1 = length(uv - center1);
  let d2 = length(uv - center2);
  let d3 = length(uv - center3);
  let influence1 = smoothstep(0.3, 0.1, d1) * sin(t * 10.0 + uv.x * 20.0) * 0.5 + 0.5;
  let influence2 = smoothstep(0.25, 0.05, d2) * cos(t * 8.0 + uv.y * 15.0) * 0.5 + 0.5;
  let influence3 = smoothstep(0.2, 0.08, d3) * sin(t * 12.0 + (uv.x + uv.y) * 10.0) * 0.5 + 0.5;
  let d4 = length(uv - mouse);
  // Radial frequency matches HEAD's centres (×20): at ×40 the crawl Jacobian hit ~32×,
  // shrinking cells to ~2 px — a twinkling noise disk pinned to the default (0.5,0.5) pointer.
  let influence4 = smoothstep(0.22, 0.04, d4) * sin(t * 9.0 + d4 * 20.0) * (0.5 + 0.5 * mouseHeld);
  let totalInfluence = influence1 + influence2 + influence3 + influence4;
  let crawlOffset = vec2<f32>(
    sin(totalInfluence * 20.0 + t * 5.0) * 0.08,
    cos(totalInfluence * 15.0 + t * 3.0) * 0.08
  );
  return uv + crawlOffset;
}

fn hueRotate(color: vec3<f32>, angle: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosA = cos(angle);
  let sinA = sin(angle);
  return color * cosA + cross(k, color) * sinA + k * dot(k, color) * (1.0 - cosA);
}

// ACES filmic fit (display only)
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
  let m1 = mat3x3<f32>(
    0.59719, 0.07600, 0.02840,
    0.35458, 0.90834, 0.13383,
    0.04823, 0.01566, 0.83777
  );
  let m2 = mat3x3<f32>(
    1.60475, -0.10208, -0.00327,
    -0.53108,  1.10813, -0.07276,
    -0.07367, -0.00605,  1.07602
  );
  let v = m1 * color;
  let a = v * (v + 0.0245786) - 0.000090537;
  let b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth depth blending curve for compositing
fn depthBlend(depth: f32, intensity: f32) -> f32 {
  let near = smoothstep(0.0, 0.25, depth);
  let far = 1.0 - smoothstep(0.5, 1.0, depth);
  return near * far * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }
  var uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseHeld = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let crawlSpeed = u.zoom_params.x * 2.0 + 0.5;
  let swapIntensity = u.zoom_params.y;
  let feedbackMix = u.zoom_params.z * 0.4 + 0.2;
  let flashRate = u.zoom_params.w * 20.0 + 5.0;
  // HEAD read these from zoom_config (time / mouse); regionSize = time grew the
  // Voronoi grid to per-pixel noise within seconds. Now the old midpoints.
  let regionSize = 0.5;
  let glowAmount = 0.15;
  let colorModSpeed = 1.5;
  let depthInf = 0.0;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // ── Single smooth displacement field ──
  let crawledUV = createCrawlingRegions(uv, time, crawlSpeed, mouse, mouseHeld);
  let cells = voronoiRegions(crawledUV, time, regionSize);
  let region = cells.region;
  let crawlVec = crawledUV - uv;
  let crawlMag = length(crawlVec);

  // Smooth hue rotation + spectral tint instead of harsh channel swapping.
  // Each cell re-rolls its hue on its own staggered clock (HEAD hashed the jittering
  // seed position with continuous time, so hues re-rolled every frame).
  // Idea 3: holding the mouse scrambles cells near the cursor much faster.
  let cellPhase = hash1(cells.cellId * 0.731 + 3.17);
  let aspect = dims.x / max(dims.y, 1.0);
  let cursorCell = (1.0 - smoothstep(0.05, 0.3, length((cells.cellUV - mouse) * vec2<f32>(aspect, 1.0)))) * mouseHeld;
  let swapRate = 2.0 * mix(1.0, 6.0, cursorCell);
  let epoch = floor(time * swapRate + cellPhase);
  let regionHash = hash3(vec3<f32>(cells.cellId.x, cells.cellId.y, epoch * 0.137));
  let hueAngle = (regionHash.x - 0.5) * 3.14159 * 2.0 * swapIntensity;
  let rotatedColor = hueRotate(inputColor, hueAngle);
  let lambda = mix(450.0, 650.0, regionHash.y);
  let spectralTint = wavelengthToRGB(lambda);
  let tintBlend = tentAlpha(crawlMag * 5.0) * swapIntensity;
  var color = mix(rotatedColor, rotatedColor * spectralTint, tintBlend);

  // Depth modulates intensity for compositing awareness
  let depthModIntensity = swapIntensity * (1.0 - depth * depthInf * 0.5);
  color = mix(inputColor, color, depthModIntensity);

  // Idea 1: Cell membranes — thin seam where F2−F1 → 0, tinted by the
  // *neighbour* cell's spectral wavelength, so cells read as living cells pressing
  // against each other. Width is ~1.5 px (cell units per pixel = grid/dims).
  let neighHash = hash3(vec3<f32>(cells.neighId.x, cells.neighId.y, floor(time * 2.0 + hash1(cells.neighId * 0.731 + 3.17)) * 0.137));
  let neighTint = wavelengthToRGB(mix(450.0, 650.0, neighHash.y));
  // Cell units per pixel through the crawl warp (the crawl compresses space up to ~16×
  // near the crawl centres); membranes fade where cells shrink below ~6 px, else they alias to speckle.
  let crawlDx = createCrawlingRegions(uv + vec2<f32>(1.0 / dims.x, 0.0), time, crawlSpeed, mouse, mouseHeld) - crawledUV;
  let crawlDy = createCrawlingRegions(uv + vec2<f32>(0.0, 1.0 / dims.y), time, crawlSpeed, mouse, mouseHeld) - crawledUV;
  let edgePx = max(max(length(crawlDx * cells.grid), length(crawlDy * cells.grid)), 1e-4);
  let membrane = (1.0 - smoothstep(0.5 * edgePx, 2.0 * edgePx + 0.02, cells.edge)) * (1.0 - smoothstep(0.12, 0.3, edgePx));
  let membraneAmt = membrane * (0.25 + 0.6 * swapIntensity);
  let lumIn = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(color, neighTint * (0.5 + 0.7 * lumIn), membraneAmt);

  // Idea 2: Trails stream behind the crawl — C is read upstream along this pixel's
  // per-frame crawl motion (crawl at t vs t − 16 ms, so it scales with crawlSpeed),
  // so colour streams behind moving fronts. Exact load, no sampler on C.
  let prevCrawled = createCrawlingRegions(uv, time - 0.016, crawlSpeed, mouse, mouseHeld);
  var crawlStep = (crawledUV - prevCrawled) * 1.5;
  let stepLen = length(crawlStep);
  if (stepLen > 0.015) { crawlStep = crawlStep * (0.015 / stepLen); }
  let upstreamUV = clamp(uv - crawlStep, vec2<f32>(0.0), vec2<f32>(1.0));
  let cDims = vec2<i32>(textureDimensions(dataTextureC));
  let cCoord = clamp(vec2<i32>(upstreamUV * vec2<f32>(cDims)), vec2<i32>(0), cDims - vec2<i32>(1));
  let prevColor = max(textureLoad(dataTextureC, cCoord, 0).rgb, vec3<f32>(0.0));
  let animatedMix = feedbackMix + sin(time * 3.0 + uv.x * 5.0) * 0.1;
  color = mix(color, prevColor, animatedMix);

  // Temporal color modulation via smooth oscillators
  let modOsc = vec3<f32>(
    sin(time * colorModSpeed * 2.0 + uv.x * 10.0) * 0.1 + 1.0,
    cos(time * colorModSpeed * 1.7 + uv.y * 8.0) * 0.1 + 1.0,
    sin(time * colorModSpeed * 2.3 + (uv.x + uv.y) * 6.0) * 0.1 + 1.0
  );
  color = color * modOsc;

  // Smooth flash pulse instead of hard binary step
  let flashPhase = time * flashRate + region.x * 10.0 + region.y * 7.0;
  let flash = gaussianMask(fract(flashPhase) - 0.5, 0.12) * 2.0;
  let flashColor = vec3<f32>(1.0, 0.5, 0.8) * flash;
  color = mix(color, color + flashColor, glowAmount * 1.5);

  // Crawling glow with smooth gaussian falloff
  let crawlGlow = smoothstep(0.0, 0.15, crawlMag) * 5.0 * glowAmount;
  let glowColor = vec3<f32>(0.8, 0.4, 1.0) * crawlGlow;
  color = color + glowColor;

  // Audio-reactive enhancement: treble drives sparkle near crawl fronts
  let treble = plasmaBuffer[0].z;
  let bass = plasmaBuffer[0].x;
  color = color * (1.0 + treble * 0.2 * crawlMag * 10.0);
  color = color + vec3<f32>(0.2, 0.1, 0.3) * bass * crawlGlow;

  // Depth-aware compositing: soften edges in deep areas
  let depthSoft = smoothstep(0.2, 0.7, depth);
  color = mix(color, inputColor, depthSoft * 0.25);

  // Alpha = crawl intensity mapped through smooth tent curve
  // Membranes are opaque tissue: they raise coverage.
  let alpha = max(tentAlpha(crawlMag * 4.0) * (0.6 + swapIntensity * 0.4), membraneAmt);
  let finalAlpha = clamp(alpha + glowAmount * 0.15, 0.15, 0.9);

  // hueRotate can go negative — clamp before storing history and before ACES.
  let linearColor = max(color, vec3<f32>(0.0));
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces_tonemap(linearColor), finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(linearColor, finalAlpha));
}
