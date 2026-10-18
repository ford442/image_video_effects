// ═══════════════════════════════════════════════════════════════════
//  Hyper-Bismuth Clockwork
//  Category: generative
//  Features: raymarched, KIFS, bismuth-crystal, iridescent, audio-reactive,
//            mouse-driven, clockwork-mechanical, upgraded-rgba, depth-aware,
//            aces-tone-map, ambient-occlusion
//  Complexity: Very High
//  Created: 2026-06-28
//  Upgraded: 2026-10-18
//  Ideas: hopper terrace ridges on step-cuts; escapement mesh flash at gearPhase crests; mainspring wind-down with ratchet rewind flash; polished brass seams where gear teeth bite the crystal; blued-steel hairspring coiled round each crystal, breathing with the balance swing; guilloché engine-turned rosette engraving on the crystal faces (petal count follows Complexity)
//  A packing: ACES display RGBA; texel (0,0) = torque state
//             (eased torque, marker 7.25, accumulated torque phase, 0)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  q = q + dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3Z(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ─── SDF ───
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdBoxFrame(p: vec3<f32>, b: vec3<f32>, e: f32) -> f32 {
  let q = abs(p) - b;
  let w = abs(q) - e;
  return min(max(q.x, max(q.y, q.z)), 0.0) + length(max(w, vec3<f32>(0.0)));
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
  return p - c * round(p / c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Bismuth stepped crystal SDF ───
// .x = distance, .y = hopper terrace ridge (boolean step-cut proximity)
fn sdBismuthStep(p: vec3<f32>, size: f32, steps: i32) -> vec2<f32> {
  var d = sdBox(p, vec3<f32>(size));
  var s = size * 0.5;
  var pp = p;
  var terrace = 0.0;
  for (var i: i32 = 0; i < steps; i = i + 1) {
    let offset = vec3<f32>(s * 0.3, -s * 0.2, s * 0.1);
    pp = pp - offset;
    let inner = sdBox(pp, vec3<f32>(s * 0.85, s * 0.9, s * 0.85));
    let cut = -inner;
    // Idea 1 — ridge where the hopper subtraction meets the outer box
    terrace = max(terrace, 1.0 - sat(abs(d - cut) / max(s * 0.08, 0.001)));
    d = max(d, cut);
    s = s * 0.7;
  }
  return vec2<f32>(d, terrace);
}

// ─── KIFS Bismuth ───
fn sdKIFSBismuth(p: vec3<f32>, time: f32, complexity: f32, clockSpeed: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  let rot = rot3Y(time * clockSpeed * 0.2) * rot3X(time * clockSpeed * 0.15);
  
  for (var i: i32 = 0; i < 3; i = i + 1) {
    z = rot * z;
    z = abs(z);
    if (z.x + z.y + z.z < complexity) {
      z = z * 2.0 - vec3<f32>(complexity * 0.5);
      dr = dr * 2.0;
    }
  }
  let d = sdBox(z, vec3<f32>(0.5)) / dr;
  return d;
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  ao: f32,
  terrace: f32,
  mesh: f32,
  contact: f32,
  guilloche: f32,
};

// Idea 5 — balance hairspring: flat Archimedean coil in the cell's xz plane.
// Returns distance to the wire; pitch breathes and the coil turns with the swing.
fn sdHairspring(q: vec3<f32>, cell: f32, swing: f32) -> f32 {
  let c = cos(swing * 0.6); let sn = sin(swing * 0.6);
  let xz = vec2<f32>(c * q.x - sn * q.z, sn * q.x + c * q.z);
  let r = length(xz);
  let a = atan2(xz.y, xz.x);
  let rIn = cell * 0.2;
  let rOut = cell * 0.47;
  let pitch = cell * 0.068 * (1.0 + 0.14 * swing);
  let u = (r - rIn) / pitch - a / 6.2831853;
  let fu = fract(u);
  let dr = min(fu, 1.0 - fu) * pitch;
  let radial = max(dr, max(rIn - r, r - rOut));
  return length(vec2<f32>(radial, q.y)) - cell * 0.012;
}

// Idea 6 — guilloché: rose-engine wave lines on the face the hit lands on.
fn guillocheLines(rq: vec3<f32>, size: f32, petals: f32) -> f32 {
  let aq = abs(rq);
  var f = rq.xy;
  if (aq.x > aq.y && aq.x > aq.z) { f = rq.yz; }
  else if (aq.y > aq.z) { f = rq.xz; }
  let rho = length(f) / max(size, 1e-4);
  let phi = atan2(f.y, f.x);
  let wave = rho + 0.045 * sin(phi * petals);
  let line = abs(sin(wave * 54.0));
  return 1.0 - smoothstep(0.0, 0.35, line);
}

// Idea 3 — mainspring power reserve: the movement runs down from full speed
// to half over WIND_PERIOD seconds, then the ratchet rewinds it. Clock time is
// the analytic integral of that speed, so motion never jumps.
const WIND_PERIOD: f32 = 24.0;
fn mainspringTime(t: f32) -> f32 {
  let f = fract(t / WIND_PERIOD);
  return WIND_PERIOD * (floor(t / WIND_PERIOD) * 0.75 + f - 0.25 * f * f);
}

fn map(p_in: vec3<f32>, time: f32, audio: f32, complexity: f32,
       clockSpeed: f32, gridDensity: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Magnetic singularity cursor
  let md = p - mousePos;
  let mDist = length(md);
  let magRadius = 2.5;
  if (mDist < magRadius) {
    let pull = (1.0 - mDist / magRadius) * 1.5;
    p = p + md / max(mDist, 1e-4) * pull * 0.3;
  }

  // Grid cell
  let cell = 2.0 / gridDensity;
  let q = opRep(p, vec3<f32>(cell));
  let cellId = floor(p / cell);
  let cellHash = hash3(cellId);

  // Audio-reactive clockwork motion
  let phase = time * clockSpeed + cellHash * 6.28 + audio * 2.0;
  let rotation = rot3Y(phase * 0.5) * rot3X(phase * 0.3);
  let rq = rotation * q;

  // Stepped bismuth crystal in each cell
  let stepCount = i32(2.0 + complexity * 0.5);
  let hopper = sdBismuthStep(rq, cell * 0.35, stepCount);
  let bismuth = hopper.x;

  // KIFS structure at center
  let kifs = sdKIFSBismuth(q, time + cellHash * 10.0, complexity, clockSpeed);

  // Blend: bismuth + KIFS
  var d = smin(bismuth, kifs, 0.15);

  // Interlocking gear teeth
  let gearPhase = time * clockSpeed * 2.0 + cellHash * 3.14;
  let gearOffset = vec3<f32>(
    cos(gearPhase) * cell * 0.15,
    sin(gearPhase * 1.3) * cell * 0.1,
    cos(gearPhase * 0.7) * cell * 0.12
  );
  let gear = sdBox(q - gearOffset, vec3<f32>(cell * 0.05, cell * 0.15, cell * 0.05));
  // Idea 4 — tooth bite: where the tooth and crystal surfaces meet
  let contact = (1.0 - sat(abs(d - gear) / max(cell * 0.045, 1e-4))) * (1.0 - sat(min(d, gear) / max(cell * 0.06, 1e-4)));
  d = smin(d, gear, 0.05);

  // Idea 5 — the balance hairspring swings once per escapement crest pair.
  let spring = sdHairspring(q, cell, sin(gearPhase));
  d = min(d, spring);

  // Idea 2 — escapement mesh: flash when neighboring teeth crest
  let mesh = pow(0.5 + 0.5 * cos(gearPhase * 2.0), 18.0);

  // Frame edges
  let frame = sdBoxFrame(q, vec3<f32>(cell * 0.38), cell * 0.02);
  d = smin(d, frame, 0.03);

  // Material
  var mat = 1.0; // crystal
  if (spring <= d + 1e-4) {
    mat = 2.0; // blued-steel hairspring
  }
  if (mDist < magRadius * 0.5 && u.zoom_config.w > 0.5) {
    mat = 0.5; // molten core (only while the singularity is held)
  }

  // Ambient occlusion proxy
  let ao = sat(0.7 + 0.3 * hash3(cellId + vec3<f32>(0.5)));

  let guilloche = guillocheLines(rq, cell * 0.35, floor(4.0 + complexity * 2.0));

  return MapResult(d, mat, ao, hopper.y, mesh, contact, guilloche);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32,
              clockSpeed: f32, gridDensity: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m2 = map(p - e.xyy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m3 = map(p + e.yxy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m4 = map(p - e.yxy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m5 = map(p + e.yyx, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m6 = map(p - e.yyx, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Iridescent thin-film color ───
fn iridescent(nDotV: f32, shift: f32) -> vec3<f32> {
  let t = nDotV * 3.14159 + shift;
  return vec3<f32>(
    0.5 + 0.5 * cos(t + 0.0),
    0.5 + 0.5 * cos(t + 2.09),
    0.5 + 0.5 * cos(t + 4.18)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let audio = plasmaBuffer[0].x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters (clamp zoom_params to normalized range)
  let complexityControl = clamp(u.zoom_params.x, 0.0, 1.0);
  let clockSpeedControl = clamp(u.zoom_params.y, 0.0, 1.0);
  let iridescenceControl = clamp(u.zoom_params.z, 0.0, 1.0);
  let gridDensityControl = clamp(u.zoom_params.w, 0.0, 1.0);
  let complexity = mix(1.0, 5.0, complexityControl);
  let clockSpeed = mix(0.2, 2.0, clockSpeedControl);
  let iridescence = mix(0.2, 2.0, iridescenceControl);
  let gridDensity = mix(1.0, 3.0, gridDensityControl);

  // Mouse position in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y;

  // Camera - orbiting through the clockwork
  let camDist = 4.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.12 + mouseUV.x * 0.4;
  let camHeight = mouseY * 1.0;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);
  // uu = cross(Y, ww) is screen-LEFT and vv is up while uv.y grows downward,
  // so rays use (-p.x, -p.y): a 180° turn (flipping one axis would mirror).
  // Singularity cursor lies on the focal plane through the target, under the pointer.
  let mousePos = ta - uu * (mouseUV.x * 2.0 - 1.0) * aspect * camDist / 2.5
                    + vv * (1.0 - mouseUV.y * 2.0) * camDist / 2.5;

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let mouseDown = u.zoom_config.w > 0.5;

  // Held input applies signed torque; clicks launch finite toothed gear shocks.
  let heldTorque = select(0.0, (mouseUV.x - 0.5) * 2.2 + (0.5 - mouseUV.y) * 0.7, mouseDown);
  let rippleCount = min(u32(u.config.y), 50u);
  var gearShock = 0.0;
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age < 0.0 || age > 3.2) { continue; }
    let center = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let delta = p - center;
    let d = length(delta);
    let radius = age * (0.28 + clockSpeed * 0.14);
    let teeth = 0.55 + 0.45 * cos(atan2(delta.y, delta.x) * mix(8.0, 22.0, complexityControl));
    let ring = (d - radius) * 22.0;
    gearShock += exp(-ring * ring) * exp(-age * 0.9) * teeth;
  }
  // Torque and shocks are bounded phase pushes, not speed multipliers on absolute time.
  // Held torque eases in/out and integrates into a phase that is kept on
  // release (A texel (0,0), read back from C) — no step on press or release.
  let st = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stOk = abs(st.y - 7.25) < 0.01;
  let prevTorque = select(0.0, clamp(st.x, -2.0, 2.0), stOk);
  let prevTorquePhase = select(0.0, st.z, stOk && abs(st.z) < 1.0e5);
  let torque = mix(prevTorque, heldTorque, 0.08);
  let torquePhase = prevTorquePhase + torque * 0.03;
  let torquePush = (torquePhase + gearShock * 1.2) / clockSpeed;
  let effectiveClockSpeed = clockSpeed;
  let rd = normalize(-p.x * uu - p.y * vv + 2.5 * ww);

  let clockTime = mainspringTime(time) + torquePush;
  let springPhase = fract(time / WIND_PERIOD);
  let reserve = 1.0 - springPhase;
  let ratchetFlash = exp(-springPhase * WIND_PERIOD * 2.5);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitAo = 1.0;
  var hitTerrace = 0.0;
  var hitMesh = 0.0;
  var hitContact = 0.0;
  var hitGuilloche = 0.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, clockTime, audio, complexity, effectiveClockSpeed, gridDensity, mousePos);

    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitAo = res.ao;
      hitTerrace = res.terrace;
      hitMesh = res.mesh;
      hitContact = res.contact;
      hitGuilloche = res.guilloche;
      depth = t;
      break;
    }

    if (t > 25.0) { break; }
    t = t + res.d * 0.7;
  }

  if (hit) {
    let n = calcNormal(hitPos, clockTime, audio, complexity, effectiveClockSpeed, gridDensity, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let lightDir2 = normalize(vec3<f32>(-0.3, 0.5, -0.7));

    let diff = sat(dot(n, lightDir));
    let diff2 = sat(dot(n, lightDir2)) * 0.5;
    let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 32.0);
    let spec2 = pow(sat(dot(reflect(-lightDir2, n), viewDir)), 64.0) * 0.5;

    if (hitMat > 1.5) {
      // Idea 5 — blued-steel hairspring: deep temper blue with a cool sheen,
      // brightening at the escapement crest the coil is swinging through.
      let blued = vec3<f32>(0.05, 0.12, 0.42) + vec3<f32>(0.1, 0.25, 0.6) * pow(1.0 - nDotV, 3.0);
      col = blued * (0.35 + diff * 0.65 + diff2 * 0.3) + vec3<f32>(0.55, 0.7, 1.0) * (spec + spec2) * 0.9;
      col += vec3<f32>(0.3, 0.55, 1.0) * hitMesh * (0.2 + mids * 0.3);
    } else if (hitMat < 0.75) {
      // Molten core
      let coreCol = vec3<f32>(1.0, 0.9, 0.7) * (1.0 + audio * 2.0);
      let innerGlow = vec3<f32>(0.8, 0.4, 0.1) * (1.0 - nDotV) * 2.0;
      col = coreCol * (0.6 + diff * 0.4) + innerGlow;
    } else {
      // Bismuth crystal surface
      let ired = iridescent(nDotV, time * 0.5 + complexity) * iridescence;
      let baseMetal = vec3<f32>(0.15, 0.18, 0.22);
      var metal = baseMetal + ired * 0.6;

      // Sharp stepped edges = more iridescent
      let edge = pow(1.0 - nDotV, 4.0);
      metal = metal + ired * edge * 0.4;
      // Idea 1 — hopper terrace ridges catch extra film color
      metal = metal + ired * hitTerrace * 0.55;
      // Idea 6 — guilloché engraving: cut grooves shift the film and catch a
      // fine specular line; fades with distance before it can alias.
      let engrave = hitGuilloche * sat(1.0 - depth / 9.0);
      metal = mix(metal, iridescent(nDotV, time * 0.5 + complexity + 1.4) * iridescence * 0.85 + baseMetal, engrave * 0.45);

      col = metal * (0.3 + diff * 0.5 + diff2 * 0.2);
      col = col + vec3<f32>(0.6, 0.7, 0.8) * (spec + spec2) * (0.5 + engrave * 0.8);
      // Idea 2 — escapement mesh flash at tooth crest
      // (flash strength follows mainspring tension; ratchet rewind flashes every crest)
      col = col + vec3<f32>(1.0, 0.78, 0.38) * (hitMesh * (0.45 + 0.55 * reserve) + ratchetFlash * 0.6) * (spec + 0.18) * 0.85;
      // Idea 4 — burnished brass where teeth wear against the step-cuts
      col = col + vec3<f32>(1.0, 0.8, 0.48) * hitContact * (0.12 + diff * 0.25 + (spec + spec2) * 1.4);

      // Audio-reactive shimmer
      col = col + ired * bass * 0.2;
      col += vec3<f32>(1.0, 0.35 + mids * 0.25, 0.08 + treble * 0.3) * gearShock * 1.4;
    }

    // Ambient occlusion
    col = col * (0.4 + 0.6 * hitAo);

    // Deep shadows in crevices
    let cavity = pow(1.0 - nDotV, 2.0) * 0.3;
    col = col * (1.0 - cavity);
  } else {
    // Background - void with distant clockwork glow
    col = vec3<f32>(0.01, 0.02, 0.03);
    let voidGlow = sat(0.05 / (length(p) * 0.5 + 0.02));
    col = col + vec3<f32>(0.1, 0.15, 0.2) * voidGlow * (0.2 + audio * 0.1);
    depth = 25.0;
  }

  // A/C owns exact ACES display history; do not re-tone-map prior frames.
  let currentDisplay = acesToneMap(col * 1.2);
  let isState = gid.x == 0u && gid.y == 0u;
  let prev = select(textureLoad(dataTextureC, coord, 0), vec4<f32>(0.0), isState);
  col = mix(prev.rgb * 0.95, currentDisplay, 0.24 + bass * 0.035);

  let finalDepth = sat(0.95 - depth * 0.04);
  let hitCoverage = select(0.0, 0.72 + finalDepth * 0.22, hit);
  let glowCoverage = clamp(dot(currentDisplay, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.45 + gearShock * 0.3, 0.0, 0.9);
  let alpha = max(max(hitCoverage, glowCoverage), prev.a * 0.92);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, select(vec4<f32>(col, alpha), vec4<f32>(torque, 7.25, torquePhase, 0.0), isState));
}
