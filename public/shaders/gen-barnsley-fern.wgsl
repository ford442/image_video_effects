// ═══════════════════════════════════════════════════════════════════
//  Barnsley Fern IFS
//  Category: generative
//  Features: barnsley-ifs, audio-reactive, upgraded-rgba, mouse-driven
//  Upgraded: 2026-10-11, 2026-10-25
//  Ideas: last-affine tint (stem vs leaflets); stem-rib density from idx 0; pinna rachis; crozier tip; rachis scales; sori; IFS orbit-trap midrib veins on every sub-frond (§12.2E); Beer-Lambert chlorophyll leaf transmission (§12.2F); cantilever frond sway (§12.1)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const FERN_DEPTH: i32 = 10;   // inverse-IFS chain length (HEAD: 7)

// ── Hash, value noise & fBM ───────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453123;
  return fract(vec2<f32>(n, n * 1.618));
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  return p + strength * vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
}

// ── Voronoi displacement ──────────────────────────────────────────
fn voronoi(p: vec2<f32>) -> vec2<f32> {
  let i = floor(p); let f = fract(p);
  var md = 8.0; var md2 = 8.0; var cell = vec2<f32>(0.0);
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let g = vec2<f32>(f32(x), f32(y));
      let h = hash22(i + g);
      let d = length(g + h - f);
      if d < md {
        md2 = md; md = d; cell = i + g + h;
      } else if d < md2 {
        md2 = d;
      }
    }
  }
  return vec2<f32>(md, md2 - md);
}

// ── Quasi-random Halton sequence ──────────────────────────────────
fn halton(i: u32, base: u32) -> f32 {
  var f = 1.0; var r = 0.0; var idx = i;
  loop { if (idx == 0u) { break; } f = f / f32(base); r += f * f32(idx % base); idx /= base; }
  return r;
}

// ── Color helpers ─────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let a = atan2(uv.y - 0.5, uv.x - 0.5);
  let s = vec2<f32>(cos(a), sin(a)) * strength;
  return vec3<f32>(color.r * (1.0 + s.x * 0.8), color.g, color.b * (1.0 - s.y * 0.5));
}

fn audioPalette(fy: f32, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
  let forest = vec3<f32>(0.02, 0.18, 0.04);
  let emerald = vec3<f32>(0.05, 0.65, 0.18);
  let lime = vec3<f32>(0.45, 0.95, 0.12);
  let gold = vec3<f32>(0.85, 0.75, 0.15);
  let magenta = vec3<f32>(0.95, 0.12, 0.72);
  let cyan = vec3<f32>(0.12, 0.92, 1.0);
  var c: vec3<f32>;
  if fy < 0.3 { c = mix(forest, emerald, fy / 0.3); }
  else if fy < 0.7 { c = mix(emerald, lime, (fy - 0.3) / 0.4); }
  else { c = mix(lime, gold, (fy - 0.7) / 0.3); }
  let shift = clamp(bass * 0.35 + treble * 0.25, 0.0, 1.0);
  c = mix(c, magenta, shift * 0.45);
  c = mix(c, cyan, mids * 0.28);
  return c;
}

// ── Inverse IFS transforms ────────────────────────────────────────
fn barnsleyInv(p: vec2<f32>, idx: i32) -> vec2<f32> {
  if idx == 0 { return vec2<f32>(0.0, p.y / 0.16); }
  if idx == 1 { let dy = p.y - 1.6; return vec2<f32>((0.85 * p.x - 0.04 * dy) / 0.7241, (0.04 * p.x + 0.85 * dy) / 0.7241); }
  if idx == 2 { let dy = p.y - 1.6; return vec2<f32>((0.22 * p.x + 0.26 * dy) / 0.1038, (-0.23 * p.x + 0.2 * dy) / 0.1038); }
  let dy = p.y - 0.44; return vec2<f32>((-0.24 * p.x + 0.28 * dy) / 0.1088, (0.26 * p.x + 0.15 * dy) / 0.1088);
}

fn pickIFS(h: f32) -> i32 {
  var idx = 1;
  if h < 0.01 { idx = 0; } else if h < 0.86 { idx = 1; } else if h < 0.93 { idx = 2; } else { idx = 3; }
  return idx;
}

// Fern attractor bounding box (x∈[-2.18,2.66], y∈[0,10]) with a small margin.
fn inFernBox(q: vec2<f32>) -> bool {
  return q.x > -2.3 && q.x < 2.8 && q.y > -0.05 && q.y < 10.05;
}

// HEAD picked the inverse map blindly (86% the main-frond map), so almost no chain survived 7 steps and the
// fern rendered as sparse speckle. Same Monte-Carlo inverse IFS, but the choice is restricted to maps whose
// preimage still lies inside the attractor's bounding box (the stem map only where |x| is small, as before).
// Returns the chosen idx in .z and the preimage in .xy; idx = -1 when no map keeps the point inside.
fn pickValidInverse(q: vec2<f32>, h: f32) -> vec3<f32> {
  let q0 = barnsleyInv(q, 0); let q1 = barnsleyInv(q, 1);
  let q2 = barnsleyInv(q, 2); let q3 = barnsleyInv(q, 3);
  let w0 = select(0.0, 0.1, abs(q.x) < 0.18 && inFernBox(q0));
  let w1 = select(0.0, 0.5, inFernBox(q1));
  let w2 = select(0.0, 0.2, inFernBox(q2));
  let w3 = select(0.0, 0.2, inFernBox(q3));
  let tot = w0 + w1 + w2 + w3;
  if tot <= 0.0 { return vec3<f32>(q, -1.0); }
  let r = h * tot;
  if r < w0 { return vec3<f32>(q0, 0.0); }
  if r < w0 + w1 { return vec3<f32>(q1, 1.0); }
  if r < w0 + w1 + w2 { return vec3<f32>(q2, 2.0); }
  return vec3<f32>(q3, 3.0);
}

// Screen (min-axis normalised, y down) -> fern IFS coordinates (upright, y∈[0,10] at scale 1, zoom about the middle).
fn toFern(uvv: vec2<f32>, scale: f32) -> vec2<f32> {
  let c = vec2<f32>(0.0, 5.0);
  return (vec2<f32>(uvv.x * 10.0, 5.0 - uvv.y * 10.0) - c) / scale + c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let pixel = vec2<i32>(gid.xy);
  if pixel.x >= i32(res.x) || pixel.y >= i32(res.y) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x * 2.4;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  // HEAD's spring lived in extraBuffer[133..138], which is re-zeroed every frame (and written by one thread
  // while the rest read it), so it always resolved to the raw pointer. Use the pointer directly.
  let mouse = rawMouse;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(1.0, 1.45, mouseDown);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scale = mix(0.7, 1.3, u.zoom_params.x);
  let caAmt = u.zoom_params.y * 0.08;
  let brightness = mix(0.8, 2.0, u.zoom_params.z);
  let feedback = u.zoom_params.w;

  // HEAD fix: the IFS lives in y∈[0,10] with x∈[-2.7,2.7]; HEAD centred the frame on y=0 with y pointing down
  // (and counted aspect twice), so only an upside-down fern base showed and the rest was alpha-0 palette.
  var p = toFern(uv, scale);

  // Organic domain warp driven by bass + time
  let warp = domainWarp(p * 1.5 + vec2<f32>(time * 0.07, time * 0.05), 0.18 + bass * 0.08, 3);
  p = mix(p, warp, 0.35 + bass * 0.15);

  // Voronoi displacement on frond coordinates
  let voro = voronoi(p * 0.35 + vec2<f32>(time * 0.04, time * 0.03));
  p = p + (vec2<f32>(voro.y, voro.x) - 0.5) * 0.18 * (1.0 + treble + mids);

  // Mouse attracts frond tips (held-drag tightens)
  let mouseFern = toFern((mouse - 0.5) * res / min(res.x, res.y), scale);
  let tipFactor = smoothstep(0.0, 1.0, p.y / 10.0);
  let pull = exp(-length(p - mouseFern) * 0.65) * tipFactor * 0.55 * held;
  p = mix(p, mouseFern, pull);

  // ── Idea 3: cantilever sway (§12.1 tactic 2) — a frond is a cantilever: base fixed, tip lags and swings most.
  // The bend is a smooth shear of the plane before the IFS test, so every sub-frond rides it; mids make it gust.
  let h01 = clamp(p.y / 10.0, 0.0, 1.0);
  p.x = p.x + (0.2 + 0.25 * mids) * sin(time * 0.7 + p.y * 0.55) * h01 * h01;

  // Quasi-random inverse IFS Monte-Carlo coverage
  let baseIdx = u32(gid.x) * 73u + u32(gid.y) * 131u + u32(time * 60.0);
  let numPaths = i32(mix(2.0, 5.0, depth + bass * 0.3));
  var density = 0.0;
  var stemHits = 0.0;
  var pinnaHits = 0.0;
  var leafletMix = 0.0;
  var veinAcc = 0.0;
  var validPaths = 0.0;

  for (var path = 0; path < numPaths; path = path + 1) {
    var q = p; var valid = 1.0; var lastIdx = 1;
    var trap = 1e3;
    for (var i = 0; i < FERN_DEPTH; i = i + 1) {
      let h = halton(baseIdx + u32(path) * 11u + u32(i), 2u);
      let pick = pickValidInverse(q, h);
      if pick.z < 0.0 { valid = 0.0; break; }
      q = pick.xy;
      lastIdx = i32(pick.z);
      // ── Idea 1: orbit trap (§12.2E) — q is frond-local at this recursion depth, so |q.x| is the distance to the
      // local rachis; the minimum over the chain traces a midrib on every sub-frond, self-similar by construction.
      trap = min(trap, abs(q.x));
    }
    density += valid;
    veinAcc += valid * exp(-trap * 9.0);
    validPaths += valid;
    stemHits += valid * select(0.0, 1.0, lastIdx == 0);
    pinnaHits += valid * select(0.0, 1.0, lastIdx == 2 || lastIdx == 3);
    leafletMix += valid * f32(lastIdx) / 3.0;
  }
  density /= f32(numPaths);
  stemHits /= max(f32(numPaths), 1.0);
  pinnaHits /= max(f32(numPaths), 1.0);
  leafletMix /= max(f32(numPaths), 1.0);

  // Multi-scale detail noise modulated by treble
  let detail = fbm(p * 6.0 + vec2<f32>(time * 0.1), 3) * (0.08 + treble * 0.12);
  density = saturate(density * (1.0 + detail) - detail * 0.3);
  // Idea 2 — stem rib from the stem affine
  density = saturate(density + stemHits * 0.22);
  // Idea 3 — pinna rachis on the side-leaflet affines
  density = saturate(density + pinnaHits * 0.1);
  // Idea 4 — fiddlehead crozier at the high-y tip
  let tipRadius = length(vec2<f32>(p.x * 1.6, p.y - 8.8));
  let crozier = exp(-abs(tipRadius - 0.7) * 4.5) * smoothstep(6.2, 8.0, p.y) * density;
  density = saturate(density + crozier * 0.85);
  let vein = veinAcc / max(validPaths, 1.0);
  density = saturate(density + vein * 0.06 * density);

  // SDF vignette mask — preserves semantic alpha falloff at edges
  let vignette = 1.0 - smoothstep(0.35, 0.85, length(uv));
  density = density * vignette;

  // Natural + audio-driven fern palette by height
  let fy = clamp(p.y / 10.0, 0.0, 1.0);
  var color = audioPalette(fy, bass, mids, treble);
  // Idea 1 — last-affine tint: stem brown vs leaflet greens
  let stemCol = vec3<f32>(0.22, 0.14, 0.04);
  let leafletCol = vec3<f32>(0.12, 0.55, 0.18);
  color = mix(color, mix(stemCol, leafletCol, leafletMix), 0.28);
  let pinnaCol = vec3<f32>(0.55, 0.78, 0.16);
  color = mix(color, pinnaCol, pinnaHits * 0.32);
  // Rachis scales — dark chevrons along the stem.
  let scaleBand = abs(fract(p.y * 1.7) - 0.5);
  color = mix(color, vec3<f32>(0.28, 0.16, 0.05), stemHits * (1.0 - smoothstep(0.04, 0.18, scaleBand)) * 0.65);
  // Sori — brown spore dots on the pinnae.
  let sori = pinnaHits * step(0.74, hash21(floor(p * 2.8)));
  color = mix(color, vec3<f32>(0.42, 0.24, 0.08), sori * 0.75);

  // Midribs: pale, chlorophyll-poor lines on the orbit-trap ridges
  color = mix(color, vec3<f32>(0.80, 0.92, 0.50), vein * 0.4 * smoothstep(0.1, 0.5, density));

  // Sunlight filtering through fronds
  let sun = 0.3 + 0.7 * smoothstep(0.2, 0.9, density);
  color = color * sun * brightness;

  // ── Idea 2: Beer-Lambert leaf transmission (§12.2F) — chlorophyll absorbs red and blue, so backlit thin tissue
  // glows yellow-green while the opaque core stays dark. Thickness comes from the coverage the IFS already measures.
  let thickness = 0.35 + 1.6 * density;
  let transmit = exp(-vec3<f32>(1.1, 0.25, 1.4) * thickness);
  let backlit = transmit * vec3<f32>(1.0, 0.92, 0.55) * smoothstep(0.05, 0.35, density) * (1.0 - 0.5 * density);
  color = color + backlit * brightness * 0.35;

  // Chromatic aberration on fern edges
  let edge = smoothstep(0.15, 0.75, density);
  color = genChromaticShift(color, uv01, caAmt * edge);

  color = acesToneMap(color * 1.8);

  // Temporal feedback echo
  color = mix(color, prev.rgb * 0.96, 0.03 + feedback * 0.08 + bass * 0.02);
  let geo = abs(fract(voro.y * 8.0 + time * 0.4) - 0.5);
  color += vec3<f32>(0.85, 0.15, 1.0) * (1.0 - smoothstep(0.0, 0.08, geo)) * 0.25 * (0.4 + treble);

  // Audio warms palette
  let warmth = bass * 0.15;
  color = vec3<f32>(color.r * (1.0 + warmth), color.g, color.b * (1.0 - warmth * 0.3));

  let photo = smoothstep(0.0, 0.4, color.g);
  let alpha = density * photo * (0.4 + depth * 0.6);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(density * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
}
