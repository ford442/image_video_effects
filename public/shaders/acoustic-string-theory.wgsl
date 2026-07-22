// ═══════════════════════════════════════════════════════════════════
//  Acoustic String Theory
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, feedback-loop,
//            gravity-well, spring-damper, pluck-on-click, spectrum-drive,
//            shockwave, video-luma, sparkle
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
//  Interactivist pass: 2026-07-22 (pluck excitation, spring well, band weights)
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

// extraBuffer state map (indices 0..4 reserved by the engine):
//   [5]  previous mouse-down level (rising-edge pluck detector)
//   [6]  spring-damper well position x
//   [7]  spring-damper well position y
//   [8]  spring-damper well velocity x
//   [9]  spring-damper well velocity y
//   [10] last pluck start time
//   [11] last pluck x (aspect-corrected string space)
//   [12] last pluck y (string space)
//   [13] last pluck strength

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let dist2 = dot(d, d) + 0.01;
  return normalize(d) * strength / dist2;
}

// Spectral weight: which audio band excites string at normalized index t01.
// Low strings answer the bass, middle strings the mids, high strings the treble.
fn bandWeight(t01: f32, bass: f32, mids: f32, treble: f32) -> f32 {
  let bw = bass * exp(-pow((t01 - 0.12) * 2.4, 2.0));
  let mw = mids * exp(-pow((t01 - 0.50) * 2.8, 2.0));
  let tw = treble * exp(-pow((t01 - 0.88) * 2.4, 2.0));
  return bw + mw + tw;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let dt = clamp(u.config.y, 0.001, 0.05);
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bass = bass_env(prev.r, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w;

  let strings = mix(2.0, 16.0, u.zoom_params.x);
  let tension = mix(0.5, 5.0, u.zoom_params.y);
  let harmonics = mix(1.0, 8.0, u.zoom_params.z);
  let resonance = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);

  // ── Interactive state (single-writer thread, read by all) ─────────
  let hasState = arrayLength(&extraBuffer) > 141u;
  var wellPos = vec2<f32>(mouse.x * aspect, mouse.y);
  var pluckTime = -100.0;
  var pluckX = 0.0;
  var pluckY = 0.0;
  var pluckAmp = 0.0;
  if (hasState) {
    wellPos = vec2<f32>(extraBuffer[134], extraBuffer[135]);
    pluckTime = extraBuffer[138];
    pluckX = extraBuffer[139];
    pluckY = extraBuffer[140];
    pluckAmp = extraBuffer[141];
  }
  if (gid.x == 0u && gid.y == 0u && hasState) {
    // Spring-damper: the gravity well chases the mouse with damped overshoot.
    let targetPos = vec2<f32>(mouse.x * aspect, mouse.y);
    let stiff = 42.0;
    let damping = 7.0;
    var wPos = vec2<f32>(extraBuffer[134], extraBuffer[135]);
    var wVel = vec2<f32>(extraBuffer[136], extraBuffer[137]);
    let accel = (targetPos - wPos) * stiff - wVel * damping;
    wVel = wVel + accel * dt;
    wPos = wPos + wVel * dt;
    extraBuffer[134] = wPos.x;
    extraBuffer[135] = wPos.y;
    extraBuffer[136] = wVel.x;
    extraBuffer[137] = wVel.y;
    // Rising-edge pluck: a click excites the nearest string, it does not glow.
    let prevDown = extraBuffer[133];
    if (mouseDown > 0.5 && prevDown <= 0.5) {
      extraBuffer[138] = time;
      extraBuffer[139] = targetPos.x;
      extraBuffer[140] = targetPos.y;
      extraBuffer[141] = 1.0;
    }
    extraBuffer[133] = mouseDown;
  }

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Spring-following gravity well bends string space
  let well = gravityWell(p, wellPos, 0.08 + bass * 0.06);
  p = p + well;

  // Click shockwave ripple
  let mDist = length(p - wellPos);
  let shock = exp(-mDist * 4.0) * mouseDown * sin(mDist * 25.0 - time * 10.0);

  // Video luma feedback boosts brightness
  let vid = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(vid, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = smoothstep(0.5, 1.0, luma) * 0.4;

  // Pluck envelope: gaussian strike that rings down faster under high tension.
  let pluckAge = max(time - pluckTime, 0.0);
  let pluckDecay = exp(-pluckAge * (1.2 + tension * 1.6));
  let pluckEnv = pluckAmp * pluckDecay;
  let pluckGauss = exp(-pow((p.x - pluckX) * 3.0, 2.0));

  var stringField = 0.0;
  var harmonicField = 0.0;
  var nodeField = 0.0;

  for (var s = 0u; s < u32(strings); s = s + 1u) {
    let fs = f32(s);
    let sy = -0.9 + (fs + 0.5) / strings * 1.8;
    let t01 = fs / max(strings - 1.0, 1.0);
    // Audio spectrum drive: each string's loudness tracks its band.
    let specAmp = 1.0 + bandWeight(t01, bass, mids, treble) * 0.55;
    // Pluck excitation: gaussian displacement centered on the struck string.
    let struck = exp(-pow((sy - pluckY) * 4.0, 2.0));
    let ring = sin(p.x * tension * 8.0 - pluckAge * (6.0 + fs * 0.7));
    let excite = pluckEnv * struck * pluckGauss * ring;
    let pluck = sin(p.x * tension * (1.0 + fs * 0.15) - time * (2.0 + fs * 0.5) * (1.0 + bass * 0.5));
    let damp = exp(-abs(p.x - wellPos.x * 0.5) * 2.0) * (0.5 + mids);
    let wave = sin((p.y - sy + shock * 0.15 + excite * 0.35) * tension * 15.0) * exp(-abs(p.y - sy) * tension * 3.0);
    let amp = (0.15 + damp + abs(excite) * 0.8) * resonance * (1.0 + bass * 0.3) * specAmp;
    let stringLine = abs(wave + pluck * amp);
    stringField = stringField + smoothstep(0.05, 0.0, stringLine) * (0.7 + fs * 0.05) * specAmp;

    // Harmonic rolloff brightens with tension (stiffer string = richer overtones).
    let rolloff = mix(0.68, 0.5, sat(tension / 5.0));
    for (var h = 1u; h < u32(harmonics); h = h + 1u) {
      let fh = f32(h);
      let harmY = sy + sin(fh * 1.618) * 0.15 + excite * 0.1;
      let harmWave = sin((p.y - harmY) * tension * 15.0 * fh) * exp(-abs(p.y - harmY) * tension * 5.0);
      let harmLine = abs(harmWave + pluck * amp * pow(rolloff, fh));
      harmonicField = harmonicField + smoothstep(0.03, 0.0, harmLine) * 0.3 * specAmp;
    }

    let nodeX = sin(fs * 2.7 + time * 0.3) * 0.5 + well.x * 0.5;
    let nodeDist = length(p - vec2<f32>(nodeX, sy));
    nodeField = nodeField + exp(-nodeDist * nodeDist * 80.0) * (0.5 + treble + pluckEnv * struck * 0.8);
  }

  // Treble sparkle on nodes
  let sparkle = step(0.88, hash21(uv * 150.0 + time * 10.0)) * treble * nodeField * 3.0;
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;
  let ao = exp(-depthSample * 3.0);

  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.9, 0.55, 0.2) * stringField * resonance * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.25, 0.75, 0.95) * harmonicField * (1.0 + mids * 0.2);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * nodeField * (0.5 + treble * 0.3);
  color = color + vec3<f32>(1.0, 0.9, 0.7) * sparkle;
  color = color + vec3<f32>(0.95, 0.8, 0.5) * pluckEnv * pluckGauss * 0.35;

  // Temporal accumulation with bass-reactive feedback; resonance sets sustain.
  let sustain = mix(0.90, 0.965, sat(resonance / 1.5));
  var accum = mix(color, prev.rgb * sustain, 0.03 + bass * 0.015);
  // Clamp the feedback loop pre-tint at ~1.2 (luma-echo-warp lesson).
  accum = min(accum, vec3<f32>(1.2));
  color = accum * (1.0 + lumaBoost) * (0.6 + 0.4 * ao);

  let presence = sat(stringField * 0.85 + harmonicField * 0.6 + nodeField * 0.9);
  let mouseProx = exp(-mDist * 2.0);
  let alpha = sat(0.08 + presence * 0.65 + mouseProx * 0.2 + bass * 0.12);
  let trailAge = prev.a * 0.96;
  let finalAlpha = max(alpha, trailAge * 0.6);

  let depth = sat(0.92 - stringField * 0.5 - nodeField * 0.3);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(bass, harmonicField, nodeField, finalAlpha));
}
