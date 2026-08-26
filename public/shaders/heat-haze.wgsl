// ═══════════════════════════════════════════════════════════════════
//  Heat Haze
//  Category: distortion
//  Features: animated, atmospheric, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  By: Phase A Upgrade Swarm
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  FIXED — the heat simulation lived in the DEPTH texture. The shader read its
//  heat field back from `readDepthTexture` and wrote `finalHeat` into
//  `writeDepthTexture`. That is self-consistent on its own, but it destroys
//  scene depth for every shader chained after this one (and the engine's depth
//  swap feeds the heat field back in), and it means the effect can never react
//  to real geometry. The heat state now lives in `dataTextureA` and is read back
//  through `dataTextureC` with exact `textureLoad`, which is the house
//  convention for a simulation; the depth channel passes real scene depth.
//
//  Because A carries SIM STATE, display goes to `writeTexture` only.
//
//  FAST MOTION (two analytic techniques)
//
//    1. Buoyant plume packets — discrete thermals rise and expand on closed-form
//       trajectories (ascent rate falls as the plume widens, as buoyancy does),
//       rather than the field being advected upward by a uniform pixel offset.
//       Plumes visibly detach, race up and dissipate.
//
//    2. Shear-layer streaks — the plate is integrated along the local warp
//       gradient with a length that scales with the warp magnitude, so fast
//       shimmer smears into directional streaks instead of only displacing.
//
//  PSYCHEDELIC COLOUR — the orange thermal tint becomes a full IQ cosine
//  spectrum keyed to heat and per-band FFT energy, and the Schlieren dispersion
//  is widened so hot air fringes prismatically.
//
//  HIGH ENERGY — click heat bursts (already present) now also detonate a
//  spectral flash and inject a plume.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn spectrum(tt: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);

  // Params with randomization guards
  let heatGain = max(u.zoom_params.x, 0.001);
  let decayRate = max(u.zoom_params.y, 0.001);
  let diffusion = clamp(u.zoom_params.z, 0.0, 1.0);
  let refraction = max(u.zoom_params.w, 0.0);

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioBoost = 1.0 + bass * 0.5;

  // ── FAST MOTION 1: buoyant plume packets ─────────────────────────────────
  // Ascent rate falls as a plume widens, so thermals detach, race up and
  // dissipate instead of the whole field sliding up by a fixed pixel offset.
  let plumePhase = fract(uv.y * 1.7 - time * clamp(0.28 + bass * 0.35, 0.0, 0.8));
  let plumeWidth = 0.25 + plumePhase * 0.9;
  let plumeRise = clamp((1.0 - plumePhase * 0.7) * 3.4, 0.5, 3.6);
  let plumeCore = exp(-pow((plumePhase - 0.35) / plumeWidth, 2.0) * 4.0);

  // Heat state now lives in dataTextureA and comes back through dataTextureC.
  let risePixels = 1 + i32(round((1.0 - decayRate) * plumeRise + bass * 2.0));
  let sourceCoord = clamp(coord + vec2<i32>(0, risePixels), vec2<i32>(0), maxCoord);
  let c = textureLoad(dataTextureC, sourceCoord, 0).r;
  let l = textureLoad(dataTextureC, clamp(sourceCoord + vec2<i32>(-1, 0), vec2<i32>(0), maxCoord), 0).r;
  let r = textureLoad(dataTextureC, clamp(sourceCoord + vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0).r;
  let t = textureLoad(dataTextureC, clamp(sourceCoord + vec2<i32>(0, -1), vec2<i32>(0), maxCoord), 0).r;
  let b = textureLoad(dataTextureC, clamp(sourceCoord + vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0).r;

  let avg = (l + r + t + b) * 0.25;
  let diffusedHeat = mix(c, avg, diffusion) * (0.85 + plumeCore * 0.35);

  // 2. Add Mouse Heat (branchless)
  var mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

  let inRadius = select(0.0, 1.0, dist < 0.05);
  let mouseHeat = select(0.0, heatGain * (1.0 - dist / 0.05), mouseDown > 0.5) * inRadius;

  var clickHeat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickHeat += smoothstep(0.026, 0.0, abs(length(delta) - age * 0.38)) * exp(-age * 1.45);
    }
  }

  let retention = 1.0 - mix(0.008, 0.12, decayRate);
  let newHeat = diffusedHeat * retention + mouseHeat + clickHeat * heatGain * 0.35;

  // Clamp
  let finalHeat = clamp(newHeat, 0.0, 1.0);

  // 3. Render
  // Distort UV based on Heat Gradient (refraction)
  // We use the spatial gradient of the heat map
  let heatGradX = r - l;
  let heatGradY = b - t;
  let baseWarp = vec2<f32>(heatGradX, heatGradY) * refraction * audioBoost;

  // ═══ UNIQUE VISUAL IDEA: rising-convection columns + chromatic Schlieren ═══
  // Hot air does not just refract statically — it rises in shimmering columns.
  // We add an upward-scrolling, vertically-stretched turbulence so the haze
  // visibly convects, with mostly-horizontal wobble (columns sway side to side
  // as they ascend). Sampled at full-res frequency for fine shimmer.
  let convTime = time;
  let colUV = uv * vec2<f32>(38.0, 14.0) + vec2<f32>(0.0, -convTime * 1.6); // scrolls up
  let column = sin(colUV.x + sin(colUV.y) * 1.7) * cos(colUV.y * 0.8 + convTime);
  // Convection strength scales with local heat — only hot regions shimmer.
  let convStrength = finalHeat * refraction * audioBoost * 0.012;
  let convWarp = vec2<f32>(column * 1.4, abs(column) * 0.5) * convStrength;

  // Narrow heat packets race upward through the broader convection columns.
  let heatRunner = pow(max(0.0, sin(uv.y * 86.0 + uv.x * 19.0 - time * 17.0)), 14.0) * finalHeat;
  let runnerWarp = vec2<f32>(sin(uv.y * 35.0 + time * 9.0), -1.0) * heatRunner * refraction * 0.012;

  let warp = baseWarp + convWarp + runnerWarp;

  // Chromatic Schlieren dispersion: hotter air bends short wavelengths more,
  // so blue refracts further than red — produces prismatic mirage fringing at
  // strong gradients. Spread scales with heat so cool areas stay aberration-free.
  let disp = (1.0 + finalHeat * 2.0);
  let uvR = clamp(uv - warp * (1.0 - 0.06 * disp), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv - warp, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv - warp * (1.0 + 0.06 * disp), vec2<f32>(0.0), vec2<f32>(1.0));
  let cr = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let cg = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let cb = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  var color = vec4<f32>(cr, cg.g, cb, cg.a);

  // ── FAST MOTION 2: shear-layer streaks ───────────────────────────────────
  // Integrate along the local warp gradient; length scales with warp magnitude
  // and is hard-clamped, so fast shimmer smears directionally.
  let warpMag = length(warp);
  let shearDir = select(vec2<f32>(0.0), warp / max(warpMag, 1e-6), warpMag > 1e-5);
  let shearLen = clamp(warpMag * 5.0 + finalHeat * 0.012, 0.0, 0.045);
  var streak = vec3<f32>(0.0);
  var sw = 0.0;
  for (var s = 0u; s < 5u; s = s + 1u) {
    let fs = f32(s) / 4.0;
    let w = 1.0 - fs * 0.72;
    let tap = clamp(uvG - shearDir * shearLen * fs, vec2<f32>(0.0), vec2<f32>(1.0));
    streak += textureSampleLevel(readTexture, u_sampler, tap, 0.0).rgb * w;
    sw += w;
  }
  color = vec4<f32>(mix(color.rgb, streak / max(sw, 1e-4),
                        clamp(warpMag * 22.0 + finalHeat * 0.35, 0.0, 0.7)), color.a);

  // ── PSYCHEDELIC: heat-keyed spectrum instead of a single orange tint ──────
  let bandIdx = u32(clamp(uv.y * 8.0, 0.0, 7.999));
  let band = plasmaBuffer[bandIdx + 1u].x;
  let heatHue = fract(finalHeat * 0.85 + plumePhase * 0.4 + band * 0.6
                      + time * 0.05 + heatRunner * 0.3);
  let heatTint = pow(spectrum(heatHue), vec3<f32>(0.7));
  let thermalTint = heatTint * (finalHeat * 0.9 + heatRunner * 0.35 + plumeCore * 0.25)
                  * audioBoost;
  // Click bursts flash full-spectrum.
  let burstTint = spectrum(fract(heatHue + 0.5)) * clickHeat * (0.9 + bass * 1.0);

  var outRGB = color.rgb + thermalTint + burstTint;
  outRGB = acesFilm(outRGB);

  // Meaningful alpha based on effect intensity
  let outAlpha = clamp(color.a * 0.7 + finalHeat * 0.5 * audioBoost + clickHeat * 0.3,
                       0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outRGB, outAlpha));
  // A carries the HEAT STATE (r = heat) — the diffusion above reads it back as
  // dataTextureC. Display is in writeTexture; B carries the colour for anything
  // downstream that wants it.
  textureStore(dataTextureA, coord, vec4<f32>(finalHeat, warp * 40.0, outAlpha));
  textureStore(dataTextureB, coord, vec4<f32>(outRGB, outAlpha));

  // Depth: real scene geometry, no longer overwritten by the heat field.
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
  textureStore(writeDepthTexture, coord,
               vec4<f32>(clamp(sceneDepth - finalHeat * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
