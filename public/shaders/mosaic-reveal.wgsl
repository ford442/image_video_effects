// ═══════════════════════════════════════════════════════════════════
//  Mosaic Reveal
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, hex-grid
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: tile-turn front; grout + tesserae bevel; re-mosaic afterimage from C
//  A packing: pre-ACES reveal colour history RGB + .a = 10 + accumulated alpha (<9.5 = empty C)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ──────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i++) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── OkLab perceptual mixing ───────────────────────────────────────
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(max(l, 0.0), 1.0 / 3.0);
  let m_ = pow(max(m, 0.0), 1.0 / 3.0);
  let s_ = pow(max(s, 0.0), 1.0 / 3.0);
  return vec3<f32>(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  );
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_;
  let m = m_ * m_ * m_;
  let s = s_ * s_ * s_;
  return vec3<f32>(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

// ── Color science & dither ────────────────────────────────────────
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  let s = min(1.0, max_lum / max(lum, 1e-4));
  return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

// ── Hex grid center (tile space) ──────────────────────────────────
// FIXED: HEAD returned (floor(centre) + 0.5) / size; half the lattice has an
// integer-x centre, so float error flipped the floor -> speckled hex cells.
// Returns the true hex centre in tile (scaled) coordinates.
fn hexCenterTile(uv: vec2<f32>) -> vec2<f32> {
  let s = vec2<f32>(1.0, 1.7320508);
  let h = s * 0.5;
  let a = (uv - s * floor(uv / s)) - h;
  let b = ((uv - h) - s * floor((uv - h) / s)) - h;
  let g = select(a, b, dot(a, a) > dot(b, b));
  return uv - g;
}

// ── Advanced alpha compositing ────────────────────────────────────
fn depthLayeredAlpha(depth: f32) -> f32 {
  return mix(0.38, 1.0, depth);
}

fn lumaKeyAlpha(col: vec3<f32>) -> f32 {
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  return smoothstep(0.03, 0.20, luma);
}

fn edgePreserveAlpha(edgeMask: f32) -> f32 {
  return mix(0.25, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspectVec = vec2<f32>(res.x / res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let cellSize = mix(12.0, 160.0, u.zoom_params.x);
  let revealSpeed = (u.zoom_params.y * 2.0 + 0.2) * (1.0 + mids * 0.8);
  let edgeGlow = u.zoom_params.z * (1.0 + treble * 0.7);
  let isHex = u.zoom_params.w > 0.5;

  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let mouseDist = distance((uv01 - mouse) * aspectVec, vec2<f32>(0.0));

  // Two opposing tile conveyors keep the mosaic field moving continuously.
  let conveyor = vec2<f32>(sin(time * 0.75), cos(time * 0.93)) * (0.008 + u.zoom_params.x * 0.018);
  let tileUV = uv01 + conveyor;
  let tile = tileUV * cellSize;
  let sqCenterT = floor(tile) + 0.5;
  let hxCenterT = hexCenterTile(tile);
  let centerT = select(sqCenterT, hxCenterT, isHex);       // tile centre, tile space
  let tileCenter = centerT / cellSize - conveyor;           // tile centre, screen uv
  let q = tile - centerT;                                   // pixel within tile, ~[-0.5, 0.5]

  var colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, tileCenter, 0.0).rgb;
  var colFull = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // Organic reveal boundary
  let warp = (fbm(uv01 * cellSize * 0.4 + time * 0.15, 3) - 0.5) * 0.06;
  let bassPulse = 1.0 + bass * 0.35;
  let revealCore = 0.45 + 0.38 * sin(time * revealSpeed * bassPulse);
  let revealRadius = clamp(revealCore + warp, 0.04, 0.92);
  let floodRunner = exp(-abs(mouseDist - (0.45 + 0.35 * sin(time * revealSpeed * 1.7 + uv01.x * TAU))) * 45.0);

  var clickWave = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      clickWave = max(clickWave,
        exp(-abs(distance((uv01 - rp.xy) * aspectVec, vec2<f32>(0.0)) - age * 0.48) * 74.0)
        * (1.0 - age / 1.5));
    }
  }

  // Idea 1: Tile-turn front — tiles turn over one by one at the front instead
  // of crossfading per pixel. Progress p is measured at the tile CENTRE (with
  // the same fbm warp sampled there) plus a per-tile jitter; the tile squashes
  // as cos(pi*p): front face = mosaic colour, back face = full image.
  let tileDist = distance((tileCenter - mouse) * aspectVec, vec2<f32>(0.0));
  let tileWarp = (fbm(tileCenter * cellSize * 0.4 + time * 0.15, 3) - 0.5) * 0.06;
  let tileRadius = clamp(revealCore + tileWarp, 0.04, 0.92);
  let jitter = (hash21(centerT + vec2<f32>(3.7, 9.1)) - 0.5) * 0.06;
  let turnP = 1.0 - smoothstep(tileRadius - 0.05 + jitter, tileRadius + 0.05 + jitter, tileDist);
  let squash = abs(cos(PI * turnP));
  let qTurn = vec2<f32>(q.x / max(squash, 0.06), q.y);
  let onFace = 1.0 - smoothstep(0.47, 0.5, abs(qTurn.x));
  let backFace = step(0.5, turnP);
  let backUV = clamp((centerT + qTurn) / cellSize - conveyor, vec2<f32>(0.0), vec2<f32>(1.0));
  let colBack = textureSampleLevel(readTexture, u_sampler, backUV, 0.0).rgb;
  var turnColor = mix(colMosaic, colBack, backFace) * (0.55 + 0.45 * squash);
  turnColor = mix(colMosaic * 0.12, turnColor, onFace);      // dark bed behind a turning tile

  // Pointer extras (flood runner, click fronts) still reveal per pixel on top.
  let extraMask = clamp(max(floodRunner * (0.35 + held * 0.45), clickWave * 0.9), 0.0, 1.0);
  let revealMask = max(turnP, extraMask);

  // Edge mask for rim light
  let edgeMask = smoothstep(revealRadius - 0.12, revealRadius - 0.03, mouseDist)
               * (1.0 - smoothstep(revealRadius + 0.03, revealRadius + 0.12, mouseDist));

  // Perceptually clean mosaic ↔ full transition
  let revealColor = mixOkLab(turnColor, colFull, extraMask);

  // Idea 3: Re-mosaic afterimage — C holds the reveal colour history. Revealed
  // pixels update at once; pixels the disc just left re-tile over ~5 frames.
  // A.a stores 10 + alpha: a C texel outside [9.5, 11.5] (never written, another shader's
  // output right after a switch, NaN) is "fresh" — no afterimage, no alpha memory.
  let prevRaw = textureLoad(dataTextureC, pixel, 0);
  let prevOk = prevRaw.a > 9.5 && prevRaw.a < 11.5;
  let prevRGB = select(revealColor, clamp(prevRaw.rgb, vec3<f32>(0.0), vec3<f32>(4.0)), prevOk);
  let prevA = select(0.0, clamp(prevRaw.a - 10.0, 0.0, 1.0), prevOk);
  let trailRate = mix(0.18, 1.0, revealMask);
  let trail = mix(prevRGB, revealColor, trailRate);
  var color = trail;

  // Idea 2: Grout + tesserae bevel — dark joints and a top-left bevel light on
  // the mosaic side only (the revealed photo stays clean). Tile space, so it
  // rides the conveyors.
  let aq = abs(q);
  let tileD = select(max(aq.x, aq.y), max(aq.x, dot(aq, vec2<f32>(0.5, 0.8660254))), isHex);
  let tileEdge = 0.5 - tileD;
  let mosaicSide = (1.0 - backFace) * (1.0 - extraMask) * onFace;
  let grout = 1.0 - smoothstep(0.015, 0.06, tileEdge);
  let bevelBand = 1.0 - smoothstep(0.04, 0.16, tileEdge);
  let bevelLit = dot(q / max(length(q), 1e-3), vec2<f32>(-0.7071, -0.7071));
  color = color * (1.0 + bevelBand * bevelLit * 0.12 * mosaicSide);
  color = mix(color, color * 0.35 + vec3<f32>(0.02), grout * 0.5 * mosaicSide);

  // Audio-reactive blackbody rim glow
  let temp = 2200.0 + treble * 5500.0 + mids * 1200.0;
  color = color + blackbodyRGB(temp) * edgeMask * edgeGlow * (2.0 + treble);
  let runnerPalette = 0.5 + 0.5 * cos(TAU * (vec3<f32>(uv01.x + uv01.y + time * 0.09)
                                         + vec3<f32>(0.0, 0.33, 0.67)));
  color += runnerPalette * (floodRunner * 0.16 + clickWave * 0.25) * (0.5 + edgeGlow);

  // Depth haze
  let haze = depth * 0.25;
  color = mix(color, color * vec3<f32>(0.6, 0.75, 1.0) + vec3<f32>(0.1, 0.14, 0.2), haze);

  // Vignette
  let vig = 1.0 - dot((uv01 - 0.5) * 1.3, (uv01 - 0.5) * 1.3);
  color = color * mix(0.85, 1.0, clamp(vig, 0.0, 1.0));

  // HDR clamp, ACES tonemap, IGN dither
  color = hue_preserve_clamp(max(color, vec3<f32>(0.0)), 3.0);
  color = aces(color * (1.0 + mids * 0.1));
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Advanced layered alpha: depth, luminance key, edge preserve + accumulative feedback
  let revealAlpha = mix(0.4, 1.0, revealMask);
  let depthAlpha = depthLayeredAlpha(depth);
  let lumaAlpha = lumaKeyAlpha(colMosaic);
  let edgeAlpha = edgePreserveAlpha(edgeMask);
  var alpha = clamp(
    revealAlpha * 0.55 + depthAlpha * 0.25 + lumaAlpha * 0.12 + edgeAlpha * 0.08,
    0.12, 1.0
  );

  // Accumulative temporal alpha feedback
  let accumAlpha = max(alpha, prevA * 0.93);
  alpha = mix(alpha, accumAlpha, 0.35);

  // Depth: tesserae relief on the mosaic side (raised tiles, sunken grout)
  let relief = (smoothstep(0.015, 0.1, tileEdge) * 0.03 - grout * 0.02) * mosaicSide;
  let depthOut = clamp(depth + relief, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(trail, 10.0 + alpha));
}
