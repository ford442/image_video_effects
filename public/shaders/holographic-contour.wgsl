// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Contour — Sobel Contours with Spectral Interference Plates
//  Category: artistic
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, sobel-contours, halftone, interference-plate,
//            chromatic-aberration, temporal-plate, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 60)
// ═══════════════════════════════════════════════════════════════════════════════
//  BUG FIXED IN THIS PASS — dead audio. The shader declared `audio-reactive`
//  and `audio-driven` in its JSON and bound `plasmaBuffer` at binding 12, but
//  never read a single sample from it: the binding existed purely to satisfy
//  the layout. Every "reactive" claim in the catalogue was false. Audio now
//  comes from `plasmaBuffer[0].xyz` with per-band detail from `[1..8]`.
//
//  Also fixed:
//    - Depth clobber. `writeDepthTexture` was fed `ink_alpha`, so any chained
//      depth-aware shader downstream read ink coverage instead of geometry.
//      Scene depth is preserved and only shifted by the contour relief.
//    - Dead `radius` variable: `sqrt(luma) * 0.5` was computed for the halftone
//      and never used — the dot size came from an unrelated expression. The
//      halftone now uses a real luminance-driven radius.
//    - The source was machine-generated WGSL (naga round-trip output: `_e20`
//      temporaries, `loop { continuing { } }` blocks, `var` for every local).
//      Rewritten as readable source with the same algorithm.
//
//  TWO NEW STRUCTURES
//
//    1. Interference plate — a hologram is a recorded interference pattern, not
//       an edge filter. The contour field is now cross-modulated with a
//       reference-beam fringe whose fringe spacing comes from the eight FFT
//       bins, producing the moiré plate structure a real hologram shows when
//       tilted. The pointer sets the reference-beam angle, so moving the cursor
//       sweeps the fringes across the frame.
//
//    2. Depth-parallax contour shells — contours are extracted at three
//       luminance offsets and composited at slightly different parallax
//       offsets driven by scene depth, so the contour set reads as stacked
//       plates at different heights rather than one flat trace.
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DotSize, y=EdgeThreshold, z=Levels, w=InkDensity
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Sobel gradient magnitude of luminance at `uv`, one texel apart.
fn sobelEdge(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  var gx = 0.0;
  var gy = 0.0;
  for (var i = -1; i <= 1; i = i + 1) {
    for (var j = -1; j <= 1; j = j + 1) {
      let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
      let l = getLuma(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb);
      // Separable Sobel weights: ±1 on the outer columns/rows, doubled on axis.
      var wx = f32(i);
      var wy = f32(j);
      if (j == 0) { wx = wx * 2.0; }
      if (i == 0) { wy = wy * 2.0; }
      gx = gx + l * wx;
      gy = gy + l * wy;
    }
  }
  return length(vec2<f32>(gx, gy));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dimsI);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = vec2<f32>(1.0) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let mousePos = u.zoom_config.yz;
  let held = step(0.5, u.zoom_config.w);

  // ── Audio (the binding existed but was never read — see header) ───────────
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Params ───────────────────────────────────────────────────────────────
  let dotSize = u.zoom_params.x * 20.0 + 2.0;
  let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5) * (1.0 - bass * 0.25);
  let levels = floor(u.zoom_params.z * 10.0) + 2.0;
  let inkDensity = u.zoom_params.w;

  // ── Bounded click fronts ─────────────────────────────────────────────────
  var clickFront = 0.0;
  var frontGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.4) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let front = r - age * 0.5;
      let env = exp(-front * front * 170.0) * exp(-age * 1.4);
      clickFront += env;
      frontGlow += env * env;
    }
  }
  clickFront = min(clickFront, 1.5);
  frontGlow = min(frontGlow, 1.2);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // ── Structure 2: depth-parallax contour shells ───────────────────────────
  // Three contour traces at slightly different parallax offsets; near geometry
  // separates them more, so the plates stack in apparent height.
  let parallax = (1.0 - depth) * (0.0015 + inkDensity * 0.0025);
  let e0 = sobelEdge(uv, pixelSize);
  let e1 = sobelEdge(uv + vec2<f32>(parallax, 0.0), pixelSize);
  let e2 = sobelEdge(uv - vec2<f32>(0.0, parallax), pixelSize);
  let edgeStack = vec3<f32>(step(edgeThresh, e0),
                            step(edgeThresh, e1),
                            step(edgeThresh, e2));
  let isEdge = max(edgeStack.x, max(edgeStack.y, edgeStack.z));

  // Chromatic split across the shells: each plate carries its own channel.
  let shellTint = vec3<f32>(0.35, 0.85, 1.0) * edgeStack.x
                + vec3<f32>(1.0, 0.45, 0.75) * edgeStack.y * 0.6
                + vec3<f32>(0.6, 1.0, 0.55) * edgeStack.z * 0.6;

  // ── Base colour and posterisation ────────────────────────────────────────
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(color);
  color = floor(color * levels) / levels;

  // ── Halftone (radius now actually derived from luminance) ────────────────
  let gridPos = vec2<f32>(global_id.xy) / dotSize;
  let gridCenter = floor(gridPos) + vec2<f32>(0.5);
  let cellDist = length(gridPos - gridCenter);
  // Dark areas get large dots, bright areas small ones — the classic mapping.
  let dotRadius = sqrt(clamp(1.0 - luma, 0.0, 1.0)) * 0.6;
  let isDot = step(cellDist, dotRadius);

  // ── Structure 1: interference plate ──────────────────────────────────────
  // Reference beam direction follows the pointer; fringe spacing per FFT band.
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let beamAngle = atan2(toMouse.y, toMouse.x) * mix(0.25, 1.0, held);
  let beamDir = vec2<f32>(cos(beamAngle), sin(beamAngle));
  let bandIdx = u32(clamp(luma * 8.0, 0.0, 7.999));
  let band = plasmaBuffer[bandIdx + 1u].x;
  let fringeK = 140.0 + band * 260.0 + mids * 90.0;
  // Object beam phase from the contour field, reference beam from the pointer.
  let objectPhase = e0 * 18.0 + luma * TAU;
  let refPhase = dot(uv * vec2<f32>(aspect, 1.0), beamDir) * fringeK - time * (1.2 + treble * 2.0);
  let fringe = 0.5 + 0.5 * cos(objectPhase + refPhase);
  let plate = fringe * (0.25 + band * 0.6 + clickFront * 0.5);

  // ── Compose ──────────────────────────────────────────────────────────────
  var finalColor = color;
  var inkAlpha = 0.0;

  // Contour ink.
  let lineDensity = inkDensity * 0.9 + 0.05;
  finalColor = mix(finalColor, vec3<f32>(0.02, 0.02, 0.04), isEdge * inkDensity);
  finalColor += shellTint * isEdge * (0.25 + plate * 0.9);
  inkAlpha = max(inkAlpha, isEdge * lineDensity);

  // Halftone ink.
  let dotCoverage = smoothstep(0.0, 0.7, 1.0 - luma);
  finalColor = mix(finalColor, finalColor * 0.7, isDot * 0.8);
  inkAlpha = max(inkAlpha, isDot * dotCoverage * inkDensity * 0.85);

  // Plate glow across the whole frame, strongest on the contours.
  finalColor += vec3<f32>(0.30, 0.70, 0.95) * plate * (0.12 + isEdge * 0.35);
  finalColor += vec3<f32>(1.0, 0.85, 0.6) * frontGlow * (0.4 + bass * 0.7);

  // Paper grain (time-varying, as before).
  let paperTex = 0.95 + 0.05 * hash12(uv * time * 0.001 + vec2<f32>(100.0));
  inkAlpha = max(inkAlpha, mix(0.15, 0.45, luma * inkDensity)) * paperTex;

  // Pointer vignette.
  let mDist = length(toMouse);
  let vignette = smoothstep(0.8, 0.2, mDist * 0.5);
  finalColor *= mix(1.0, vignette, 0.6);
  inkAlpha = mix(inkAlpha, min(1.0, inkAlpha * 1.2), vignette * 0.5);

  // ── Temporal plate memory (exact load — dataTextureC is rgba32float) ─────
  let prev = textureLoad(dataTextureC, coord, 0);
  finalColor = max(finalColor, prev.rgb * (0.74 + inkDensity * 0.12));

  finalColor = acesFilm(finalColor);

  let alpha = clamp(max(inkAlpha, frontGlow * 0.5), 0.0, 1.0);
  let outColor = vec4<f32>(finalColor, alpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  // Depth: scene geometry preserved (was overwritten with ink alpha), lifted
  // slightly where a contour shell sits proud of the plate.
  textureStore(writeDepthTexture, coord,
               vec4<f32>(clamp(depth - isEdge * 0.05, 0.0, 1.0), 0.0, 0.0, 1.0));
}
