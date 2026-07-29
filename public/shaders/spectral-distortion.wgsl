// ═══════════════════════════════════════════════════════════════════
//  Spectral Distortion
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, glitch, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Visualist upgrade: 2026-07-30 (Batch 18)
//    - Critically-damped spring trails the warp blob behind the cursor
//      (persistent center + velocity in extraBuffer[133..136]).
//    - Click warp bursts: each live ripple adds a decaying, expanding
//      radial warp impulse (~1.2s fade) that locally boosts warpStr.
//    - Per-channel spectral separation: R offset rides plasmaBuffer[3].x,
//      B offset rides plasmaBuffer[7].x so the chromatic tear shimmers
//      across the spectrum instead of one global split.
//  All per-pixel logic is branchless (select/step/smoothstep only).
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Separation, y=WarpScale, z=MouseInfluence, w=Speed
  ripples: array<vec4<f32>, 50>, // xy=click UV, z=click time, w=unused
};

fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn value_noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise(i + vec2<f32>(0.0, 0.0)),
                   noise(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(noise(i + vec2<f32>(0.0, 1.0)),
                   noise(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let rawMouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 0.001);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  // Different spectrum regions drive the per-channel chromatic tear.
  let binR = plasmaBuffer[3].x;
  let binB = plasmaBuffer[7].x;

  // Slider-driven constants (u.zoom_params.x/y/z/w).
  let separation = clamp(u.zoom_params.x * 0.1 * (1.0 + bass * 0.3), 0.0, 0.2);
  let warpScale = u.zoom_params.y * 20.0 + 1.0 + mids * 5.0;
  let mouseInf = u.zoom_params.z;
  let speed = u.zoom_params.w * 2.0;

  // ── Spring-damper influence center (extraBuffer[133..136]) ───────
  // Branchless mouse gate on the RAW mouse, evaluated before springing.
  let mouseActive = step(0.0, rawMouse.x);
  // Persistent spring state: center in [133..134], velocity in [135..136].
  // [0..4] reserved, [5..132] engine FFT — shader state lives at 133+ only.
  var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  // Branchless first-frames snap: untouched state jumps straight to target.
  let stateZero = 1.0 - step(0.0001, abs(springPos.x) + abs(springPos.y));
  // While the mouse is inactive, hold the last eased center as the target.
  let springTarget = mix(springPos, rawMouse, mouseActive);
  springPos = mix(springPos, springTarget, stateZero);
  // Critically damped spring (fixed 60 Hz step): trails with weight,
  // settles without overshoot. Every thread writes identical values.
  let springDt = 1.0 / 60.0;
  let springOmega = 2.0 * 3.14159265 * 3.0; // ~3 Hz settle frequency
  let springExp = exp(-springOmega * springDt);
  let springX = springPos - springTarget;
  let springTemp = (springVel + springOmega * springX) * springDt;
  springPos = springTarget + (springX + springTemp) * springExp;
  springVel = (springVel - springOmega * springTemp) * springExp;
  extraBuffer[133] = springPos.x;
  extraBuffer[134] = springPos.y;
  extraBuffer[135] = springVel.x;
  extraBuffer[136] = springVel.y;
  let mousePos = springPos;

  var warpStr = 0.02 + treble * 0.01;

  // Branchless mouse influence: sprung center + slider-widened radius.
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let influenceRadius = 0.15 + mouseInf * 0.3;
  let influence = 1.0 - smoothstep(0.0, influenceRadius, dist);
  warpStr += influence * mouseInf * 0.1 * mouseActive;
  // Holding the mouse button squeezes extra warp into the blob.
  warpStr += influence * u.zoom_config.w * 0.03 * mouseActive;

  // ── Click warp bursts ────────────────────────────────────────────
  // Each live ripple emits an expanding ring that locally boosts warpStr;
  // the envelope decays over ~1.2s. Fully branchless smoothstep bands.
  var clickBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let age = max(time - u.ripples[i].z, 0.0);
    let live = 1.0 - step(1.2, age);            // 1 inside ~1.2s window
    let fade = (1.0 - age / 1.2) * live;        // decaying envelope
    let ringRadius = age * 0.45;                // ring expands outward
    let rVec = uv - u.ripples[i].xy;
    let ringDist = length(vec2<f32>(rVec.x * aspect, rVec.y));
    let band = 1.0 - smoothstep(0.0, 0.08, abs(ringDist - ringRadius));
    clickBoost += band * fade * fade * 0.08;
  }
  warpStr += clickBoost;

  // Generate warp fields for R, G, B (field taps preserved verbatim).
  let t = time * speed;
  let nR = value_noise(uv * warpScale + vec2<f32>(t, t));
  let nG = value_noise(uv * warpScale + vec2<f32>(t + 10.0, -t));
  let nB = value_noise(uv * warpScale + vec2<f32>(-t, t + 5.0));

  // Per-channel bin separation: R and B ride different spectrum regions
  // so the chromatic tear shimmers with the audio, not one global split.
  let sepR = separation * (0.6 + binR * 0.8);
  let sepB = separation * (0.6 + binB * 0.8);

  let offR = vec2<f32>(nR - 0.5, value_noise(uv * warpScale + 100.0) - 0.5) * warpStr + vec2<f32>(sepR, 0.0);
  let offG = vec2<f32>(nG - 0.5, value_noise(uv * warpScale + 200.0) - 0.5) * warpStr;
  let offB = vec2<f32>(nB - 0.5, value_noise(uv * warpScale + 300.0) - 0.5) * warpStr - vec2<f32>(sepB, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + offG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Alpha: warp magnitude + chromatic separation + click bursts drive
  // the spectral effect weight.
  let warpMag = length(offR - offB);
  let luma = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(warpMag * 8.0 + separation * 6.0 + clickBoost * 4.0 + luma * 0.2, 0.0, 1.0);
  let finalColor = vec4<f32>(r, g, b, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor); // DISPLAY color
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
