// ═══════════════════════════════════════════════════════════════════
//  Magnetic Kelp
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: holdfast-anchored cantilever deflection (Euler-Bernoulli s²(3−s) profile) with buoyant stipe tension; pneumatocyst gas bladders that bob, rim-light and lift the upper stipe
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
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Strand Density, .y = Current Speed, .z = Magnetism, .w = Biolume
  ripples: array<vec4<f32>, 50>,
};

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(31.2, 13.6)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// ── IDEA 1 helper: cantilever deflection profile ──
// A stipe anchored at the holdfast (s = 0) under a distributed drag load
// deflects as an Euler-Bernoulli cantilever: w(s) ∝ s²(3 − s), normalised so
// the free tip (s = 1) deflects 1. Buoyant tension from the gas bladders
// stiffens the column and straightens it back toward vertical.
fn cantilever(s: f32, tension: f32) -> f32 {
  let x = sat(s);
  let w = x * x * (3.0 - x) * 0.5;
  return w / (1.0 + tension);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);

  // Clamp/normalize parameter vector
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));

  // ═══ CHUNK: bass_env smoothing (state relocated to safe slot 133) ═══
  var prevBass = bass;
  if (arrayLength(&extraBuffer) > 138u) {
    prevBass = extraBuffer[133];
  }
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    if (arrayLength(&extraBuffer) > 138u) {
      extraBuffer[133] = smoothBass;
    }
  }

  let strandDensity = mix(6.0, 44.0, zp.x);
  let currentSpeed = mix(0.1, 2.0, zp.y);
  let magnetism = mix(0.0, 1.4, zp.z) * (1.0 + held * 1.5);
  let biolume = mix(0.2, 2.4, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

  let lanes = p.x * strandDensity;
  let laneId = floor(lanes);
  let laneLocal = fract(lanes) - 0.5;
  let seed = hash21(vec2<f32>(laneId, 13.7));
  let phase = seed * 6.28318;

  // Height above the seafloor: holdfast at the bottom row, free tip at top.
  let s = sat(1.0 - uv.y);
  let yNorm = sat(0.5 + p.y * 0.5);

  // ═══ Sway physics: layered pendulum-like modes ═══
  let swayBase = sin(p.y * 4.0 + time * currentSpeed + phase);
  let swayHarmonic = sin(p.y * 11.0 + time * currentSpeed * 1.7 + phase * 1.3) * 0.35;
  let current = sin(p.y * 2.0 - time * currentSpeed * 0.5 + seed * 10.0) * 0.2;

  // ═══ Organic FBM displacement for non-uniform strand motion ═══
  let fbmSway = fbm(vec2<f32>(laneId * 0.1, p.y * 2.0 + time * 0.2), 4) - 0.5;
  let organicWidth = 1.0 + fbm(vec2<f32>(p.y * 3.0, laneId * 0.3), 3) * 0.5;

  // ── IDEA 1: holdfast-anchored cantilever ──
  // Drag load grows with current speed (reconfiguration: stiffer bend in fast
  // flow); buoyant bladders add tension that straightens the column.
  let bladderTension = 0.35 + seed * 0.4;
  let bend = cantilever(s, bladderTension) * (1.0 + bladderTension) * (0.55 + zp.y * 0.6);

  // Click ripples → surge waves: a horizontal water pulse radiating from the
  // click, loading each stipe through the same cantilever profile.
  var surge = 0.0;
  var surgeGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.5) {
      let rpos = (rp.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
      let d = p - rpos;
      let front = length(d) - age * 0.9;
      let ring = exp(-front * front * 18.0) * exp(-age * 1.3);
      surge += sign(d.x) * ring * 0.9;
      surgeGlow = max(surgeGlow, exp(-front * front * 220.0) * exp(-age * 1.8));
    }
  }

  let magneticPull = (mouse.x - p.x) * magnetism * exp(-abs(mouse.y - p.y) * 3.0);
  let strandOffset = ((swayBase + swayHarmonic + fbmSway * 0.6 + current) * (0.25 + mids * 0.2) + surge) * bend
                   + magneticPull * (0.35 + 0.65 * bend);

  let strandDist = abs(laneLocal + strandOffset);
  let rooted = smoothstep(0.0, 0.04, s);
  let strand = smoothstep(0.30, 0.02, strandDist) * organicWidth * rooted;

  // ── IDEA 2: pneumatocyst gas bladders ──
  // Giant kelp carries a gas-filled float at the base of each blade. They sit
  // alternately left/right of the stipe, bob with the swell (bass), are
  // rim-lit like thin translucent shells, and their lift is what supplies the
  // bladderTension above. Absent near the holdfast.
  let spacing = mix(0.22, 0.12, zp.x);
  let bob = sin(time * (0.8 + currentSpeed * 0.6) + phase) * 0.012 * (1.0 + smoothBass * 1.5);
  let cellCoord = (p.y + bob) / spacing + seed * 3.0;
  let cellId = floor(cellCoord);
  let side = select(-1.0, 1.0, fract(cellId * 0.5) > 0.25);
  let laneW = 1.0 / strandDensity;
  let bulbR = min(0.022 + 0.008 * hash21(vec2<f32>(laneId, cellId)), laneW * 0.3) * (1.0 + smoothBass * 0.25);
  let bdx = (laneLocal + strandOffset) * laneW - side * bulbR * 1.25;
  let bdy = (fract(cellCoord) - 0.5) * spacing;
  let bulbD = length(vec2<f32>(bdx, bdy)) / max(bulbR, 1e-4);
  let bulbPresent = smoothstep(0.12, 0.25, s) * step(0.35, hash21(vec2<f32>(laneId + 7.0, cellId)));
  let bulbFill = smoothstep(1.0, 0.85, bulbD) * bulbPresent;
  let bulbRim = smoothstep(0.55, 0.95, bulbD) * bulbFill;
  let bulbSpec = exp(-dot(vec2<f32>(bdx, bdy) / max(bulbR, 1e-4) + vec2<f32>(0.35, 0.35), vec2<f32>(bdx, bdy) / max(bulbR, 1e-4) + vec2<f32>(0.35, 0.35)) * 12.0) * bulbFill;

  // ═══ Fronds and bioluminescent tips (tips at the free end of the cantilever) ═══
  let frond = smoothstep(0.7, 1.0, sin((p.y + seed * 0.7) * 18.0 + time * 2.0 + smoothBass * 4.0)) * strand;
  let tipMask = smoothstep(0.18, 0.0, abs(s - 0.92)) * strand;
  let tipPulse = 0.5 + 0.5 * sin(time * 3.0 + seed * 8.0 + smoothBass * 6.0);
  let tipGlow = tipMask * (0.6 + tipPulse * 0.4) * biolume;

  // Drifting spores
  let sporeUV = uv + vec2<f32>(time * 0.03, -time * 0.05);
  let spores = step(0.998 - treble * 0.03, hash21(floor(sporeUV * 280.0)));

  // Chromatic kelp: green strands, cyan fronds, glowing tips
  let tipCol = palette(seed + time * 0.02,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 0.5),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  var color = vec3<f32>(0.01, 0.04, 0.06);
  color = color + vec3<f32>(0.02, 0.5, 0.32) * strand * (1.0 + smoothBass * 0.1);
  color = color + vec3<f32>(0.15, 0.95, 0.75) * frond * biolume * (1.0 + mids * 0.15);
  color = color + tipCol * tipGlow * 1.5;
  color = color + vec3<f32>(0.8, 1.0, 0.65) * spores * (0.3 + treble);
  // Bladders: amber-olive translucent body, bioluminescent rim, gas highlight
  color = mix(color, vec3<f32>(0.32, 0.36, 0.08) + color * 0.3, bulbFill * 0.7);
  color = color + vec3<f32>(0.3, 1.0, 0.8) * bulbRim * biolume * (0.35 + mids * 0.3);
  color = color + vec3<f32>(1.0, 0.95, 0.75) * bulbSpec * (0.6 + treble * 0.5);
  // Surge fronts and magnetic halo
  color = color + vec3<f32>(0.2, 0.55, 0.7) * surgeGlow * (0.5 + bass * 0.5);
  let mouseHalo = exp(-length(p - mouse) * 6.0) * magnetism * 0.25;
  color = color + vec3<f32>(0.25, 0.6, 0.9) * mouseHalo;

  // Temporal sway persistence: kelp remembers previous motion (exact load)
  let maxC = vec2<i32>(i32(dims.x) - 1, i32(dims.y) - 1);
  let prev = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxC), 0);
  color = mix(color, prev.rgb * 0.88, 0.04 + smoothBass * 0.015);

  let display = acesToneMap(color * (1.1 + bass * 0.1));

  // Alpha = kelp-canopy coverage: stipes, fronds, bladders, glowing tips.
  let alpha = clamp(strand * 0.55 + frond * 0.15 + bulbFill * 0.35 + tipGlow * 0.25 + spores * 0.3 + surgeGlow * 0.2 + mouseHalo * 0.2, 0.04, 1.0);
  // Depth: canopy toward the surface (high s) and bladders sit nearer.
  let depth = clamp(sat(strand) * (0.3 + s * 0.45) + bulbFill * 0.2, 0.0, 1.0);
  let finalColor = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
