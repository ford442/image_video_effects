// ═══════════════════════════════════════════════════════════════════
//  Hexagon Mosaic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-ripples, glass-tiles,
//            vignette-grain, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23, 2026-10-31
//  Ideas: pointer-keyed bevel; neighbour-pane leak into the grout
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const TAU: f32 = 6.28318530718;

// ── Helpers ─────────────────────────────────────────────────────────
// Canonical 2D hash (shared library pattern).
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// Distance from a point inside a mosaic cell to the nearest hex edge.
// The two-offset-grid lattice has 6 nearest neighbours at 60° intervals,
// so each Voronoi cell is a regular hexagon of inradius 0.5 whose edge
// normals are n1/n2/n3 below. Result is >= 0 inside the cell.
fn hexEdgeDist(p: vec2<f32>) -> f32 {
  let d1 = dot(p, vec2<f32>(1.0, 0.0));
  let d2 = dot(p, vec2<f32>(0.5, 0.8660254));
  let d3 = dot(p, vec2<f32>(-0.5, 0.8660254));
  return 0.5 - max(d1, max(d2, d3));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / u.config.zw;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Params (semantics unchanged: density / radius / hardness / sat) ──
  let gridScaleBase = mix(10.0, 150.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let focusRadius = clamp(clamp(u.zoom_params.y, 0.0, 1.0) * 0.8, 0.0, 1.0);
  let edgeHardness = clamp(u.zoom_params.z, 0.0, 1.0);
  let satBoost = clamp(clamp(u.zoom_params.w, 0.0, 1.0) * (1.0 + bass * 0.3 + mids * 0.15), 0.0, 3.0);

  let aspect = u.config.z / max(u.config.w, 0.001);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let mousePos = u.zoom_config.yz;
  let press = step(0.5, u.zoom_config.w);
  let dMouse = distance(uv * aspectVec, mousePos * aspectVec);

  // Press-to-magnify: tiles gently bulge under the cursor while held.
  let bulge = 1.0 - press * 0.30 * exp(-dMouse * dMouse * 18.0);
  let gridScale = gridScaleBase * bulge;

  // ── Hex lattice: two offset grids, pick the nearest centre ──────
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;

  let uvScaled = uv * aspectVec * gridScale;

  let uvA = uvScaled / r;
  let idA = floor(uvA + 0.5);
  let uvB = (uvScaled - h) / r;
  let idB = floor(uvB + 0.5);

  let centerA = idA * r;
  let centerB = idB * r + h;

  let distA = distance(uvScaled, centerA);
  let distB = distance(uvScaled, centerB);

  let center = select(centerB, centerA, distA < distB);
  let cellP = uvScaled - center;
  let centerUV = clamp(center / gridScale / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));

  // ── Mosaic sample + luma-preserving saturation boost ────────────
  let hexColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let origColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let tileLuma = dot(hexColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  var tileRgb = clamp(mix(vec3<f32>(tileLuma), hexColor.rgb, 1.0 + satBoost), vec3<f32>(0.0), vec3<f32>(1.0));

  // ── Glass-tile shading: dome, directional bevel, grout ──────────
  let pxScaled = gridScale / max(u.config.w, 1.0);   // one screen pixel in scaled units
  let edgeDist = max(hexEdgeDist(cellP), 0.0);
  let bevelBand = 1.0 - smoothstep(0.02, 0.30, edgeDist); // 1 near tile edge, 0 interior

  // ── Idea 1: pointer-keyed bevel ─────────────────────────────────
  // The dome already shades by cellP. The key now sits at the cursor so
  // each pane's highlight faces the pointer.
  let toPointer = (mousePos - centerUV) * aspectVec;
  let pointerLen = length(toPointer);
  let lightDir = select(vec2<f32>(-0.6, 0.8), toPointer / max(pointerLen, 1e-4), pointerLen > 0.02);
  let safeCellP = cellP + vec2<f32>(0.0001, -0.0001);
  let facing = dot(normalize(safeCellP), normalize(lightDir));
  let bevel = bevelBand * facing * 0.22;
  let dome = (1.0 - smoothstep(0.0, 0.55, length(cellP))) * 0.08;
  let shade = clamp(1.0 + dome + bevel, 0.6, 1.4);
  tileRgb = tileRgb * shade;

  // Grout: thin dark seams derived from the tile colour.
  let groutW = clamp(1.6 * pxScaled, 0.0, 0.14);
  let groutAA = max(1.2 * pxScaled, 0.001);
  let tileMask = smoothstep(0.0, groutAA, edgeDist - groutW);
  tileRgb = mix(tileRgb * 0.35, tileRgb, tileMask);

  // ── Idea 2: neighbour-pane leak ─────────────────────────────────
  // The lattice centre we did not pick is the adjacent pane. Its colour
  // stains the grout; the tile interior stays the winning centre.
  let otherCenter = select(centerA, centerB, distA < distB);
  let otherUV = clamp(otherCenter / gridScale / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));
  let otherCol = textureSampleLevel(readTexture, u_sampler, otherUV, 0.0).rgb;
  tileRgb = mix(tileRgb, otherCol, (1.0 - tileMask) * 0.55);

  // ── Glint sweep: per-tile phase hash, audio-reactive ────────────
  let cellPhase = hash21(center) * TAU;
  let cellSpeed = 0.5 + hash21(center + vec2<f32>(7.31, 3.17));
  let wave = sin(cellPhase + time * cellSpeed + dot(center, vec2<f32>(0.8, 0.6)) * 0.6);
  let glintAmp = 0.10 + mids * 0.10 + treble * 0.12;
  let glint = pow(max(wave, 0.0), 6.0) * glintAmp * bevelBand * tileMask;
  tileRgb = tileRgb + vec3<f32>(glint);

  // ── Click ripples: rings of light crossing the bevels ───────────
  var rippleGlow = 0.0;
  for (var i: u32 = 0u; i < 50u; i = i + 1u) {
    let rp = u.ripples[i];
    let elapsed = time - rp.z;
    let ringOn = f32(rp.z > 0.0 && elapsed >= 0.0 && elapsed <= 2.5);
    let rd = distance(uv * aspectVec, rp.xy * aspectVec);
    let ring = (1.0 - smoothstep(0.0, 0.05, abs(rd - elapsed * 0.55)))
             * max(0.0, 1.0 - elapsed / 2.5);
    rippleGlow = rippleGlow + ringOn * ring;
  }
  rippleGlow = min(rippleGlow, 1.2);
  tileRgb = tileRgb + vec3<f32>(rippleGlow * 0.35) * (0.4 + 0.6 * bevelBand);

  // ── Mosaic-only polish: vignette + fine animated grain ──────────
  let vig = 1.0 - 0.22 * smoothstep(0.45, 0.95, distance(uv, vec2<f32>(0.5)));
  let grainSeed = uv * u.config.zw + vec2<f32>(fract(time) * 91.7, fract(time * 1.31) * 57.3);
  let grain = (hash21(grainSeed) - 0.5) * 0.028;
  tileRgb = clamp(tileRgb * vig + vec3<f32>(grain), vec3<f32>(0.0), vec3<f32>(1.0));

  // ── Mouse reveal (press expands it) + press halo ────────────────
  let effFocus = clamp(focusRadius * (1.0 + press * 0.30), 0.0, 1.0);
  let edgeWidth = max((1.0 - edgeHardness) * 0.2, 0.001);
  let mask = clamp(smoothstep(effFocus, effFocus + edgeWidth, dMouse), 0.0, 1.0);
  let halo = press * 0.30 * (1.0 - smoothstep(0.0, 0.05, abs(dMouse - effFocus - edgeWidth * 0.5)));

  let revealed = mix(origColor.rgb, tileRgb, mask);
  let lit = revealed + vec3<f32>(halo) * (0.5 + 0.5 * bevelBand);
  let outRgb = aces(max(lit, vec3<f32>(0.0)));
  let cover = mix(origColor.a, hexColor.a, mask);
  let alpha = clamp(cover * (0.62 + 0.38 * tileMask) * (0.8 + 0.2 * mask), 0.0, 1.0);
  let finalColor = vec4<f32>(outRgb, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coords, finalColor);
  textureStore(dataTextureA, coords, finalColor);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
