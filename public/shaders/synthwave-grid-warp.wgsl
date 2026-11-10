// ═══════════════════════════════════════════════════════════════════
//  Synthwave Grid Warp
//  Category: retro-glitch
//  Features: grid, warp, neon, 80s, audio-drive, depth-grid
//  Complexity: High
//  Updated: 2026-05-31 — Grok (stronger audio drive + depth grid)
// ═══════════════════════════════════════════════════════════════════
//  Upgraded: 2026-04-25, 2026-11-09
//  Ideas: streaming grid + bass/treble line pulse; slatted retro sun; ground-swell warp of the grid lines
//  A packing: display RGBA (the file keeps no state)
//  Orientation: scene maths is y-up; flipped once from the top-origin screen uv (HEAD rendered upside-down)
//  Composition: the horizon is a fixed line (HORIZON, scene uv.y) that the sun straddles and the mountains stand on;
//               Camera Height now scales the grid (cell size / density) instead of dragging the horizon off screen
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ── Composition constants (scene uv, y-up) ───────────────────
const HORIZON: f32 = 0.62;    // the horizon line: sky above, floor below, at every Camera Height
const SUN_RISE: f32 = 0.10;   // sun centre sits this far above the horizon (its slatted lower half sinks behind it)

// ── Screen → World ───────────────────────────────────────────
// Pinhole floor projection with the horizon pinned to `horizon` (HEAD's pitch put it at uv.y = 0.5 + 0.34*camY,
// i.e. on the top edge at the default camera, so the sun and mountains sat on the near floor).
fn screenToWorld(uv: vec2<f32>, camY: f32, fov: f32, horizon: f32) -> vec3<f32> {
  let ndc = (uv - vec2<f32>(0.5)) * 2.0;
  let ndcH = (horizon - 0.5) * 2.0;
  let f = 1.0 / tan(fov * 0.5);
  let t = camY / max((ndcH - ndc.y) * f, 0.001);
  return vec3<f32>(ndc.x * f * t, 0.0, -f * t);
}

// ── Grid SDF ─────────────────────────────────────────────────
fn sdGrid(p: vec3<f32>, spacing: f32) -> f32 {
  let gx = abs(fract(p.x / spacing - 0.5) - 0.5);
  let gz = abs(fract(p.z / spacing - 0.5) - 0.5);
  return min(gx, gz) * spacing;
}

// ── Height Fog ───────────────────────────────────────────────
fn heightFog(dist: f32, height: f32, density: f32, falloff: f32) -> f32 {
  return exp(-density * dist) * exp(-falloff * max(0.0, height));
}

// ── Sun ──────────────────────────────────────────────────────
fn renderSun(uv: vec2<f32>, sunPos: vec2<f32>, size: f32, glow: f32, time: f32, pxPerSun: f32) -> vec3<f32> {
  let d = length(uv - sunPos);
  var core = smoothstep(size, size - 0.001, d);
  let halo = pow(smoothstep(size + glow, size, d), 2.0);
  // ── Idea 2: slatted retro sun ───────────────────────────────────────
  // The lower half of the disc is cut by horizontal slits whose thickness grows toward the bottom and which
  // drift slowly downward. Slit edges are one pixel wide (pxPerSun = sun radius in pixels).
  let yRel = (sunPos.y - uv.y) / size;                       // 0 at the centre line, 1 at the bottom of the disc
  let slits = 5.0;
  let aa = 1.5 * slits / max(pxPerSun, 1.0);
  let thick = max(mix(0.12, 0.62, clamp(yRel, 0.0, 1.0)), aa);
  let dd = abs(fract(yRel * slits - time * 0.1) - 0.5);      // 0.5 at a slit centre
  let cut = smoothstep(0.5 - thick * 0.5 - aa, 0.5 - thick * 0.5 + aa, dd) * smoothstep(0.0, 0.08, yRel);
  core = core * (1.0 - cut);
  return vec3<f32>(1.0, 0.9, 0.6) * (core + halo * 0.5);
}

// ── Mountain Layer ───────────────────────────────────────────
// Ridges stand on the horizon: the silhouette top is HORIZON + n*height and nothing is drawn below the horizon line.
fn mountainLayer(uv: vec2<f32>, layerZ: f32, scale: f32, height: f32, sunPos: vec2<f32>, above: f32) -> vec4<f32> {
  let n = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x * scale, 0.0), 0.0).r;
  let h = n * height;
  let dist = (uv.y - HORIZON) - h;
  let inside = (1.0 - smoothstep(0.0, 0.008, dist)) * above;
  let col = mix(vec3<f32>(0.1, 0.07, 0.2), vec3<f32>(0.3, 0.2, 0.4), inside);
  let toSun = sunPos - uv;
  let rim = max(dot(normalize(vec2<f32>(0.0, 1.0) - vec2<f32>(0.0, h)), normalize(toSun + vec2<f32>(0.0001))), 0.0);
  let col2 = col + rim * 0.2;
  return vec4<f32>(col2, inside);
}

// ── MAIN ─────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let suv = vec2<f32>(global_id.xy) / resolution;          // screen uv, y = 0 at the TOP (depth / output)
  let uv = vec2<f32>(suv.x, 1.0 - suv.y);                  // scene uv, y-up: sky pink toward y=0, mountains rise from y=0
  let aspect = resolution.x / resolution.y;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let camY = mix(0.5, 3.0, u.zoom_params.x);
  let fogDensity = mix(0.1, 2.0, u.zoom_params.y);
  let fogFalloff = mix(0.0, 1.0, u.zoom_params.z);
  let mountainScale = mix(1.0, 8.0, u.zoom_params.w);
  let time = u.config.x;

  // 1 in the sky, 0 on the floor, one pixel of anti-aliasing across the horizon line
  let aaH = 1.5 / resolution.y;
  let above = smoothstep(HORIZON - aaH, HORIZON + aaH, uv.y);

  let worldPos = screenToWorld(uv, camY, 1.2, HORIZON);
  let dist = length(worldPos);

  // ── Idea 1: streaming grid ──────────────────────────────────────────
  // Rows flow toward the camera at a constant world speed (kept modulo the cell so the phase never loses
  // precision and never jumps with audio); bass/treble pulse the line brightness instead of the rate.
  let spacing = 0.5;
  let scroll = fract(time * 0.5 / spacing) * spacing;
  // ── Idea 3: ground swell ────────────────────────────────────────────
  // A travelling sine along z displaces the lines (rows bunch and spread, columns sway); bass deepens it.
  let swellAmp = 0.03 + 0.07 * bass;
  let swellZ = swellAmp * sin(worldPos.z * 2.2 - time * 1.4);
  let swellX = swellAmp * 0.8 * sin(worldPos.z * 1.7 - time * 1.1 + 1.3);
  let gridDist = sdGrid(vec3<f32>(worldPos.x + swellX, 0.0, worldPos.z - scroll + swellZ), spacing);
  // the floor projection is meaningless above the horizon (it clamps to a far plane): no grid in the sky
  let gridLine = smoothstep(0.02, 0.0, gridDist) * (1.0 - above);
  let lineGlow = 1.0 + bass * 0.8 + treble * 0.35 * (0.5 + 0.5 * sin(worldPos.z * 9.0 - time * 7.0));
  let gridCol = vec3<f32>(0.0, 0.8, 1.0) * lineGlow * gridLine;

  // HEAD passed height = 0.0, so the Fog Falloff slider was dead. Height is the scene elevation of the pixel:
  // higher on screen = farther toward the horizon, so Fog Falloff now fades the grid out toward the horizon.
  let fog = heightFog(dist, uv.y * 1.5, fogDensity, fogFalloff);

  let sunPos = vec2<f32>(0.5 + sin(time * 0.05) * 0.1, HORIZON + SUN_RISE);
  let sunSize = 0.09;
  // aspect-correct the disc (HEAD drew an ellipse on a 16:9 canvas); the floor hides whatever sinks below the horizon
  let sun = renderSun(uv * vec2<f32>(aspect, 1.0), sunPos * vec2<f32>(aspect, 1.0), sunSize, 0.2, time, sunSize * resolution.y) * above;

  let m1 = mountainLayer(uv, 0.2, mountainScale, 0.105, sunPos, above);
  let m2 = mountainLayer(uv, 0.5, mountainScale * 1.5, 0.063, sunPos, above);
  // Sky: hot pink at the horizon up to deep violet; floor: near-black violet that glows toward the horizon
  let skyT = clamp((uv.y - HORIZON) / (1.0 - HORIZON), 0.0, 1.0);
  let sky = mix(vec3<f32>(0.95, 0.38, 0.55), vec3<f32>(0.1, 0.05, 0.2), sqrt(skyT));
  let floorGlow = exp(-(HORIZON - uv.y) * 9.0);
  let floorCol = vec3<f32>(0.03, 0.01, 0.08) + vec3<f32>(0.45, 0.1, 0.38) * floorGlow * 0.6;
  let backdrop = mix(floorCol, sky, above);

  // Ridges sit above the horizon where the floor fog (a function of floor distance) is zero, so they get their own
  // aerial perspective: Fog Density tints the far ridge toward the sky behind it more than the near one.
  let haze1 = exp(-0.8 * fogDensity);
  let haze2 = exp(-0.3 * fogDensity);

  // Back to front: sky/floor, far ridge, sun (its slits show the far ridge and sky), near ridge, grid. The far ridge
  // sits behind the sun so the slatted lower half stays readable. Fog fades a grid line into the floor haze through
  // its coverage; it no longer darkens the line's own colour.
  let sunCov = clamp(length(sun), 0.0, 1.0);
  var col = mix(backdrop, mix(sky, m1.rgb, haze1), m1.a);
  col = col * (1.0 - sunCov) + sun * sunCov;
  col = mix(col, mix(sky, m2.rgb, haze2), m2.a);
  col = mix(col, gridCol, clamp(gridLine * fog, 0.0, 1.0));

  // HEAD's col/(col+1) halved every colour (neon cyan 0.8 -> 0.44, sky pink dull mauve): ACES (clamped >= 0).
  col = acesToneMap(col);

  // Grok: Stronger audio drive (bass pulses the grid, treble adds shimmer)
  let audioDrive = 1.0 + bass * 0.7 + treble * 0.5;
  let alpha = clamp(gridLine * 2.0 * audioDrive * fog + length(sun) + m1.a + m2.a, 0.0, 1.15);

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, suv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
