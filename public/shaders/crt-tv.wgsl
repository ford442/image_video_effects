// ═══════════════════════════════════════════════════════════════════
//  CRT TV — Phosphor Physics
//  Category: retro-glitch
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: brightness-dependent beam width; rolling ground-loop hum bar; faceplate glass (rounded tube corners + curved-glass glare)
//  A packing: pre-ACES HDR phosphor RGB (post-persistence, no glass glare) + semantic alpha; C read back as that HDR RGB
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn curveUv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  var centered = uv * 2.0 - 1.0;
  let distSq = dot(centered, centered);
  centered = centered * (1.0 + curvature * distSq);
  return centered * 0.5 + 0.5;
}

// Aperture grille on INTEGER screen columns (never fract(uv*res) at texel centres, which is
// constant). Smooth cosine triad profile: each column peaks one phosphor stripe and keeps the
// other two at a soft floor, normalised to unit mean so the grille does not dim the picture.
fn apertureGrille(pixelX: i32) -> vec3<f32> {
  let phase = (f32(pixelX % 3) + 0.5) / 3.0;
  let centres = vec3<f32>(1.0 / 6.0, 0.5, 5.0 / 6.0);
  let floorLevel = 0.3;
  let profile = 0.5 + 0.5 * cos((vec3<f32>(phase) - centres) * TAU);
  let mask = floorLevel + (1.0 - floorLevel) * profile;
  // mean over a triad = floor + (1-floor)*0.5
  return mask / (floorLevel + (1.0 - floorLevel) * 0.5);
}

// Phosphor gamma decay (per-channel rates kept from HEAD) blended by `amount`; refresh flicker
// kept. The old global humBar is replaced by the spatial rolling hum bar (humGain, idea 2).
fn phosphorDecay(baseColor: vec3<f32>, time: f32, flicker: f32, humGain: f32, amount: f32) -> vec3<f32> {
  let decayRates = vec3<f32>(2.5, 5.0, 10.0);
  let refreshFlicker = 1.0 - flicker * 0.03 * sin(time * 377.0);
  let c = max(baseColor, vec3<f32>(0.0));
  let decayed = pow(c, vec3<f32>(1.0) / decayRates);
  return mix(c, decayed, amount) * refreshFlicker * humGain;
}

// Halation sampled in the SAME source space as the main sample (srcUV is already the curved
// raster coordinate — HEAD re-warped it through an inverse curve and misregistered the glow).
fn halationGlow(srcUV: vec2<f32>, strength: f32, resolution: vec2<f32>) -> vec3<f32> {
  if (strength < 0.01) { return vec3<f32>(0.0); }
  let invRes = 1.0 / resolution;
  var glow = vec3<f32>(0.0);
  var totalWeight = 0.0;
  let offsets = array<vec2<f32>, 5>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0) * invRes * 2.0, vec2<f32>(-1.0, 0.0) * invRes * 2.0,
    vec2<f32>(0.0, 1.0) * invRes * 2.0, vec2<f32>(0.0, -1.0) * invRes * 2.0
  );
  let weights = array<f32, 5>(0.4, 0.15, 0.15, 0.15, 0.15);
  for (var i = 0; i < 5; i = i + 1) {
    let sampleUV = srcUV + offsets[i];
    if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
      let s = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let brightness = dot(s, vec3<f32>(0.299, 0.587, 0.114));
      glow += smoothstep(0.3, 0.8, brightness) * s * weights[i];
      totalWeight += weights[i];
    }
  }
  if (totalWeight > 0.0) { glow /= totalWeight; }
  return glow * vec3<f32>(1.1, 0.95, 0.9) * strength * 2.0;
}

// IDEA 1 — brightness-dependent beam width. Scanlines rebuilt on the curved SOURCE row
// (srcY * lineCount), one Gaussian electron beam per raster line. Beam sigma grows with the
// row's luma: bright rows fatten into the gaps, dark rows stay thin with visible black between.
// Partial energy normalisation keeps thin dark beams from collapsing to black.
// linesPerPx = raster lines per screen pixel; the profile fades out toward Nyquist (0.5) so the
// compressed lines near the curved edges never alias into moire.
fn scanBeam(srcY: f32, lineCount: f32, linesPerPx: f32, luma: f32, intensity: f32, time: f32, mids: f32) -> f32 {
  let row = srcY * lineCount;
  let d = fract(row) - 0.5;                          // distance from beam centre, in line units
  let lineIdx = floor(row);
  let jitter = sin(time * 10.0 + lineIdx * 0.7) * 0.02 * (1.0 + mids * 5.0); // HEAD's mids beam jitter
  let sigma = clamp(mix(0.15, 0.36, sqrt(clamp(luma, 0.0, 1.0))) + jitter, 0.08, 0.45);
  let gauss = exp(-(d * d) / (2.0 * sigma * sigma));
  let coverage = min(sigma * 2.50662827, 1.0);       // integral of the beam over one line
  let beam = gauss / mix(1.0, coverage, 0.5);
  let aa = 1.0 - smoothstep(0.3, 0.5, linesPerPx);
  return mix(1.0, beam, clamp(intensity, 0.0, 1.0) * aa);
}

fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(strength, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(strength, 0.0), 0.0).b;
  return vec3<f32>(r, g, b);
}

fn crtVignette(uv: vec2<f32>, strength: f32) -> f32 {
  let centered = uv * 2.0 - 1.0;
  let dist = length(centered);
  let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
  return vig * (1.0 - abs(centered.x * centered.y) * 0.15 * strength);
}

// IDEA 3a — faceplate: rounded-rect tube mask in aspect space (replaces the hard [0,1] box).
fn tubeSdf(srcUV: vec2<f32>, aspect: f32, radius: f32) -> f32 {
  let halfSize = vec2<f32>(aspect, 1.0);
  let p = (srcUV * 2.0 - 1.0) * halfSize;
  let q = abs(p) - (halfSize - vec2<f32>(radius));
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// IDEA 3b — curved-glass glare: Blinn highlight of a fixed top-left room light on the faceplate
// dome, whose normal tilts with the same curvature that drives the barrel warp.
fn faceplateGlare(uv: vec2<f32>, aspect: f32, curvature: f32, barrel: f32) -> f32 {
  let c = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let slope = c * (0.18 + curvature * 3.0);
  let n = normalize(vec3<f32>(slope, 1.0));
  let l = normalize(vec3<f32>(-0.35, -0.4, 1.0));   // screen y=0 is top: light from upper-left
  let h = normalize(l + vec3<f32>(0.0, 0.0, 1.0));
  let ndh = max(dot(n, h), 0.0);
  let spot = pow(ndh, 320.0);
  let sheen = pow(ndh, 24.0);
  return (spot * 0.10 + sheen * 0.015) * (0.35 + barrel);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // HEAD spring (extraBuffer[133..138] is re-zeroed each frame, so this is effectively raw mouse).
  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let scanlineIntensity = u.zoom_params.x;
  let phosphorGlow = u.zoom_params.y;
  let halationStrength = u.zoom_params.z + treble * 0.5;
  let barrelAmount = u.zoom_params.w;

  var rippleFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleFlash += smoothstep(0.15, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }

  let mouseBulge = smoothstep(0.25, 0.0, length((uv - smoothMouse) * vec2<f32>(aspect, 1.0))) * select(0.0, 0.12, held);
  let curvature = barrelAmount * 0.15 * (1.0 + bass * 0.5 + mouseBulge + rippleFlash * 0.08);
  let flickerAmount = 0.5 + barrelAmount * 0.5 + mids * 0.2;
  let chromaticStr = 0.002 * barrelAmount + treble * 0.005;

  let curved = barrelAmount > 0.01;
  var crtUV = select(uv, curveUv(uv, curvature), curved);
  // Source-row step for one screen pixel down (for scanline anti-aliasing under curvature).
  let nextUV = select(uv + vec2<f32>(0.0, 1.0 / resolution.y),
                      curveUv(uv + vec2<f32>(0.0, 1.0 / resolution.y), curvature), curved);
  let srcRowStep = abs(nextUV.y - crtUV.y);

  // IDEA 3a — rounded faceplate corners; soft glass edge instead of a hard tube cut.
  let cornerRadius = 0.05 + barrelAmount * 0.16;
  let edgeWidth = max(4.0 / resolution.y, barrelAmount * 0.012);
  let sd = tubeSdf(crtUV, aspect, cornerRadius);
  let tubeMask = 1.0 - smoothstep(-edgeWidth, 0.0, sd);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  if (tubeMask <= 0.0) {
    // Bezel: opaque black. Write A (same packing: HDR black) and depth before returning.
    textureStore(writeTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  // IDEA 2 — rolling ground-loop hum bar. 60 Hz mains vs 59.94 Hz field rate beat at 0.06 Hz;
  // stylised to one pass every ~5 s. It rides the curved raster (source row), crawls upward
  // (y=0 is top), dims a soft band and drags the raster sideways inside it. Mids deepen it.
  let humPhase = fract(crtUV.y + time * 0.2);
  let humWave = 0.5 + 0.5 * cos(humPhase * TAU);
  let humBand = humWave * humWave * humWave * humWave;
  let humDepth = clamp(0.1 * flickerAmount + mids * 0.2, 0.0, 0.45);
  let humGain = 1.0 - humDepth * humBand;
  crtUV.x += humBand * (0.0008 + mids * 0.002) * sin(crtUV.y * 40.0 + time * 7.0);

  var color = chromaticAberration(crtUV, chromaticStr);
  let rowLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));

  // IDEA 1 — beam-width scanlines on the curved source row (~3 screen px per line flat).
  let lineCount = max(resolution.y / 3.0, 1.0);
  let linesPerPx = lineCount * srcRowStep;
  color *= scanBeam(crtUV.y, lineCount, linesPerPx, rowLuma, scanlineIntensity, time, mids);
  color *= apertureGrille(coord.x);
  color += halationGlow(crtUV, halationStrength, resolution);

  if (phosphorGlow > 0.01) {
    let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = smoothstep(0.4, 0.9, brightness) * phosphorGlow * 0.4;
    color = mix(color, pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.7)), phosphorGlow * 0.3);
    color += color * bloom;
  }

  color = phosphorDecay(color, time, flickerAmount, humGain, 0.25 + phosphorGlow * 0.3);
  color *= crtVignette(uv, 0.5 + barrelAmount * 0.5);
  color *= 0.95 + fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 0.05;
  color *= vec3<f32>(1.05, 1.02, 0.98);
  color *= tubeMask;

  // C persistence: C holds last frame's pre-ACES HDR phosphor (A packing), so no double tone-map.
  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, max(prev, vec3<f32>(0.0)), 0.08 + phosphorGlow * 0.06);
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(16.0));

  // Semantic alpha: phosphor emission coverage inside the tube, opaque bezel outside.
  let emission = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let tubeAlpha = clamp(0.86 + emission * 0.14 + rippleFlash * 0.15 + bass * 0.05, 0.0, 1.0);
  let alpha = mix(1.0, tubeAlpha, tubeMask);

  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  // IDEA 3b — glass glare sits on the faceplate, not in the phosphor: added after the A write.
  let glare = faceplateGlare(uv, aspect, curvature, barrelAmount) * tubeMask;
  let display = acesToneMap(color * (0.95 + bass * 0.05) + vec3<f32>(0.92, 0.97, 1.0) * glare);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
