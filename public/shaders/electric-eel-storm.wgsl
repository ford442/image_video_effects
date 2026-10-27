// ═══════════════════════════════════════════════════════════════════
//  Electric Eel Storm
//  Category: generative
//  Features: generative, audio-reactive, temporal, chromatic, mouse-driven, upgraded-rgba, distance-lod
//  Complexity: Very High
//  Upgraded: 2026-10-19
//  Ideas: anguilliform eel body + undulating ventral ribbon fin; electric-organ
//         dipole field (head +, tail −; soft inverse-square field lines with
//         flowing current); EOD volleys gating the arcs, click-startle discharge
//  A packing: ACES display RGBA (C read as display colour: trails + chromatic dispersion)
//  Description: Electric eels swimming through a conductive storm
//               cloud, discharging arcs between them. Bass drives
//               eel body pulses, mids create storm turbulence,
//               treble triggers lightning arcs. Mouse attracts
//               the eel school.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI = 3.14159265;
const TAU = 6.2831853;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash12(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: f32) -> f32 {
  // Fractional octave count: the last octave fades in, so the distance LOD below has no
  // visible ring where the integer count used to step (HEAD drew concentric seams).
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  let n = i32(ceil(octaves));
  for (var i: i32 = 0; i < n; i = i + 1) {
    let w = clamp(octaves - f32(i), 0.0, 1.0);
    v += a * noise2(p * f) * w + a * 0.5 * (1.0 - w);
    a *= 0.5;
    f *= 2.03;
  }
  return v;
}

// Eel path: serpentine swimming motion
fn eelPosition(index: f32, time: f32, pulseSpeed: f32, mouse: vec2<f32>) -> vec2<f32> {
  let fi = index;
  let baseY = 0.3 + fi * 0.15 + sin(fi * 2.7) * 0.1;
  let baseX = 0.5 + sin(time * 0.2 + fi * 1.3) * 0.25;

  // Serpentine body wave
  let bodyWave = sin(time * pulseSpeed * 2.0 + fi * 1.1) * 0.06;

  // Mouse attraction
  let attract = (mouse - vec2<f32>(baseX, baseY)) * 0.15;
  let attractSmooth = attract * (0.5 + 0.5 * sin(time + fi));

  return vec2<f32>(baseX + bodyWave + attractSmooth.x, baseY + attractSmooth.y);
}

// Eel facing: +1 swimming right, -1 left. The drift is baseX = 0.5 + sin(time*0.2 + fi*1.3)*0.25,
// so the swim direction is the sign of its cosine; near the turn the body foreshortens.
fn eelFacing(index: f32, time: f32) -> f32 {
  return clamp(cos(time * 0.2 + index * 1.3) * 4.0, -1.0, 1.0);
}

struct EelHit {
  d: f32,      // body distance (approx.)
  fin: f32,    // ribbon-fin membrane coverage 0..1
  u: f32,      // 0 = tail tip, 1 = snout
}

// ── Idea 1: anguilliform eel body + ventral ribbon fin ──
// Centreline wave y = A(u)·sin(k·u − ωt), amplitude growing toward the tail; blunt rounded
// snout, tail tapering to a point; the long anal fin under the trunk ripples with its own,
// faster wave (Electrophorus swims with that fin while the trunk stays fairly straight).
fn sdEel(uv: vec2<f32>, pos: vec2<f32>, facing: f32, time: f32, pulseSpeed: f32, bass: f32) -> EelHit {
  let toPixel = uv - pos;
  let bodyLength = 0.18 + bass * 0.03;
  let bodyWidth = 0.015 + sin(time * pulseSpeed * 3.0) * 0.003 * (1.0 + bass);
  let span = bodyLength * max(abs(facing), 0.3);
  let dirSign = select(-1.0, 1.0, facing >= 0.0);
  let lx = toPixel.x * dirSign;                              // +lx toward the snout
  let u = clamp(lx / (2.0 * span) + 0.5, 0.0, 1.0);
  let amp = (0.004 + 0.022 * (1.0 - u) * (1.0 - u)) * (1.0 + bass * 0.5);
  let yc = amp * sin(u * 9.0 - time * pulseSpeed * 4.0);
  let ly = toPixel.y - yc;
  let w = bodyWidth * min(u * 2.2, 1.0) * sqrt(clamp((1.0 - u) / 0.14, 0.0, 1.0));
  let d = max(abs(ly) - w, abs(lx) - span);
  // ventral ribbon fin: from u = 0.12 to 0.78, below the trunk
  let finSpan = smoothstep(0.08, 0.2, u) * smoothstep(0.84, 0.7, u);
  let finH = bodyWidth * (1.1 + 0.5 * sin(u * 26.0 - time * pulseSpeed * 9.0)) * finSpan;
  let below = -ly - w;                                       // distance under the belly
  let finRays = 0.6 + 0.4 * sin(u * 140.0);
  let fin = smoothstep(finH + 0.002, finH - 0.001, below) * step(-0.001, below) * finSpan * finRays
          * step(abs(lx), span);
  return EelHit(d, fin, u);
}

// ── Idea 2: electric-organ dipole field (§12.2F soft inverse-square) ──
// Head is the + pole, tail the − pole. 2D dipole field lines are the circles through both
// poles = level sets of the angle the head–tail segment subtends at the pixel; strength is
// the sum of soft inverse-square falloffs; a dash flows along the lines from + to − using
// the 2D potential ln(r−/r+).
fn dipoleField(uv: vec2<f32>, head: vec2<f32>, tail: vec2<f32>, time: f32, flow: f32) -> f32 {
  let a = uv - head;
  let b = uv - tail;
  let r0 = 0.018;
  let rp2 = dot(a, a);
  let rm2 = dot(b, b);
  let strength = r0 * r0 / (rp2 + r0 * r0) + r0 * r0 / (rm2 + r0 * r0);
  let subtended = atan2(a.x * b.y - a.y * b.x, dot(a, b));  // −π..π, constant along a field line
  let lines = pow(abs(cos(subtended * 4.0)), 24.0);
  let potential = 0.5 * log((rm2 + 1e-5) / (rp2 + 1e-5));
  let dash = 0.35 + 0.65 * smoothstep(0.55, 0.95, fract(potential * 1.3 - time * flow));
  return lines * dash * sqrt(strength);
}

// ── Idea 3: EOD volleys ──
// Discharges come as volleys: a burst gate per 0.6 s slot (fires with p rising with bass)
// carrying a decaying pulse train.
fn eodVolley(index: f32, time: f32, bass: f32) -> f32 {
  let clock = time * 1.6 + index * 0.37;
  let slot = floor(clock);
  let ph = fract(clock);
  let fire = step(1.0 - (0.3 + 0.55 * bass), hash21(vec2<f32>(index * 7.1, slot)));
  let train = step(0.45, fract(ph * 7.0));
  return fire * exp(-ph * 3.5) * (0.35 + 0.65 * train);
}

// Lightning arc between two points
fn lightningArc(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>, time: f32, seed: f32, minW: f32) -> f32 {
  let ab = b - a;
  let abLen = length(ab);
  let abDir = ab / max(abLen, 0.0001);
  let abN = vec2<f32>(-abDir.y, abDir.x);

  let toPixel = uv - a;
  let proj = clamp(dot(toPixel, abDir), 0.0, abLen);
  let closest = a + abDir * proj;
  let t = proj / max(abLen, 0.0001);

  // Jagged displacement: piecewise-linear kinks pinned to zero at both ends, so consecutive
  // bolt segments join (HEAD's sin(t·20 + seed) never returned to the segment ends → broken,
  // coiled bolts).
  let k = t * 5.0;
  let k0 = floor(k);
  let h0 = hash21(vec2<f32>(k0, seed)) - 0.5;
  let h1 = hash21(vec2<f32>(k0 + 1.0, seed)) - 0.5;
  let pin = sin(PI * t);
  let jagged = mix(h0, h1, fract(k)) * abLen * 0.35 * pin;
  let jagged2 = sin(t * 45.0 - seed * 7.0 + time * 8.0) * 0.002 * pin;
  let displaced = closest + abN * (jagged + jagged2);

  let d = length(uv - displaced);
  let arcWidth = max(0.003 + sin(time * 20.0 + seed) * 0.001, minW);
  return smoothstep(arcWidth, 0.0, d);
}

// Storm cloud turbulence
// ═══ CHUNK: distance-based octave LOD (perf) ═══
// Pixels far from screen center contribute less to the focal read of
// the storm — relax FBM octaves there (4→2 / 3→2) to cut noise2 calls
// without a perceptible loss of detail at the periphery.
fn stormCloud(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  let distFromCenter = length(uv - vec2<f32>(0.5));
  let lod = smoothstep(0.3, 0.7, distFromCenter);
  let oct1 = mix(4.0, 2.0, lod);
  let oct2 = mix(3.0, 2.0, lod);
  let p = uv * 3.0 + vec2<f32>(time * 0.1, time * 0.05);
  let n1 = fbm2(p, oct1);
  let n2 = fbm2(p * 2.0 + vec2<f32>(100.0, 0.0), oct2);
  let cloud = smoothstep(0.4 - intensity * 0.2, 0.7, n1) * 0.5;
  let turbulence = smoothstep(0.3, 0.6, n2) * intensity * 0.3;
  return cloud + turbulence;
}

// Branching lightning bolt
fn lightningBolt(uv: vec2<f32>, start: vec2<f32>, time: f32, seed: f32, treble: f32, minW: f32) -> f32 {
  var bolt = 0.0;
  let segments = 12;
  var pos = start;
  let downward = vec2<f32>(0.0, -1.0);

  for (var i: i32 = 0; i < segments; i = i + 1) {
    let fi = f32(i);
    var nextPos = pos + downward * (0.06 + hash21(vec2<f32>(fi, seed)) * 0.04);
    nextPos.x += sin(fi * 3.0 + seed * 5.0 + time * 10.0) * 0.03 * (1.0 + treble);

    let arc = lightningArc(uv, pos, nextPos, time, seed + fi, minW);
    bolt = max(bolt, arc);

    // Branching
    if (i > 3 && hash21(vec2<f32>(fi, seed + 1.0)) > 0.6) {
      let branchPos = nextPos + vec2<f32>(0.03, 0.0) * sign(hash21(vec2<f32>(fi, seed + 2.0)) - 0.5);
      let branch = lightningArc(uv, nextPos, branchPos, time, seed + fi + 10.0, minW);
      bolt = max(bolt, branch * 0.6);
    }
    pos = nextPos;
  }
  return bolt;
}

fn hueToRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  // Row 0 is the top of the screen: flip so +y is up (bolts fall from the cloud top).
  let uv01 = vec2<f32>(gid.xy) / res;
  let uv = vec2<f32>(uv01.x, 1.0 - uv01.y);
  let time = u.config.x;
  let mouse = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);
  let minW = 1.2 / max(res.y, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  // HEAD smoothed bass through extraBuffer[3], which never persists; plain bass now.
  let smoothBass = bass;

  // Parameters
  let eelCount = i32(u.zoom_params.x * 4.0 + 2.0);
  let stormIntensity = u.zoom_params.y * 1.5;
  let pulseSpeed = u.zoom_params.z * 3.0 + 1.0;
  let lightningFreq = u.zoom_params.w;

  // Recent clicks (startle stimulus for Idea 3)
  let rippleCount = min(u32(u.config.y), 50u);

  // Storm cloud background
  let cloud = stormCloud(uv, time, stormIntensity);
  var col = vec3<f32>(0.04, 0.05, 0.08);
  col += vec3<f32>(0.15, 0.18, 0.25) * cloud;

  // Eels and their discharges
  var eelMask = 0.0;
  var eelGlow = 0.0;
  var finMask = 0.0;
  var field = 0.0;
  var arcs = 0.0;
  var headShade = 0.0;
  var prevEelPos = vec2<f32>(0.0);
  var prevVolley = 0.0;

  for (var i: i32 = 0; i < eelCount; i = i + 1) {
    let fi = f32(i);
    let eelPos = eelPosition(fi, time, pulseSpeed, mouse);
    let facing = eelFacing(fi, time);

    // Idea 3: volley gate + click-startle (a touch near an eel forces a defensive discharge)
    var volley = eodVolley(fi, time, smoothBass);
    for (var r = 0u; r < rippleCount; r = r + 1u) {
      let ev = u.ripples[r];
      let age = max(time - ev.z, 0.0);
      let near = smoothstep(0.3, 0.05, length(vec2<f32>(ev.x, 1.0 - ev.y) - eelPos));
      volley = max(volley, exp(-age * 2.5) * near * (0.6 + 0.4 * step(0.5, fract(age * 7.0))));
    }

    // ═══ CHUNK: early-exit for off-screen eels (perf) ═══
    // Skip the SDF + glow evaluation entirely for eels whose body is
    // far outside this pixel's neighborhood — only their glow could
    // possibly reach, and at that range it's below visibility anyway.
    if (length(uv - eelPos) < 0.35) {
      let e = sdEel(uv, eelPos, facing, time, pulseSpeed, smoothBass);
      let d = e.d;

      // Eel body (brighter toward the electric-organ head end)
      let body = smoothstep(0.004, 0.0, d);
      eelMask += body;
      headShade = max(headShade, body * e.u);
      finMask = max(finMask, e.fin * (1.0 - body));

      // Eel glow
      let glow = 1.0 / (1.0 + d * d * 2000.0);
      eelGlow += glow * (0.5 + smoothBass * 0.5 + volley * 0.6);

      // Idea 2: dipole field around the electric organ — dim resting field (electrolocation),
      // flaring with the volley
      let span = (0.18 + smoothBass * 0.03) * max(abs(facing), 0.3);
      let dirSign = select(-1.0, 1.0, facing >= 0.0);
      let head = eelPos + vec2<f32>(span * 0.85 * dirSign, 0.0);
      let tail = eelPos - vec2<f32>(span * 0.85 * dirSign, 0.0);
      field += dipoleField(uv, head, tail, time, 0.8 + pulseSpeed * 0.6) * (0.12 + volley * 1.4) * (1.0 - body);
    }

    // Discharge arcs between nearby eels — only while either neighbour is in a volley
    if (i > 0) {
      let distBetween = length(eelPos - prevEelPos);
      if (distBetween < 0.4) {
        let arcSeed = fi * 3.7 + time * 0.1;
        let arc = lightningArc(uv, prevEelPos, eelPos, time, arcSeed, minW);
        arcs += arc * (0.3 + treble * 0.7) * smoothstep(0.05, 0.3, max(volley, prevVolley)) * 1.6;
      }
    }
    prevEelPos = eelPos;
    prevVolley = volley;
  }

  // Treble triggers lightning bolts from cloud top
  var bolts = 0.0;
  let boltTrigger = step(0.85, sin(time * 5.0 * lightningFreq) * 0.5 + 0.5 + treble * 0.3);
  if (boltTrigger > 0.0) {
    for (var b: i32 = 0; b < 3; b = b + 1) {
      let bf = f32(b);
      let startX = 0.2 + bf * 0.3 + sin(time + bf) * 0.1;
      // a stroke holds its shape for ~1/8 s instead of re-randomising every frame
      let boltTime = floor(time * 8.0) / 8.0;
      let bolt = lightningBolt(uv, vec2<f32>(startX, 0.9), boltTime, bf * 7.3 + boltTime, treble, minW);
      bolts += bolt * boltTrigger;
    }
  }

  // Eel color: bioluminescent blue-green with pulse
  let eelHue = 0.45 + smoothBass * 0.05 + sin(time * pulseSpeed) * 0.02;
  let eelCol = hueToRGB(eelHue) * (0.8 + mids * 0.4);

  // Arc color: electric violet-white
  let arcCol = vec3<f32>(0.7, 0.6, 1.0) * arcs * (1.0 + treble * 2.0);

  // Bolt color: bright white-blue
  let boltCol = vec3<f32>(0.9, 0.95, 1.0) * bolts * (1.5 + treble);

  // Combine
  col += eelCol * eelMask * (0.55 + 0.45 * headShade);
  col += eelCol * vec3<f32>(0.6, 0.9, 1.0) * finMask * 0.45;
  col += eelCol * eelGlow * 0.3;
  col += vec3<f32>(0.45, 0.75, 1.0) * field;
  col += arcCol;
  col += boltCol;

  // Storm turbulence glow from mids
  let turbGlow = fbm2(uv * 5.0 + time * 0.3, 3.0) * mids * stormIntensity;
  col += vec3<f32>(0.2, 0.15, 0.3) * turbGlow;

  // Display first; history in C is display colour.
  let disp = acesToneMap(max(col, vec3<f32>(0.0)) * 1.1);

  // Chromatic dispersion on lightning (strong) — exact loads, no filtering on rgba32float
  let cStr = 0.006 + treble * 0.01;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + 0.001);
  let maxC = vec2<i32>(res) - vec2<i32>(1);
  let pix = vec2<i32>(gid.xy);
  let offPx = cDir * cStr * res;
  let prevR = textureLoad(dataTextureC, clamp(pix + vec2<i32>(round(offPx * 1.5)), vec2<i32>(0), maxC), 0).r;
  let prevG = textureLoad(dataTextureC, clamp(pix + vec2<i32>(round(offPx * 1.0)), vec2<i32>(0), maxC), 0).g;
  let prevB = textureLoad(dataTextureC, clamp(pix - vec2<i32>(round(offPx * 0.8)), vec2<i32>(0), maxC), 0).b;

  // Temporal feedback
  let prev = textureLoad(dataTextureC, pix, 0);
  var fbCol = mix(disp, prev.rgb * 0.9, 0.06 + smoothBass * 0.02);

  // Blend chromatic offsets
  fbCol.r = mix(fbCol.r, prevR * 0.9, 0.05 + arcs * 0.05);
  fbCol.g = mix(fbCol.g, prevG * 0.9, 0.05 + bolts * 0.05);
  fbCol.b = mix(fbCol.b, prevB * 0.9, 0.05 + eelGlow * 0.03);
  fbCol = clamp(fbCol, vec3<f32>(0.0), vec3<f32>(1.0));

  // Semantic alpha: storm sky is near-opaque; eels, fins, field, arcs and bolts complete it
  let alpha = clamp(0.8 + cloud * 0.12 + eelMask * 0.2 + finMask * 0.1 + eelGlow * 0.08
                    + field * 0.2 + arcs * 0.2 + bolts * 0.2, 0.0, 1.0);

  // Depth: eels in foreground, clouds behind, lightning at mid-depth
  let depth = clamp(0.9 - eelMask * 0.3 - eelGlow * 0.2 + cloud * 0.15, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(fbCol, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));
}
