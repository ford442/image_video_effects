// ═══════════════════════════════════════════════════════════════════
//  Neon Stellated Octahedron
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14, 2026-11-01
//  Ideas (2026-11): face-identity rim (argmax of the four half-spaces names the boundary face; 8 hues); neon tube profile (white-hot core + inverse-square halo, 12.2F)
//  Ideas: tomographic section through the true solid compound (each tetra = 4 face half-spaces) sweeping triangle -> hexagram, with the shared regular-octahedron core (tetraA AND tetraB) lit apart from the 8 stellation spikes, click = local slice dent, mouse-held = lock slice at the central hexagram; Kepler cube hull: the 8 star tips are cube vertices, drawn as the cube's 12-edge frame with corner beacons in bipartite parity colors (tetra A warm / tetra B cool)
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Star Scale, y=Spin Speed, z=Neon Power, w=Color Shift

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neon(t: f32, intensity: f32) -> vec3<f32> {
  let base = 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
  return base * (1.0 + intensity * 2.0);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
  return dot(p, n) + h;
}

fn sdSegment3(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> f32 {
  let pa = p - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Regular tetrahedron vertices
fn tetraVerts(s: f32) -> array<vec3<f32>, 4> {
  return array<vec3<f32>, 4>(
    vec3<f32>(1.0, 1.0, 1.0) * s,
    vec3<f32>(1.0, -1.0, -1.0) * s,
    vec3<f32>(-1.0, 1.0, -1.0) * s,
    vec3<f32>(-1.0, -1.0, 1.0) * s
  );
}

fn tetraEdges() -> array<vec2<i32>, 6> {
  return array<vec2<i32>, 6>(
    vec2<i32>(0,1), vec2<i32>(0,2), vec2<i32>(0,3),
    vec2<i32>(1,2), vec2<i32>(1,3), vec2<i32>(2,3)
  );
}

fn stellatedOctaSDF(p: vec3<f32>, scale: f32, edgeThick: f32) -> vec3<f32> {
  let verts = tetraVerts(scale);
  let edges = tetraEdges();
  var e0 = 1e9;
  var e1 = 1e9;
  var minFace = 1e9;

  for (var layer = 0; layer < 2; layer = layer + 1) {
    let flip = select(1.0, -1.0, layer == 1);
    var layerEdge = 1e9;
    for (var i = 0; i < 6; i = i + 1) {
      let e = edges[i];
      let a = verts[e.x] * flip;
      let b = verts[e.y] * flip;
      layerEdge = min(layerEdge, sdSegment3(p, a, b) - edgeThick);
    }
    if (layer == 0) {
      e0 = layerEdge;
    } else {
      e1 = layerEdge;
    }
    let f0 = sdPlane(p, normalize(vec3<f32>(1.0, 1.0, 1.0)), -scale * 0.577 * flip);
    let f1 = sdPlane(p, normalize(vec3<f32>(-1.0, 1.0, 1.0)), -scale * 0.577 * flip);
    minFace = min(minFace, abs(f0));
    minFace = min(minFace, abs(f1));
  }
  let ridge = max(e0, e1);
  return vec3<f32>(min(e0, e1), minFace, ridge);
}

// Solid regular tetrahedron as the intersection of its 4 face half-spaces.
// Outward face normals are the negated vertex directions; inradius = s*sqrt(3)/3.
fn tetraSolid(p: vec3<f32>, s: f32, flip: f32) -> f32 {
  let k = 0.57735027;
  let q = p * flip;
  let d0 = dot(q, vec3<f32>(-1.0, -1.0, -1.0));
  let d1 = dot(q, vec3<f32>(-1.0, 1.0, 1.0));
  let d2 = dot(q, vec3<f32>(1.0, -1.0, 1.0));
  let d3 = dot(q, vec3<f32>(1.0, 1.0, -1.0));
  return max(max(d0, d1), max(d2, d3)) * k - s * k;
}

// 2026-11 Idea 1: which of the tetrahedron's four face half-spaces is the maximum, i.e. which face the
// section boundary lies on (tetraSolid takes the max and discards the index).
fn tetraFaceIdx(p: vec3<f32>, flip: f32) -> f32 {
  let q = p * flip;
  let d0 = dot(q, vec3<f32>(-1.0, -1.0, -1.0));
  let d1 = dot(q, vec3<f32>(-1.0, 1.0, 1.0));
  let d2 = dot(q, vec3<f32>(1.0, -1.0, 1.0));
  let d3 = dot(q, vec3<f32>(1.0, 1.0, -1.0));
  var idx = 0.0;
  var m = d0;
  if (d1 > m) { m = d1; idx = 1.0; }
  if (d2 > m) { m = d2; idx = 2.0; }
  if (d3 > m) { idx = 3.0; }
  return idx;
}

// Hollow box frame (cube edges) — iq
fn sdBoxFrame(p: vec3<f32>, b: vec3<f32>, e: f32) -> f32 {
  let p1 = abs(p) - b;
  let q = abs(p1 + e) - e;
  return min(min(
    length(max(vec3<f32>(p1.x, q.y, q.z), vec3<f32>(0.0))) + min(max(p1.x, max(q.y, q.z)), 0.0),
    length(max(vec3<f32>(q.x, p1.y, q.z), vec3<f32>(0.0))) + min(max(q.x, max(p1.y, q.z)), 0.0)),
    length(max(vec3<f32>(q.x, q.y, p1.z), vec3<f32>(0.0))) + min(max(q.x, max(q.y, p1.z)), 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;

  let starScale = mix(0.4, 0.9, u.zoom_params.x) * (1.0 + bass * 0.12);
  let spin = time * mix(0.1, 0.5, u.zoom_params.y);
  let neonPower = mix(0.5, 2.0, u.zoom_params.z);
  let colorShift = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);

  // Tomographic slice depth: the viewing plane sweeps through the compound
  // (tip triangles -> hexagram at centre). Mouse-held locks it at the centre.
  let vertR = starScale * 1.7320508;
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  var slice = mix(sin(time * 0.23) * vertR * 0.92, 0.0, held);

  // Click ripples dent the slicing plane locally, exposing a deeper section.
  var rippleGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 3.0) {
      let dv = (uv01 - rp.xy) * vec2<f32>(aspect, 1.0);
      let front = length(dv) - age * 0.45;
      let env = exp(-front * front * 40.0) * exp(-age * 1.2);
      slice += env * vertR * 0.45 * (1.0 + bass * 0.3);
      rippleGlow += env;
    }
  }

  var p = vec3<f32>((uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.2, slice);
  let yaw = (mouse.x - 0.5) * TAU + spin;
  let pitch = (mouse.y - 0.5) * PI * 0.6 + sin(time * 0.3) * 0.1;
  p = rotY(rotX(p, pitch), yaw);

  // Kaleidoscopic 6-fold symmetry in XY
  let ang = atan2(p.y, p.x);
  let seg = TAU / 6.0;
  let ka = abs(fract(ang / seg + 0.5) - 0.5) * seg;
  let r = length(p.xy);
  p = vec3<f32>(cos(ka) * r, sin(ka) * r, p.z);

  let edgeThick = mix(0.006, 0.02, u.zoom_params.z);
  let sd = stellatedOctaSDF(p, starScale, edgeThick);
  let edge = exp(-abs(sd.x) * 90.0);
  let facet = exp(-sd.y * 15.0) * 0.35 * (1.0 - edge);
  let ridge = exp(-abs(sd.z) * 70.0);

  let hue = fract(atan2(p.z, p.x) / TAU + length(p) * 0.4 + colorShift + time * 0.06);
  let hue2 = fract(hue + 0.5 + mids * 0.1);

  var color = vec3<f32>(0.01, 0.005, 0.03);
  color += neon(hue, neonPower * edge) * edge * (1.0 + bass * 0.5);
  color += neon(hue2, neonPower * facet) * facet * (0.8 + treble * 0.4);
  color += neon(hue + 0.12, neonPower) * ridge * 0.85 * (0.7 + bass * 0.4);

  // Idea 2 (2026-11): neon tube profile. A real tube has a white-hot core and a long 1/r^2 halo, not a
  // Gaussian: soft inverse-square 0.0015 / (d^2 + 0.0006) (12.2F) plus a thin white core.
  let tubeHalo = 0.0015 / (sd.x * sd.x + 0.0006);
  let tubeCore = exp(-abs(sd.x) * 300.0);
  color += neon(hue, neonPower * 0.5) * tubeHalo * 0.06 * (1.0 + bass * 0.4);
  color += vec3<f32>(1.0, 0.97, 0.92) * tubeCore * 0.5 * neonPower;

  // Stellate spike glow at vertices
  let spike = exp(-length(p) * 2.5) * neon(hue + 0.33, 0.8) * 0.3;
  color += spike * (1.0 + treble * 0.5);

  // ═══ Idea 1: section through the true solid compound ═══
  let tA = tetraSolid(p, starScale, 1.0);
  let tB = tetraSolid(p, starScale, -1.0);
  let core = max(tA, tB);                 // shared regular octahedron
  let aa = 0.012;
  let fillA = smoothstep(aa, -aa, tA);
  let fillB = smoothstep(aa, -aa, tB);
  let coreFill = smoothstep(aa, -aa, core);
  let spikeA = fillA * (1.0 - coreFill);
  let spikeB = fillB * (1.0 - coreFill);
  let sectionRim = exp(-abs(min(tA, tB)) * 80.0);
  let coreRim = exp(-abs(core) * 95.0) * max(fillA, fillB);
  let hueA = fract(colorShift + time * 0.04);
  let hueB = fract(hueA + 0.5);
  // Thickness proxy: deeper inside the solid = denser neon glass
  let thickA = clamp(-tA * 5.0, 0.0, 1.0);
  let thickB = clamp(-tB * 5.0, 0.0, 1.0);
  color += neon(hueA, neonPower * 0.4) * spikeA * (0.12 + thickA * 0.3) * (1.0 + bass * 0.4);
  color += neon(hueB, neonPower * 0.4) * spikeB * (0.12 + thickB * 0.3) * (1.0 + bass * 0.4);
  color += vec3<f32>(0.75, 0.7, 1.0) * coreFill * (0.1 + clamp(-core * 6.0, 0.0, 1.0) * 0.25) * (0.8 + mids * 0.5);
  // Idea 1 (2026-11): the rim takes the hue of the face it lies on (4 faces x 2 tetrahedra = 8 hues).
  let faceId = select(tetraFaceIdx(p, -1.0) + 4.0, tetraFaceIdx(p, 1.0), tA < tB);
  let faceHue = fract(colorShift + faceId * 0.125 + time * 0.03);
  color += mix(neon(hue + 0.25, neonPower * 0.6), neon(faceHue, neonPower * 0.6), 0.7) * sectionRim * 0.35 * (1.0 + rippleGlow * 1.5);
  color += vec3<f32>(0.9, 0.85, 1.0) * coreRim * 0.5 * neonPower * (1.0 + treble * 0.4);

  // ═══ Idea 2: Kepler cube hull + bipartite corner beacons ═══
  let hull = sdBoxFrame(p, vec3<f32>(starScale), edgeThick * 0.5);
  let hullGlow = exp(-abs(hull) * 110.0) * 0.4;
  let cornerD = length(abs(p) - vec3<f32>(starScale));
  let parity = p.x * p.y * p.z;             // >0: tetra A tip, <0: tetra B tip
  let beacon = exp(-cornerD * 14.0) * (0.35 + treble * 0.65);
  let beaconCol = select(neon(hueB, 1.0), neon(hueA, 1.0), parity > 0.0);
  color += vec3<f32>(0.55, 0.6, 0.8) * hullGlow * neonPower;
  color += beaconCol * beacon * 0.6;

  let cc = clamp(pixel, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, cc, 0);
  color = mix(color, prev.rgb, 0.04);

  let solidCover = max(fillA, fillB);
  let alpha = clamp(edge * 0.9 + facet * 0.4 + length(spike) * 0.3 + ridge * 0.25
                    + solidCover * 0.45 + sectionRim * 0.3 + hullGlow * 0.3 + beacon * 0.3, 0.0, 1.0);
  let depthOut = clamp(edge * 0.6 + facet * 0.4 + ridge * 0.2 + solidCover * (0.3 + coreFill * 0.2), 0.0, 1.0);
  let display = acesToneMap(max(color, vec3<f32>(0.0)) * (1.2 + mids * 0.1));
  let finalColor = vec4<f32>(display, alpha);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalColor);
}
