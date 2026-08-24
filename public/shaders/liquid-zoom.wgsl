// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Zoom — Depth-Parallax Layer Stack
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, depth-parallax-layers, volumetric-fog,
//            chromatic-aberration, temporal-streaks, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════════════════
//  An endless zoom-through built from phase-offset copies of the plate, scaled
//  per pixel by scene depth so near content rushes past and far content drifts.
//  Two structures replace the original two hardcoded layers:
//
//    1. Four-layer parallax stack with audio-driven cadence — layers are evenly
//       phase-offset across the cycle and composited back-to-front by their own
//       parallax factor, so the seam between "the layer fading out" and "the
//       layer fading in" is always covered. Layer speed is modulated by the
//       eight FFT bins (each layer owns two bins), so the stack pulses through
//       the spectrum instead of running at one fixed rate. The old two-layer
//       version picked a "dominant" layer with a hard 0.5 threshold for the
//       depth write, which popped whenever the layers crossed.
//
//    2. Bounded click zoom pulses — each click briefly accelerates the local
//       zoom cadence inside an expanding ring and deposits a bright rim, so
//       clicking punches a burst of travel through the tunnel. Capped at 50
//       ripples and ~2.4 s.
//
//  Also fixed: the shader had NO bounds guard, never wrote dataTextureA, never
//  read audio, and its four sliders were labelled Intensity/Speed/Scale/Detail
//  in the JSON while the WGSL used them as foreground speed, background speed,
//  parallax strength and fog density. The WGSL mapping is authoritative and the
//  honest labels now live in the definition's updatedParams.
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
  zoom_params: vec4<f32>,  // x=NearSpeed, y=FarSpeed, z=ParallaxStrength, w=FogDensity
  ripples: array<vec4<f32>, 50>,
};

const LAYERS: u32 = 4u;
const ZOOM_INTENSITY: f32 = 4.0;
const FADE_DURATION: f32 = 0.3;

fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Fog thickens with distance and desaturates as the layer rushes past.
fn applyFog(layerColor: vec3<f32>, fogAmount: f32, zoomProgress: f32) -> vec3<f32> {
  let fogColor = vec3<f32>(0.05, 0.10, 0.08);
  let avg = dot(layerColor, vec3<f32>(1.0 / 3.0));
  let saturation = 1.0 - zoomProgress * 0.1;
  let desaturated = mix(vec3<f32>(avg), layerColor, saturation);
  return mix(desaturated, fogColor, fogAmount);
}

struct Layer {
  color: vec3<f32>,
  alpha: f32,
  progress: f32,
};

fn sampleLayer(
  uv: vec2<f32>,
  zoomCenter: vec2<f32>,
  parallaxFactor: f32,
  perPixelSpeed: f32,
  fogDensity: f32,
  zoomTime: f32,
  cycleOffset: f32,
  chroma: f32
) -> Layer {
  let progress = fract(zoomTime * perPixelSpeed + cycleOffset);
  let scale = 1.0 + progress * ZOOM_INTENSITY * parallaxFactor;
  let repeatingUV = (uv - zoomCenter) / scale + zoomCenter;
  let wrapped = ping_pong_v2(repeatingUV);

  // Radial chromatic split — the tunnel disperses toward its rim.
  let radial = (wrapped - zoomCenter) * chroma;
  let cR = textureSampleLevel(readTexture, non_filtering_sampler, ping_pong_v2(wrapped + radial), 0.0).r;
  let cG = textureSampleLevel(readTexture, non_filtering_sampler, wrapped, 0.0);
  let cB = textureSampleLevel(readTexture, non_filtering_sampler, ping_pong_v2(wrapped - radial), 0.0).b;

  let fadeIn = smoothstep(0.0, FADE_DURATION, progress);
  let fadeOut = 1.0 - smoothstep(1.0 - FADE_DURATION, 1.0, progress);

  // Distance fog, then the Fresnel-tempered layer opacity.
  let fogAmount = pow(1.0 - parallaxFactor, 2.0) * fogDensity;
  let color = applyFog(vec3<f32>(cR, cG.g, cB), fogAmount, progress);

  let fresnel = schlickFresnel(0.8, 0.02);
  var alpha = fadeIn * fadeOut;
  // Far background must not pulse with the zoom cycle.
  alpha = mix(alpha, 1.0, 1.0 - smoothstep(0.0, 0.1, parallaxFactor));
  alpha = mix(alpha, 0.3, fogAmount) * (1.0 - fresnel * 0.15);

  var out: Layer;
  out.color = color;
  out.alpha = clamp(alpha, 0.0, 1.0);
  out.progress = progress;
  return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dimsI);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let zoomTime = u.zoom_config.x;
  let zoomCenter = u.zoom_config.yz;
  let held = step(0.5, u.zoom_config.w);

  // ── Params ───────────────────────────────────────────────────────────────
  let nearSpeed = u.zoom_params.x;
  let farSpeed = u.zoom_params.y;
  let parallaxStrength = u.zoom_params.z;
  let fogDensity = u.zoom_params.w;

  let staticDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  // Depth 0 = near. parallaxFactor 1 = near, 0 = far.
  let parallaxFactor = pow(1.0 - staticDepth, max(parallaxStrength, 0.001));

  // ── Structure 2: bounded click zoom pulses ───────────────────────────────
  var pulseBoost = 0.0;
  var rimGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.4) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let front = r - age * 0.6;
      let env = exp(-front * front * 130.0) * exp(-age * 1.4);
      pulseBoost += env;
      rimGlow += env * env;
    }
  }
  pulseBoost = min(pulseBoost, 1.5);
  rimGlow = min(rimGlow, 1.2);

  // Held pointer accelerates travel near the cursor.
  let mDist = length((uv - zoomCenter) * vec2<f32>(aspect, 1.0));
  let pointerBoost = held * exp(-mDist * mDist * 8.0);

  let basePixelSpeed = mix(farSpeed, nearSpeed, parallaxFactor);
  let chroma = (0.0008 + treble * 0.0035) * (1.0 + pulseBoost);

  // ── Structure 1: four-layer stack, each owning two FFT bins ──────────────
  var color = vec3<f32>(0.0);
  var coverage = 0.0;
  var alphaAccum = 0.0;
  var nearestProgress = 0.0;
  var nearestWeight = -1.0;

  for (var k = 0u; k < LAYERS; k = k + 1u) {
    let fk = f32(k);
    let band = (plasmaBuffer[k * 2u + 1u].x + plasmaBuffer[k * 2u + 2u].x) * 0.5;
    let speed = basePixelSpeed * (1.0 + band * 0.5 + bass * 0.25)
              + pulseBoost * 0.35 + pointerBoost * 0.25;
    let layer = sampleLayer(uv, zoomCenter, parallaxFactor, speed, fogDensity,
                            zoomTime, fk / f32(LAYERS), chroma);

    // Back-to-front over-compositing: later (nearer) layers cover earlier ones.
    let w = layer.alpha * (1.0 - coverage);
    color += layer.color * w;
    coverage += w;
    alphaAccum = max(alphaAccum, layer.alpha);

    // Track the layer contributing most here — drives the depth write, with
    // no hard threshold to pop across.
    if (w > nearestWeight) {
      nearestWeight = w;
      nearestProgress = layer.progress;
    }
  }

  // Any uncovered remainder falls back to the undistorted plate.
  let plate = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  color += plate.rgb * (1.0 - coverage);

  color += vec3<f32>(0.55, 0.85, 1.0) * rimGlow * (0.4 + mids * 0.6);
  color += vec3<f32>(0.30, 0.55, 0.85) * pointerBoost * 0.2;

  // ── Temporal streaks: the tunnel leaves motion trails ────────────────────
  let prev = textureLoad(dataTextureC, coord, 0);
  color = max(color, prev.rgb * (0.72 + parallaxFactor * 0.16));

  color = acesFilm(color);

  // ── Semantic alpha ───────────────────────────────────────────────────────
  let alpha = clamp(mix(plate.a, 1.0, clamp(coverage, 0.0, 1.0)) * alphaAccum
                    + rimGlow * 0.25, 0.0, 1.0);
  let outColor = vec4<f32>(color, alpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  // ── Depth follows the dominant layer's transform ─────────────────────────
  let scale = 1.0 + nearestProgress * ZOOM_INTENSITY * parallaxFactor;
  let transformedUV = (uv - zoomCenter) / scale + zoomCenter;
  let newDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
                                    ping_pong_v2(transformedUV), 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(newDepth, 0.0, 0.0, 0.0));
}
