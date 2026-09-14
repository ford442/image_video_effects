// ═══════════════════════════════════════════════════════════════════
//  Metaball Soft Body
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Rayleigh droplet shape-oscillation modes (l=2,3, ω∝√(l(l−1)(l+2))) excited by bass/treble and click impulses; Rayleigh–Plateau varicose beading on stretched necks between merging bodies
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Ball Count, .y = Surface Roughness, .z = Metal Hue, .w = Caustic Strength
  ripples: array<vec4<f32>, 50>,
};

// Per-pixel precomputed body state (centres/radii/mode amplitudes depend only
// on time, audio, mouse and clicks — not on p — so they are evaluated once and
// reused by the three gradient taps).
var<private> g_center: array<vec2<f32>, 6>;
var<private> g_radius: array<f32, 6>;
var<private> g_mode2: array<f32, 6>;
var<private> g_mode3: array<f32, 6>;
var<private> g_phase: array<f32, 6>;

struct FieldInfo {
  f: f32,
  f1: f32,
  f2: f32,
  i1: i32,
  i2: i32,
};

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// Raw metaball field with Rayleigh shape modes, tracking the two dominant bodies.
fn fieldRaw(p: vec2<f32>, time: f32, nBalls: i32) -> FieldInfo {
  var info = FieldInfo(0.0, 0.0, 0.0, 0, 0);
  for (var i: i32 = 0; i < 6; i = i + 1) {
    if (i >= nBalls) { break; }
    let d = p - g_center[i];
    let d2 = dot(d, d);
    // IDEA 1: droplet shape oscillation. Capillary modes of a free drop ring at
    // ω_l ∝ √(l(l−1)(l+2)): l=2 (oblate/prolate squash) and l=3 (trefoil).
    let theta = atan2(d.y, d.x);
    let ph = g_phase[i];
    let w2 = 2.83 * 1.6;   // √8
    let w3 = 5.48 * 1.6;   // √30
    let shape = 1.0
      + g_mode2[i] * cos(2.0 * (theta - ph)) * cos(time * w2 + ph)
      + g_mode3[i] * cos(3.0 * (theta + ph * 1.7)) * cos(time * w3 + ph * 2.3);
    let r = g_radius[i] * shape;
    let c = (r * r) / (d2 + 0.00005);
    info.f = info.f + c;
    if (c > info.f1) {
      info.f2 = info.f1; info.i2 = info.i1;
      info.f1 = c; info.i1 = i;
    } else if (c > info.f2) {
      info.f2 = c; info.i2 = i;
    }
  }
  return info;
}

// IDEA 2: Rayleigh–Plateau beading. A liquid bridge between two bodies is
// unstable to varicose perturbations with wavelength ≈ 9.02 × neck radius; the
// growth switches on as the bridge is stretched (centre gap vs. radii).
fn neckBeading(p: vec2<f32>, info: FieldInfo, time: f32, mids: f32, nBalls: i32) -> f32 {
  if (nBalls < 2 || info.f2 <= 0.0) { return 0.0; }
  let c1 = g_center[info.i1];
  let c2 = g_center[info.i2];
  let axis = c2 - c1;
  let L = max(length(axis), 0.001);
  let a = axis / L;
  let along = dot(p - c1, a);
  let t = along / L;
  let perp = abs(dot(p - c1, vec2<f32>(-a.y, a.x)));
  let rMin = min(g_radius[info.i1], g_radius[info.i2]);
  let neckR = rMin * 0.35;
  let lambda = 9.02 * neckR;
  let stretch = L / max(g_radius[info.i1] + g_radius[info.i2], 0.001);
  let growth = smoothstep(1.2, 3.0, stretch);
  let bridge = clamp(info.f2 / max(info.f1, 0.0001), 0.0, 1.0);
  let window = smoothstep(0.1, 0.3, t) * smoothstep(0.9, 0.7, t) * exp(-perp * perp / (rMin * rMin * 1.5));
  return sin(along * 6.28318 / lambda - time * (1.5 + mids * 2.0)) * growth * bridge * window * (0.22 + mids * 0.25);
}

fn fieldAt(p: vec2<f32>, time: f32, mids: f32, nBalls: i32) -> vec2<f32> {
  let info = fieldRaw(p, time, nBalls);
  let bead = neckBeading(p, info, time, mids, nBalls);
  return vec2<f32>(info.f * (1.0 + bead), bead);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  // Bass envelope (relocated from per-pixel A.r into bounded extraBuffer[133]).
  var prevEnv = bass;
  let hasState = arrayLength(&extraBuffer) > 138u;
  if (hasState) { prevEnv = extraBuffer[133]; }
  let bassEnv = clamp(bass_env(prevEnv, bass, 0.8, 0.15), 0.0, 1.0);
  if (hasState && global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = bassEnv;
  }

  let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
  let prevState = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0);

  let nBalls = 3 + i32(u.zoom_params.x * 3.0);
  let roughness = u.zoom_params.y;
  let metalShift = u.zoom_params.z;
  let causticStr = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Video luma-keyed optical-flow distortion
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(inputColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let flow = (inputColor.rg - 0.5) * 0.05 * luma;
  p = p + flow;

  var mousePos = (mouseUV - 0.5) * 2.0;
  mousePos.x = mousePos.x * aspect;

  // Viscous damping of shape modes: rougher skin = more viscous body.
  let damping = 1.2 + roughness * 3.0;
  let rippleCount = min(u32(u.config.y), 50u);

  // Precompute body centres, radii and mode amplitudes.
  for (var i: i32 = 0; i < 6; i = i + 1) {
    let fi = f32(i);
    let seed = fi * 17.31;
    let orbitR = 0.2 + hash12(vec2<f32>(seed, 0.0)) * 0.25;
    let spd = 0.25 + hash12(vec2<f32>(seed, 1.0)) * 0.4 + bassEnv * 0.2;
    let phase = seed * 0.7 + time * spd;
    let cx = cos(phase) * orbitR + cos(time * 0.13 + fi) * 0.08;
    let cy = sin(phase * 0.83 + 1.3) * orbitR + sin(time * 0.11 + fi) * 0.08;
    let pos = vec2<f32>(cx, cy);
    let toMouse = mousePos - pos;
    let dist2 = dot(toMouse, toMouse) + 0.001;
    let grav = normalize(toMouse + vec2<f32>(0.0001)) * 0.06 / dist2;
    let mPos = pos + clamp(grav * (1.0 + mouseDown * 3.0), vec2<f32>(-0.6), vec2<f32>(0.6));
    g_center[i] = mPos;
    g_radius[i] = 0.1 + hash12(vec2<f32>(seed, 2.0)) * 0.06 + bassEnv * 0.04;
    g_phase[i] = hash12(vec2<f32>(seed, 3.0)) * 6.28318;

    // Click impulses: pressure wave from each click excites the nearby bodies.
    var impulse = 0.0;
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
      let rp = u.ripples[ri];
      let age = time - rp.z;
      if (age < 0.0 || age > 3.0) { continue; }
      var rc = (rp.xy - 0.5) * 2.0;
      rc.x = rc.x * aspect;
      let dd = length(mPos - rc);
      let arrival = smoothstep(dd * 1.1 - 0.05, dd * 1.1 + 0.05, age);
      impulse = impulse + arrival * exp(-(age - dd * 1.1) * damping) * exp(-dd * 1.5);
    }
    impulse = clamp(impulse, 0.0, 1.5);
    let visc = 1.0 / (1.0 + roughness * 1.5);
    g_mode2[i] = (0.03 + bassEnv * 0.14 + impulse * 0.28 + mouseDown * 0.05) * visc;
    g_mode3[i] = (treble * 0.09 + impulse * 0.16) * visc * visc;
  }

  // Mouse held shockwave + click pressure rings
  let clickDist = length(p - mousePos);
  var shockWave = mouseDown * exp(-clickDist * clickDist * 60.0) * sin(clickDist * 30.0 - time * 6.0);
  var rippleRing = 0.0;
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age < 0.0 || age > 2.5) { continue; }
    var rc = (rp.xy - 0.5) * 2.0;
    rc.x = rc.x * aspect;
    let rr = length(p - rc);
    rippleRing = rippleRing + exp(-pow(rr - age * 0.9, 2.0) * 90.0) * (1.0 - age / 2.5);
  }
  shockWave = shockWave + rippleRing * 0.6;

  let dx = 0.003;
  let fb = fieldAt(p, time, mids, nBalls);
  let f = fb.x;
  let bead = fb.y;
  let fx = fieldAt(p + vec2<f32>(dx, 0.0), time, mids, nBalls).x;
  let fy = fieldAt(p + vec2<f32>(0.0, dx), time, mids, nBalls).x;

  let grad = vec2<f32>(fx - f, fy - f) / dx;
  let gradLen = length(grad);
  let normal = grad / max(gradLen, 0.001);
  let view = normalize(vec2<f32>(0.0001, 0.0) - p);
  let fresnel = pow(1.0 - max(dot(normal, view), 0.0), 3.0);

  let surfaceDist = abs(f - 1.0);
  let surfaceMask = 1.0 - smoothstep(0.0, max(0.15 + shockWave * 0.08, 0.02), surfaceDist);
  let insideMask = step(1.0, f);

  let lightDir = normalize(vec2<f32>(0.5, 0.8));
  let spec = pow(max(dot(normal, normalize(lightDir + view)), 0.0), mix(32.0, 8.0, roughness));

  let baseMetal = mix(vec3<f32>(0.75, 0.78, 0.82), vec3<f32>(0.9, 0.7, 0.4), metalShift);
  let subSurf = vec3<f32>(0.9, 0.4, 0.2) * insideMask * 0.4;

  // Liquid-metal environment reflection of the input along the surface normal.
  let envUV = clamp(uv + normal * 0.04 * fresnel, vec2<f32>(0.0), vec2<f32>(1.0));
  let envCol = textureSampleLevel(readTexture, u_sampler, envUV, 0.0).rgb;

  let caustic = vec3<f32>(0.2, 0.6, 1.0) * gradLen * causticStr * 0.15 * (1.0 + mids * 0.4);
  let mergeGlow = vec3<f32>(1.0, 0.8, 0.5) * max(f - 1.5, 0.0) * 0.3;

  // Rayleigh–Plateau satellite glints: bead crests on a thinning neck.
  let beadGlint = max(bead, 0.0) * surfaceMask * 2.2;

  // Treble sparkle on surface
  let sparkle = hash12(uv * resolution + fract(time * 12.0) * 200.0);
  let trebleSpark = step(0.96 - treble * 0.1, sparkle) * treble * surfaceMask;

  var generatedColor = vec3<f32>(0.01, 0.01, 0.015);
  generatedColor = generatedColor + baseMetal * surfaceMask * 0.6;
  generatedColor = generatedColor + vec3<f32>(1.0, 0.95, 0.9) * spec * surfaceMask;
  generatedColor = generatedColor + mix(baseMetal, envCol * baseMetal * 1.5, 0.35) * fresnel * surfaceMask * 0.5;
  generatedColor = generatedColor + subSurf;
  generatedColor = generatedColor + caustic;
  generatedColor = generatedColor + mergeGlow;
  generatedColor = generatedColor + vec3<f32>(0.6, 0.85, 1.0) * beadGlint;
  generatedColor = generatedColor + vec3<f32>(0.5, 0.7, 0.9) * rippleRing * 0.25;
  generatedColor = generatedColor + vec3<f32>(0.9, 0.95, 1.0) * trebleSpark;

  generatedColor = acesToneMapping(generatedColor * (1.4 + bassEnv * 0.5));

  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  // Temporal feedback trail (display-space history from A via exact C load)
  let trail = mix(prevState.rgb * 0.88, generatedColor, 0.12 + mouseDown * 0.1);
  generatedColor = max(generatedColor, trail * 0.55);

  // Alpha = implicit-surface coverage (+ glints, click rings, trail persistence)
  let fieldAlpha = clamp(f * surfaceMask * 0.5 + surfaceMask * 0.3 + insideMask * 0.25 + trebleSpark + beadGlint * 0.3 + rippleRing * 0.15, 0.0, 0.95) * depth;
  let interaction = surfaceMask + mouseDown * 0.4 + trebleSpark * 2.0;
  let alpha = clamp(max(fieldAlpha * (1.0 + fresnel * 0.3) * (0.8 + interaction * 0.25), prevState.a * 0.5), 0.02, 1.0);

  let finalColor = vec4<f32>(generatedColor, alpha);
  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(max(surfaceMask, insideMask * 0.6) * depth, 0.0, 0.0, 0.0));
}
