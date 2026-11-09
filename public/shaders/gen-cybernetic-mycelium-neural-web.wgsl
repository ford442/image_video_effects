// ═══════════════════════════════════════════════════════════════════
//  Cybernetic-Mycelium Neural-Web
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-10-31
//  Ideas: saltatory conduction leaps across myelinated segments; astrocyte calcium halos around dense synaptic hubs; Airy-disc calcium wave rings travelling out of the astrocyte hub (F Airy disc); advancing colony growth fronts along trail-density iso-contours (promotes trailDensity)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Growth Rate, y=Pulse Intensity, z=Decay Speed, w=Network Complexity

const PI : f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

fn hash2(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(0.1031, 0.1030));
  q += dot(q, q + 33.33);
  return fract((q.x + q.y) * q.x);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i+vec2<f32>(0.0,0.0)), hash2(i+vec2<f32>(1.0,0.0)), w.x),
    mix(hash2(i+vec2<f32>(0.0,1.0)), hash2(i+vec2<f32>(1.0,1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise2(pp);
    pp = pp * 2.03 + vec2<f32>(1.7, 3.1);
    a *= 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Bessel J1 (Numerical Recipes rational / asymptotic fit), x > 0 only.
fn besselJ1(x: f32) -> f32 {
  let ax = max(x, 1e-3);
  let y = ax * ax;
  let n1 = ax * (72362614232.0 + y * (-7895059235.0 + y * (242396853.1 + y * (-2972611.439 + y * (15704.4826 + y * (-30.16036606))))));
  let d1 = 144725228442.0 + y * (2300535178.0 + y * (18583304.74 + y * (99447.43394 + y * (376.9991397 + y))));
  let z = 8.0 / ax;
  let w = z * z;
  let xx = ax - 2.356194491;
  let p1 = 1.0 + w * (0.183105e-2 + w * (-0.3516396496e-4 + w * (0.2457520174e-5 + w * (-0.240337019e-6))));
  let q1 = 0.04687499995 + w * (-0.2002690873e-3 + w * (0.8449199096e-5 + w * (-0.88228987e-6 + w * 0.105787412e-6)));
  let far = sqrt(0.636619772 / ax) * (cos(xx) * p1 - z * sin(xx) * q1);
  return select(far, n1 / d1, ax < 8.0);
}

// Airy diffraction pattern (2 J1(x)/x)^2, 1 at the centre, first zero at x = 3.8317.
fn airy(x: f32) -> f32 {
  let xs = max(x, 1e-3);
  let a = 2.0 * besselJ1(xs) / xs;
  return a * a;
}

// Inverse of acesToneMap for display values (positive root of the fit's quadratic).
fn acesInverse(y: vec3<f32>) -> vec3<f32> {
  let yc = clamp(y, vec3<f32>(0.0), vec3<f32>(0.985));
  let qa = 2.43 * yc - vec3<f32>(2.51);
  let qb = 0.59 * yc - vec3<f32>(0.03);
  let qc = 0.14 * yc;
  let disc = max(qb * qb - 4.0 * qa * qc, vec3<f32>(0.0));
  return max((-qb - sqrt(disc)) / (2.0 * qa), vec3<f32>(0.0));
}

// Psychedelic mycelial spectrum — neon wheel spun by the audio
fn mycoPalette(t: f32, drive: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.25, 2.0 + drive * 1.3, 4.1 - drive * 0.9);
  return 0.5 + 0.5 * cos(TAU * t + phase);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv01 = fragCoord / res;
  let uv = (fragCoord - 0.5 * res) / res.y;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growthRate = u.zoom_params.x;
  let pulseIntensity = u.zoom_params.y;
  let decaySpeed = u.zoom_params.z;
  let complexity = u.zoom_params.w;

  let rawMouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let heldF = select(0.0, 1.0, held);

  // ── spring cursor — the ONLY persistent state, all in the safe zone ──
  var smoothMouse = rawMouse;
  var cursorSpeed = 0.0;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    cursorSpeed = length(vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]));
  }
  if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
    if (extraBuffer[SPRING_INIT] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
      let omega = 10.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[SPRING_X] = springPos.x;
    extraBuffer[SPRING_Y] = springPos.y;
    extraBuffer[SPRING_VX] = springVel.x;
    extraBuffer[SPRING_VY] = springVel.y;
    extraBuffer[SPRING_T] = time;
    extraBuffer[SPRING_INIT] = 1.0;
    smoothMouse = springPos;
    cursorSpeed = length(springVel);
  }
  // Whip the cursor and the net mutates — replaces the old click-count state slot
  let whip = clamp(cursorSpeed * 0.6, 0.0, 1.5);

  // ── click mutation bursts (capped, bounded) ─────────────────────────
  var burst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.85);
      burst = max(burst, exp(-front * 30.0) * (1.0 - age / 1.4));
    }
  }
  burst = min(burst, 1.0);
  let mutationSeed = fract(burst * 0.7 + whip * 0.3 + time * 0.05);

  let mousePos = (smoothMouse - 0.5) * vec2<f32>(aspect.x, 1.0) * 2.5;
  let mouseWorld = vec2<f32>(mousePos.x, smoothMouse.y * 2.0);

  // KIFS structural lattice (nutrient hotspots)
  var z = vec3<f32>(uv.x, uv.y, 0.0) * complexity * 3.0;
  var dr = 1.0;
  for(var i = 0; i < 5; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    z = z * 2.0 - vec3<f32>(1.0, 1.0, 1.0);
    dr *= 2.0;
  }
  let hotspot = length(z) / abs(dr);

  // Mycelial trail density — fast motion: growth streams several times quicker
  let flow = time * (0.9 + growthRate * 1.8 + bass * 1.4 + heldF * 0.8);
  let trailP = uv * 4.0 + vec2<f32>(flow * 0.35, -flow * 0.2);
  let trailDensity = fbm(trailP) * fbm(trailP * 1.5 + vec2<f32>(flow * 0.8, -flow * 0.6));

  // Hyphal filigree — fine branching striation carved over the trails
  let filigree = 0.5 + 0.5 * sin(trailDensity * 42.0 - flow * 4.0 + hotspot * 60.0);
  let detailedTrails = trailDensity * (0.75 + filigree * 0.5);

  // Exact four-neighbor history (needed for myelination before density)
  let prevData = textureLoad(dataTextureC, coord, 0);
  let historyMax = vec2<i32>(i32(u.config.z) - 1, i32(u.config.w) - 1);
  let prevN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), historyMax), 0).rgb;
  let prevS = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), historyMax), 0).rgb;
  let prevE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), historyMax), 0).rgb;
  let prevW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), historyMax), 0).rgb;
  let neighborHistory = (prevN + prevS + prevE + prevW) * 0.25;
  let neighborLuma = dot(neighborHistory, vec3<f32>(0.333, 0.333, 0.334));
  // Idea 1 — myelination: fire-reinforced trails thicken where history is already high
  let myelin = clamp(neighborLuma * 1.45, 0.0, 1.0);

  // Mouse attraction — held and burst both deepen the well
  let toMouse = mouseWorld - uv;
  let mouseDist = length(toMouse);
  let mouseAttraction = exp(-mouseDist * mouseDist * 2.0) * (3.0 + burst * 3.0 + heldF * 2.5 + whip * 1.5);

  // Audio-reactive turbulence on trails
  let audioTurbulence = fbm(uv * 8.0 + vec2<f32>(bass * 2.0 + flow * 0.3, mid * 2.0 - flow * 0.25));

  // Data pulses racing the high-density trails — treble sets the fire rate
  let pulsePhase = fract(time * (2.4 + treble * 6.0) * pulseIntensity + detailedTrails * 3.0 + mutationSeed);
  let pulse = exp(-pow(pulsePhase - 0.5, 2.0) * 50.0) * pulseIntensity;
  // Idea — refractory notch: a short dark gap just after the spike.
  let refractory = smoothstep(0.52, 0.58, pulsePhase) * smoothstep(0.74, 0.62, pulsePhase) * smoothstep(0.28, 0.55, detailedTrails);
  // Idea — dendritic spines: knobs where the filigree sine peaks.
  let dendriticSpine = smoothstep(0.84, 0.98, filigree) * smoothstep(0.22, 0.5, detailedTrails);

  let audioGrowth = 1.0 + bass * 2.0 + mid * 0.8;
  let totalDensity = detailedTrails * (1.0 + myelin * 0.55) * audioGrowth + mouseAttraction + audioTurbulence * 0.3;

  // Decay
  // HEAD fix: hard 20x20 hash cells printed a checkerboard over the whole frame; a value-noise
  // patch field keeps the same cell scale and decay rate but with soft organic borders.
  let age2 = fract(noise2(uv * 20.0) * 1.0 + time * decaySpeed * (1.0 + bass) + mutationSeed);
  let alive = smoothstep(0.0, 0.3, age2) * smoothstep(1.0, 0.7, age2);

  // ── Color: bio-mechanical base under a psychedelic pulse spectrum ────
  let baseHue = fract(detailedTrails * 0.5 + time * (0.12 + treble * 0.6) + mutationSeed);
  let bioCol = mix(
    mycoPalette(baseHue, mid) * 0.32,
    vec3<f32>(0.35, 0.35, 0.38),
    trailDensity * 0.6
  );

  let pulseCol = mycoPalette(baseHue + 0.4 + treble * 0.2, 1.0 + bass) * pulse * 1.4;

  let intersection = smoothstep(0.4, 0.6, trailDensity) * smoothstep(0.6, 0.4, trailDensity);
  let bioLum = mycoPalette(baseHue + 0.65, treble) * intersection * (0.6 + bass * 2.2);

  let mouseGlow = mycoPalette(fract(time * 0.5), bass) * mouseAttraction * 0.5;

  var col = bioCol * alive * (1.0 - refractory * 0.62);
  col += pulseCol;
  col += mycoPalette(baseHue + 0.22, 1.0) * dendriticSpine * (0.4 + treble * 0.45);
  col += bioLum;
  col += mouseGlow;
  col += mycoPalette(fract(time * 1.1), 1.0) * burst * 1.2;
  // Idea 5 — saltatory conduction: pulse energy hops across myelinated sections.
  let saltatory = pulse * smoothstep(0.35, 0.78, myelin) * smoothstep(0.22, 0.6, trailDensity);
  col += mycoPalette(baseHue + 0.48, 1.0 + bass) * saltatory * 1.35;
  // Idea 6 — astrocyte calcium halos around dense hubs.
  let astro = exp(-mouseDist * 4.0) * (0.5 + 0.5 * sin(time * 2.8 + trailDensity * 20.0));
  col += mycoPalette(baseHue + 0.9, mid) * astro * 0.42;
  // Idea 3 — Ca2+ wave rings: astrocyte calcium spreads as concentric waves; the Airy
  // pattern gives the hub a real ring ladder whose brightness travels outward.
  let airyR = airy(mouseDist * 34.0);
  let calciumWave = airyR * (0.55 + 0.45 * sin(time * 3.0 - mouseDist * 16.0)) * smoothstep(0.55, 0.05, mouseDist);
  col += mycoPalette(baseHue + 0.95, mid) * calciumWave * (0.32 + mid * 0.4);
  // Idea 4 — colony growth fronts: hyphae advance as contour bands of trail density that
  // creep outward at the Growth Rate; the front is brightest on already-myelinated runs.
  let frontPhase = fract(trailDensity * 3.2 - time * (0.08 + growthRate * 0.22));
  let growthFront = smoothstep(0.0, 0.05, frontPhase) * smoothstep(0.16, 0.05, frontPhase) * smoothstep(0.12, 0.4, trailDensity);
  col += mycoPalette(baseHue + 0.3, 1.0) * growthFront * (0.22 + myelin * 0.35);
  // Idea 2 — gap-junction flash: this pixel and a neighbor both spike (AND, not ridge)
  let gap = pulse * smoothstep(0.42, 0.78, neighborLuma) * smoothstep(0.35, 0.75, pulse);
  col += mycoPalette(baseHue + 0.08, 1.0 + treble) * gap * 1.65;

  // Organic subsurface scattering approximation
  let sss = fbm(uv * 6.0 + flow * 0.12) * 0.1;
  col += mycoPalette(baseHue + 0.85, mid) * sss * 0.6;

  // Audio bloom
  col += mycoPalette(0.35, bass) * bass * bass * 0.35;
  col += mycoPalette(0.75, mid) * mid * 0.28;

  // Chromatic edge aberration on dense areas
  let ca = totalDensity * 0.02 * (1.0 + treble);
  col.r += noise2(uv + vec2<f32>(ca, 0.0)) * ca;
  col.b += noise2(uv - vec2<f32>(ca, 0.0)) * ca;

  // Depth sample for depth-aware feedback
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;

  // ── temporal feedback — exact load, no filtering ────────────────────
  // A four-neighbor ridge measure reinforces connected hyphae while keeping
  // the history payload display-safe RGBA.
  let connectivity = clamp(length(prevData.rgb - neighborHistory) * 1.8, 0.0, 1.0);
  let feedbackMix = 0.3 + bass * 0.15;
  // HEAD fix: C holds ACES output; re-tone-mapping it every frame drove the whole
  // frame to a pastel wash, so decode the trail to linear before it is blended.
  col = mix(acesInverse(prevData.rgb) / (1.05 + mid * 0.25) * 0.95, col, feedbackMix);
  col += mycoPalette(baseHue + 0.18, mid) * connectivity * (0.08 + treble * 0.12);

  col = acesToneMap(col * (1.05 + mid * 0.25));

  // Semantic alpha: mycelial density + firing energy
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(
    clamp(totalDensity * 0.3, 0.0, 0.7) + luma * 0.45 + pulse * 0.2
      + burst * 0.25 + connectivity * 0.12 + myelin * 0.08 + gap * 0.15 + depthSample * 0.1
      + saltatory * 0.12 + astro * 0.08 + calciumWave * 0.08 + growthFront * 0.06
      + dendriticSpine * 0.1,
    0.0, 1.0);

  let outColor = vec4<f32>(col, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(hotspot * 0.5 + depthSample * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0));
}
