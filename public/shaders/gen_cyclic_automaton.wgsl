// ═══════════════════════════════════════════════════════════════════
//  Greenberg-Hastings Excitable Automaton
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, mouse-driven, temporal
//  Complexity: Medium
//  Scientific: Greenberg-Hastings excitable media with cardinal-wave triggering, refractory cooling, and bass-driven spontaneous ignition
//  Upgraded: 2026-08-23 — finite click ignition rings, wavefront tracer,
//            treble sparks, directional held-mouse painting
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// extraBuffer layout (shader-owned [133..138] only):
//   spring mouse xy, velocity xy, lastTime, initialized

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn decodeState(v: f32, numStates: i32) -> i32 {
  return clamp(i32(floor(v * f32(numStates) + 0.5)), 0, numStates - 1);
}

fn loadState(coord: vec2<i32>, size: vec2<i32>, numStates: i32) -> i32 {
  return decodeState(textureLoad(dataTextureC, clampCoord(coord, size), 0).r, numStates);
}

// Normalized refractory progress of a neighbor state (0.0 for resting/firing cells).
fn refractoryProgressOf(state: i32, numStates: i32) -> f32 {
  let progress = clamp(f32(max(state - 2, 0)) / max(1.0, f32(numStates - 2)), 0.0, 1.0);
  return progress * select(0.0, 1.0, state >= 2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let size = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x * 6.5; // Fast motion upgrade

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Slider wiring (saved-preset contract: ids/defaults unchanged) ──
  let numStates = i32(round(mix(4.0, 24.0, u.zoom_params.x)));      // States: automaton depth
  let spontaneousBase = mix(0.0001, 0.012, u.zoom_params.y);        // Spontaneity: ignition probability
  let bloomStrength = mix(0.15, 0.8, u.zoom_params.z);              // Bloom: neighbor glow + tracer gain
  let cooldownCurve = mix(1.7, 0.55, u.zoom_params.w);              // Cooldown: refractory tail persistence
  let cooldownBoost = mix(0.85, 1.25, u.zoom_params.w);             // Cooldown: cooling color ramp

  let currentState = loadState(coord, size, numStates);
  let n = loadState(coord + vec2<i32>(0, -1), size, numStates);
  let s = loadState(coord + vec2<i32>(0, 1), size, numStates);
  let e = loadState(coord + vec2<i32>(1, 0), size, numStates);
  let w = loadState(coord + vec2<i32>(-1, 0), size, numStates);
  let ne = loadState(coord + vec2<i32>(1, -1), size, numStates);
  let nw = loadState(coord + vec2<i32>(-1, -1), size, numStates);
  let se = loadState(coord + vec2<i32>(1, 1), size, numStates);
  let sw = loadState(coord + vec2<i32>(-1, 1), size, numStates);

  let cardFiring = select(0, 1, n == 1) + select(0, 1, s == 1) + select(0, 1, e == 1) + select(0, 1, w == 1);
  let allFiring = cardFiring + select(0, 1, ne == 1) + select(0, 1, nw == 1) + select(0, 1, se == 1) + select(0, 1, sw == 1);

  // ── Directional mouse painting ───────────────────────────────────
  // Compare the current mouse against the previous frame (extraBuffer[133..135])
  // and stretch the ignition footprint along the drag direction, so strokes
  // seed cardiac-style wavefronts instead of radial blobs.
  let mouseRaw = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var mouse = mouseRaw; var springVel = vec2<f32>(0.0); var lastTime = u.config.x; var initialized = false;
  if (hasSpring) { mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { mouse = mouseRaw; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(u.config.x - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = mouse - mouseRaw; let temp = (springVel + omega * sdelta) * dt;
  springVel = (springVel - omega * temp) * springDecay; mouse = mouseRaw + (sdelta + temp) * springDecay;
  if (hasSpring && coord.x == 0 && coord.y == 0) {
    extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = u.config.x; extraBuffer[138] = 1.0;
  }
  let mouseDown = u.zoom_config.w;
  let mouseDelta = springVel;
  let mouseSpeed = length(mouseDelta);
  let motionDir = mouseDelta / max(mouseSpeed, 1e-4);
  let toPixel = uv - mouse;
  let pixelDist = length(toPixel);
  let pixelDir = toPixel / max(pixelDist, 1e-4);
  let motionGain = clamp(mouseSpeed * 45.0, 0.0, 1.0);
  let align = dot(pixelDir, motionDir) * 0.5 + 0.5;
  let dirWeight = mix(1.0, mix(0.18, 1.0, align * align), motionGain);
  let held = select(1.0, 1.4, mouseDown > 0.5);
  let mouseMask = (1.0 - smoothstep(0.0, 0.13 * held, pixelDist)) * mouseDown * dirWeight;

  // Clicks launch finite ignition rings. Timestamps are honored so a full
  // uniform array cannot become a permanent source of automaton energy.
  var clickIgnition = 0.0;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = u.config.x - ripple.z;
    if (age < 0.0 || age > 2.2) { continue; }
    let rippleDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let ring = exp(-abs(rippleDistance - age * 0.22) * 85.0) * exp(-age * 1.1);
    clickIgnition = max(clickIgnition, ring);
  }

  // ── Ignition sources ─────────────────────────────────────────────
  let rand = hash21(vec2<f32>(f32(coord.x), f32(coord.y)) + vec2<f32>(time * 31.1, time * 17.3));
  let spontaneousProb = spontaneousBase * (0.2 + bass * 4.2);
  // Treble ignition sparks: a fine, fast hash-noise pattern gated by hi-hat
  // energy seeds new wave centers scattered across the field.
  let sparkHash = hash21(vec2<f32>(f32(coord.x), f32(coord.y)) * 1.618 + vec2<f32>(time * 113.7, -time * 91.3));
  let trebleSparkProb = spontaneousBase * treble * 9.0 * smoothstep(0.35, 0.95, sparkHash);
  let trebleSpark = sparkHash > 1.0 - clamp(trebleSparkProb, 0.0, 0.9);
  let ignite = (cardFiring > 0) || (rand < spontaneousProb) || trebleSpark
    || (mouseMask > 0.02) || (clickIgnition > 0.28);

  // ── Greenberg-Hastings state machine (resting=0, firing=1, refractory>=2) ──
  let isResting = currentState == 0;
  let isFiring = currentState == 1;
  let isRefractory = currentState >= 2;
  let refractoryNext = select(currentState + 1, 0, currentState >= numStates - 1);

  var nextState = currentState;
  nextState = select(nextState, 1, isResting && ignite);
  nextState = select(nextState, 2, isFiring);
  nextState = select(nextState, refractoryNext, isRefractory);

  let firingMask = select(0.0, 1.0, nextState == 1);
  let refractoryMask = select(0.0, 1.0, nextState >= 2);
  let refractoryProgress = clamp(f32(max(nextState - 2, 0)) / max(1.0, f32(numStates - 2)), 0.0, 1.0);
  let neighborGlow = f32(allFiring) / 8.0;
  let bloom = neighborGlow * bloomStrength;

  // ── Wavefront leading-edge tracer ────────────────────────────────
  // The refractoryProgress gradient across the cardinal neighborhood marks
  // where the wave just passed: a firing cell backed by a cooling trail sits
  // on the leading edge. Render a thin bright ring there for legibility.
  let rpN = refractoryProgressOf(n, numStates);
  let rpS = refractoryProgressOf(s, numStates);
  let rpE = refractoryProgressOf(e, numStates);
  let rpW = refractoryProgressOf(w, numStates);
  let trailMax = max(max(rpN, rpS), max(rpE, rpW));
  let trailMin = min(min(rpN, rpS), min(rpE, rpW));
  let trailGradient = clamp(trailMax - trailMin, 0.0, 1.0);
  let leadingEdge = firingMask * smoothstep(0.03, 0.28, trailMax) * (0.45 + 0.55 * trailGradient);
  let earlyRefr = refractoryMask * (1.0 - smoothstep(0.0, 0.14, refractoryProgress)) * smoothstep(0.03, 0.22, trailMax);
  let tracer = clamp(leadingEdge + earlyRefr * 0.6, 0.0, 1.0);

  // ── Coloring ─────────────────────────────────────────────────────
  let rpCurve = pow(refractoryProgress, cooldownCurve);
  let restColor = vec3<f32>(0.04, 0.01, 0.12) + vec3<f32>(0.18, 0.08, 0.42) * bloom * 0.22;
  let firingColor = mix(vec3<f32>(1.0, 0.2, 0.85), vec3<f32>(0.2, 1.0, 0.95), smoothstep(0.4, 1.0, bass + mouseMask));
  let refractoryColor = mix(vec3<f32>(0.95, 0.85, 0.12), vec3<f32>(0.12, 0.05, 0.55), clamp(rpCurve * cooldownBoost, 0.0, 1.0));
  let tracerColor = mix(vec3<f32>(1.0, 0.35, 0.95), vec3<f32>(0.25, 1.0, 0.85), treble * 0.45);

  var generatedColor = mix(restColor, refractoryColor, refractoryMask);
  generatedColor = mix(generatedColor, firingColor, firingMask);
  generatedColor += vec3<f32>(1.0, 0.96, 0.72) * bloom * 0.4;
  generatedColor += vec3<f32>(0.16, 0.44, 1.0) * bloom * (1.0 - firingMask) * 0.28;
  generatedColor += vec3<f32>(0.08, 0.12, 0.22) * smoothstep(0.2, 1.0, mids) * (1.0 - refractoryMask) * 0.15;
  generatedColor += tracerColor * tracer * (0.55 + bloomStrength * 0.9);
  generatedColor += vec3<f32>(0.9, 0.95, 1.0) * select(0.0, 1.0, trebleSpark) * 0.35 * (1.0 - firingMask);
  generatedColor += vec3<f32>(0.22, 0.75, 1.0) * clickIgnition * (0.25 + mids * 0.35);

  let opacity = 0.92;
  let finalColor = mix(inputColor.rgb, generatedColor, opacity);
  let finalAlpha = max(inputColor.a, 0.85 + max(firingMask, tracer * 0.5) * 0.15);
  let depthSignal = max(max(firingMask, tracer * 0.8), (1.0 - refractoryProgress) * refractoryMask);
  let finalDepth = mix(inputDepth, clamp(0.16 + depthSignal * 0.72 + bloom * 0.22 + treble * 0.06, 0.0, 1.0), 0.88);

  let caStr = 0.003 * (1.0 + bass) + finalDepth * 0.001;
  let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(acesToneMap(chromaticColor * 1.1), finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(f32(nextState) / f32(numStates), firingMask, refractoryProgress, bloom));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
