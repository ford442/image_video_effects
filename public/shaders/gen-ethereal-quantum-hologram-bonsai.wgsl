// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Hologram Bonsai
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            hologram, l-system, quantum, iridescence, curl-noise, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: prune-cut seal rings at terminal branch tips; north-facing moss lichen from bark normal vs up-light;
//         superposition collapse (per-branch presence flicker that locks inside the cursor well, seal rings and leaves
//         now sit on the true cylinder end); 3D root-to-tip sap pulse along height + branch reach (replaces screen-space ripple)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI : f32 = 3.14159265358979323846;
const MAX_STEPS : i32 = 80;
const MAX_DIST : f32 = 30.0;
const SURF_DIST : f32 = 0.001;

fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
  let a = normalize(axis);
  let s = sin(angle);
  let c = cos(angle);
  let oc = 1.0 - c;
  return mat3x3<f32>(
    c + a.x*a.x*oc,       a.x*a.y*oc - a.z*s,  a.x*a.z*oc + a.y*s,
    a.y*a.x*oc + a.z*s,   c + a.y*a.y*oc,      a.y*a.z*oc - a.x*s,
    a.z*a.x*oc - a.y*s,   a.z*a.y*oc + a.x*s,  c + a.z*a.z*oc
  );
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash3(i+vec3<f32>(0,0,0)), hash3(i+vec3<f32>(1,0,0)), u.x),
        mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
    mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
        mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise3(pp);
    pp = pp * 2.03 + vec3<f32>(1.7, 3.1, 5.3);
    a *= 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════
//  BONSAI L-SYSTEM SDF (simulated via recursive cylinders)
// ═══════════════════════════════════════════════════════════════
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn bonsaiBranch(p: vec3<f32>, pos: vec3<f32>, dir: vec3<f32>, branchLen: f32, radius: f32) -> f32 {
  let local = p - pos;
  // Align cylinder to direction
  let up = vec3<f32>(0.0, 1.0, 0.0);
  let rotAxis = cross(up, dir);
  let rotAngle = acos(clamp(dot(up, dir), -1.0, 1.0));
  var aligned = local;
  if(length(rotAxis) > 0.001) {
    aligned = rot3D(rotAxis, rotAngle) * local;
  }
  return sdCylinder(aligned, branchLen * 0.5, radius);
}

// Idea 2nd-pass A: superposition collapse. Each branch drifts between "present" and
// "partly un-collapsed" in smoothly crossfaded time slots; the cursor well observes
// (collapses) nearby branches to full presence. Scales branch radius, leaf and seal ring.
fn branchPresence(level: i32, b: i32, tip: vec3<f32>, time: f32, instability: f32) -> f32 {
  let slot = time * 0.45 + f32(level * 7 + b) * 0.37;
  let s0 = floor(slot);
  let k = smoothstep(0.75, 1.0, fract(slot));
  let h0 = hash3(vec3<f32>(f32(level), f32(b), s0));
  let h1 = hash3(vec3<f32>(f32(level), f32(b), s0 + 1.0));
  let q = mix(h0, h1, k);
  let absent = smoothstep(0.55, 0.85, q) * clamp(instability * 2.0, 0.0, 1.0) * 0.7;
  let wellPos = vec3<f32>((u.zoom_config.y - 0.5) * 4.0, u.zoom_config.z * 3.0, 0.0);
  let observed = smoothstep(1.1, 0.25, length(tip - wellPos));
  return mix(1.0 - absent, 1.0, observed);
}

fn bonsaiSDF(p: vec3<f32>, time: f32, complexity: f32, instability: f32) -> f32 {
  var d = 1000.0;

  // Curl noise displacement for holographic instability
  let disp = vec3<f32>(
    fbm(p * 1.5 + time * 0.3),
    fbm(p * 1.5 + time * 0.3 + 10.0),
    fbm(p * 1.5 + time * 0.3 + 20.0)
  ) * instability * 0.1;
  let pp = p + disp;

  // Main trunk
  d = smin(d, bonsaiBranch(pp, vec3<f32>(0.0, -1.5, 0.0), vec3<f32>(0.0, 1.0, 0.0), 3.0, 0.12), 0.05);

  // Branch levels
  let levels = i32(mix(2.0, 5.0, complexity));
  for(var level = 0; level < levels; level++) {
    let lvlF = f32(level);
    let branchY = -0.5 + lvlF * 0.6;
    let nBranches = i32(mix(2.0, 4.0, complexity)) + level;

    for(var b = 0; b < nBranches; b++) {
      let bf = f32(b);
      let angle = bf * (6.28 / f32(nBranches)) + lvlF * 1.3 + time * 0.1;
      let branchLen = 0.8 - lvlF * 0.15;
      let branchRad = 0.08 - lvlF * 0.015;
      let tilt = 0.3 + lvlF * 0.2;

      let dir = vec3<f32>(sin(angle) * tilt, cos(tilt), cos(angle) * tilt);
      let pos = vec3<f32>(sin(angle) * 0.1, branchY, cos(angle) * 0.1);

      // Idea 2nd-pass A: the cylinder is centred on pos, so its real end is pos + 0.5*len*dir
      let tipPos = pos + normalize(dir) * (branchLen * 0.5);
      let pres = branchPresence(level, b, tipPos, time, instability);

      d = smin(d, bonsaiBranch(pp, pos, dir, branchLen, branchRad * pres), 0.08);

      // Leaves (quantum droplets) - now seated on the true branch end
      let leafSize = (0.04 - lvlF * 0.008) * pres;
      d = smin(d, sdSphere(pp - tipPos, leafSize), 0.04);
    }
  }

  // Root system
  for(var r = 0; r < 5; r++) {
    let rf = f32(r);
    let angle = rf * (6.28 / 5.0) + time * 0.05;
    let rootDir = vec3<f32>(sin(angle) * 0.5, -0.8, cos(angle) * 0.5);
    let rootPos = vec3<f32>(sin(angle) * 0.05, -1.5, cos(angle) * 0.05);
    d = smin(d, bonsaiBranch(pp, rootPos, normalize(rootDir), 1.0, 0.06), 0.06);
  }

  return d;
}

fn calcNormal(p: vec3<f32>, time: f32, complexity: f32, instability: f32) -> vec3<f32> {
  let e = vec2<f32>(SURF_DIST * 2.0, 0.0);
  return normalize(vec3<f32>(
    bonsaiSDF(p + e.xyy, time, complexity, instability) - bonsaiSDF(p - e.xyy, time, complexity, instability),
    bonsaiSDF(p + e.yxy, time, complexity, instability) - bonsaiSDF(p - e.yxy, time, complexity, instability),
    bonsaiSDF(p + e.yyx, time, complexity, instability) - bonsaiSDF(p - e.yyx, time, complexity, instability)
  ));
}

// Prune-cut seal rings at terminal branch tips (concentric cross-section bands).
fn pruneSealRings(p: vec3<f32>, time: f32, complexity: f32, instability: f32) -> f32 {
  var rings = 0.0;
  let levels = i32(mix(2.0, 5.0, complexity));
  for (var level = 0; level < levels; level++) {
    let lvlF = f32(level);
    let branchY = -0.5 + lvlF * 0.6;
    let nBranches = i32(mix(2.0, 4.0, complexity)) + level;
    for (var b = 0; b < nBranches; b++) {
      let bf = f32(b);
      let angle = bf * (6.28 / f32(nBranches)) + lvlF * 1.3 + time * 0.1;
      let branchLen = 0.8 - lvlF * 0.15;
      let tilt = 0.3 + lvlF * 0.2;
      let dir = normalize(vec3<f32>(sin(angle) * tilt, cos(tilt), cos(angle) * tilt));
      let pos = vec3<f32>(sin(angle) * 0.1, branchY, cos(angle) * 0.1);
      let tipPos = pos + dir * (branchLen * 0.5);   // Idea 2nd-pass A: true cut end
      let pres = branchPresence(level, b, tipPos, time, instability);
      let toTip = p - tipPos;
      let distTip = length(toTip);
      let ringBands = 0.5 + 0.5 * sin(distTip * 110.0 - time * 1.4);
      let tipMask = smoothstep(0.14, 0.02, distTip) * smoothstep(0.0, 0.03, distTip);
      rings = max(rings, tipMask * ringBands * pres);
    }
  }
  return rings;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let uv = (fragCoord - 0.5 * res) / res.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let complexity = clamp((u.zoom_params.x - 1.0) / 6.0, 0.0, 1.0);
  let instability = clamp(u.zoom_params.y / 2.0, 0.0, 1.0);
  let glow = clamp((u.zoom_params.z - 0.5) / 9.5, 0.0, 1.0);
  let audioReact = clamp(u.zoom_params.w / 3.0, 0.0, 1.0);

  // Camera
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y;  // Flip Y: screen top = up
  let camAng = time * 0.05 + mouseUV.x * 0.3;
  let camDist = 4.0;
  let ro = vec3<f32>(
    cos(camAng) * camDist,
    1.0 + mouseY * 1.0,
    sin(camAng) * camDist
  );
  let ta = vec3<f32>(0.0, 0.5, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
  let vv = cross(uu, ww);
  let rd = normalize(ww + uu * uv.x + vv * uv.y);

  // Mouse gravity well (quantum gardener)
  let mouseWorld = vec3<f32>(
    (mouseUV.x - 0.5) * 4.0,
    mouseY * 3.0,
    0.0
  );

  // Raymarch
  var t = 0.0;
  var d = 0.0;
  for(var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * t;
    let pp = p;
    // Apply mouse gravity lensing
    let toMouse = mouseWorld - p;
    let mDist = length(toMouse);
    let lensing = toMouse / (mDist * mDist + 0.1) * 0.05 * length(u.zoom_config.yz);
    d = bonsaiSDF(pp + lensing, time, complexity, instability);
    if(d < SURF_DIST || t > MAX_DIST) { break; }
    t += d * 0.8;
  }

  // Shading
  var col = vec3<f32>(0.0);
  if(t < MAX_DIST) {
    let p = ro + rd * t;
    let n = calcNormal(p, time, complexity, instability);

    // Lighting
    let lightDir = normalize(vec3<f32>(2.0, 3.0, -1.0));
    let diff = max(dot(n, lightDir), 0.0);
    let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);
    let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);

    // Holographic iridescence (jade to magenta)
    let holoHue = fract(dot(p, vec3<f32>(1.0, 2.3, 3.7)) * 0.2 + time * 0.15);
    let holoCol = mix(
      vec3<f32>(0.0, 0.5, 0.2),   // Deep jade
      vec3<f32>(0.8, 0.1, 0.6),   // Luminous magenta
      holoHue
    );

    // Base bark color
    let barkCol = mix(
      vec3<f32>(0.1, 0.08, 0.05),
      holoCol,
      fresnel * instability
    );

    col = barkCol * (diff * 0.6 + 0.3) + spec * vec3<f32>(0.8, 0.9, 1.0) * 0.5;

    // Chromatic aberration (holographic glitch)
    let glitch = noise3(p * 5.0 + time * 2.0) * instability * 0.3;
    col.r += glitch * 0.2;
    col.b -= glitch * 0.1;

    // Quantum droplet glow (leaves)
    let leafGlow = fresnel * glow * vec3<f32>(0.3, 0.8, 0.5);
    col += leafGlow;

    // Audio holographic shimmer
    col += vec3<f32>(0.1, 0.2, 0.3) * bass * audioReact * fresnel;

    // Prune-cut seal rings at terminal branch tips
    let pruneRings = pruneSealRings(p, time, complexity, instability);
    col += vec3<f32>(0.35, 0.18, 0.12) * pruneRings * (0.45 + bass * 0.2);

    // North-facing moss lichen (bark normal vs up-light)
    let upLight = normalize(vec3<f32>(0.12, 0.92, -0.28));
    let mossFacing = smoothstep(0.38, 0.8, dot(n, upLight));
    let mossTex = fbm(p * vec3<f32>(6.0, 4.5, 6.0) + vec3<f32>(0.0, time * 0.04, 0.0));
    let mossCol = vec3<f32>(0.07, 0.24, 0.08) * mossTex;
    col = mix(col, col * 0.68 + mossCol, mossFacing * 0.65);

    // Idea 2nd-pass B: 3D sap pulse. Front travels root tip -> trunk -> branch reach
    // (height above the root base plus lateral reach), so it follows the wood, not the screen.
    let sapS = p.y + 2.3 + length(p.xz) * 0.7;
    let sapFront = fract(time * 0.22) * 6.0 - 0.6;
    let sapDx = (sapS - sapFront) * 2.6;
    let sapBand = exp(-sapDx * sapDx);
    let sapTail = exp(-max(sapFront - sapS, 0.0) * 1.8) * step(sapS, sapFront) * 0.25;
    let sapAmp = 0.16 + bass * audioReact * 0.55;
    col += vec3<f32>(0.08, 0.85, 0.55) * (sapBand + sapTail) * sapAmp * (0.4 + fresnel);

    // Distance fade
    col *= exp(-t * 0.08);
  }

  // Ambient glow / background
  let bgGrad = mix(
    vec3<f32>(0.02, 0.03, 0.04),
    vec3<f32>(0.05, 0.08, 0.1),
    uv.y * 0.5 + 0.5
  );
  col = mix(bgGrad, col, smoothstep(MAX_DIST, 0.0, t));

  // Temporal feedback
  let previous = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  col = mix(previous.rgb, acesToneMap(max(col, vec3<f32>(0.0)) * 1.4), 0.3);

  let finalDepth = clamp(0.95 - t * 0.03, 0.0, 1.0);
  let hitCoverage = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), t < MAX_DIST);
  let finalAlpha = clamp(max(hitCoverage, previous.a * 0.94), 0.0, 1.0);
  let packed = vec4<f32>(col, finalAlpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), packed);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), packed);
}
