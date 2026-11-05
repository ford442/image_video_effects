// ═══════════════════════════════════════════════════════════════════
//  Rainbow Icosahedron Cascade
//  Category: generative
//  Features: nested icosahedral shells, spectral facet coloring, orbit-trap
//            edges, audio-reactive scale, mouse orbit, temporal feedback
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-11-01
//  Ideas (2026-11): five-fold vertex beads (12 per shell); signed depth cue (front warm/bright, back cool/dim). REPAIR: HEAD rendered nothing (SDF sampled on the plane z = 2.8, outside every shell; alpha max 0.002) - now an orthographic wire projection; edge table had six edges missing and six duplicated.
//  Ideas: silhouette orbit-trap on edges; golden-angle yaw offset per shell; dual dodeca vertices (20 triangle-centroid sparks per shell); click shell pulse (ripple age breathes radius/thickness)
//  A packing: linear HDR history in A; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398874989484820;
const GOLDEN_ANGLE: f32 = 2.399963229728653;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

// Icosahedron vertices (unit sphere, golden-ratio construction)
fn icosaVerts() -> array<vec3<f32>, 12> {
  let t = PHI;
  return array<vec3<f32>, 12>(
    normalize(vec3<f32>(0.0, 1.0, t)),
    normalize(vec3<f32>(0.0, 1.0, -t)),
    normalize(vec3<f32>(0.0, -1.0, t)),
    normalize(vec3<f32>(0.0, -1.0, -t)),
    normalize(vec3<f32>(1.0, t, 0.0)),
    normalize(vec3<f32>(1.0, -t, 0.0)),
    normalize(vec3<f32>(-1.0, t, 0.0)),
    normalize(vec3<f32>(-1.0, -t, 0.0)),
    normalize(vec3<f32>(t, 0.0, 1.0)),
    normalize(vec3<f32>(-t, 0.0, 1.0)),
    normalize(vec3<f32>(t, 0.0, -1.0)),
    normalize(vec3<f32>(-t, 0.0, -1.0))
  );
}

fn icosaEdges() -> array<vec2<i32>, 30> {
  return array<vec2<i32>, 30>(
    vec2<i32>(0,8), vec2<i32>(0,9), vec2<i32>(0,4), vec2<i32>(0,6),
    vec2<i32>(1,10), vec2<i32>(1,11), vec2<i32>(1,4), vec2<i32>(1,6),
    vec2<i32>(2,8), vec2<i32>(2,9), vec2<i32>(2,5), vec2<i32>(2,7),
    vec2<i32>(3,10), vec2<i32>(3,11), vec2<i32>(3,5), vec2<i32>(3,7),
    vec2<i32>(4,8), vec2<i32>(4,10), vec2<i32>(5,8), vec2<i32>(5,10),
    vec2<i32>(6,9), vec2<i32>(6,11), vec2<i32>(7,9), vec2<i32>(7,11),
    // Repair: HEAD listed (8,2) (9,2) (10,3) (11,3) (4,1) (6,1), duplicates of (2,8) (2,9) (3,10) (3,11) (1,4)
    // (1,6), and so omitted six real edges. The six missing edges (the coordinate-axis pairs):
    vec2<i32>(0,2), vec2<i32>(1,3), vec2<i32>(4,6), vec2<i32>(5,7), vec2<i32>(8,10), vec2<i32>(9,11)
  );
}

// 20 triangular faces of the regular icosahedron (dual = dodeca vertices).
fn icosaFaces() -> array<vec3<i32>, 20> {
  return array<vec3<i32>, 20>(
    vec3<i32>(0, 4, 8), vec3<i32>(0, 8, 2), vec3<i32>(0, 2, 9), vec3<i32>(0, 9, 6), vec3<i32>(0, 6, 4),
    vec3<i32>(3, 5, 10), vec3<i32>(3, 10, 1), vec3<i32>(3, 1, 11), vec3<i32>(3, 11, 7), vec3<i32>(3, 7, 5),
    vec3<i32>(4, 8, 10), vec3<i32>(4, 10, 1), vec3<i32>(4, 1, 6),
    vec3<i32>(6, 1, 11), vec3<i32>(6, 9, 11),
    vec3<i32>(8, 2, 5), vec3<i32>(8, 5, 10),
    vec3<i32>(9, 2, 7), vec3<i32>(9, 7, 11),
    vec3<i32>(5, 2, 7)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let shellCount = i32(mix(2.0, 6.0, u.zoom_params.x));
  let shellGap = mix(0.12, 0.35, u.zoom_params.y);
  let edgeGlow = mix(0.004, 0.018, u.zoom_params.z);
  let hueDrift = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  // Wire projection (repair): HEAD evaluated a 3-D SDF at (uv * 2.2, 2.8), a plane farther from the origin than
  // every shell's circumradius, so nothing rendered. The object is now rotated (shell golden-angle yaw, then the
  // mouse/auto yaw and pitch) and projected; edges, dual centres and vertices are measured in 2-D, with the
  // depth of the nearest point kept for the depth cues.
  let pix = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.2;
  let yaw = (mouse.x - 0.5) * TAU + time * mix(0.08, 0.35, u.zoom_params.y);
  let pitch = (mouse.y - 0.5) * PI * 0.7 + sin(time * 0.25) * 0.15;

  var color = vec3<f32>(0.02, 0.01, 0.06);
  var alpha = 0.0;
  var minDist = 1e9;
  var facetHue = 0.0;

  let baseScale = 0.55 + bass * 0.15;
  let verts = icosaVerts();
  let edges = icosaEdges();
  let faces = icosaFaces();
  let rippleCount = min(u32(u.config.y), 50u);

  for (var s = 0; s < shellCount; s = s + 1) {
    let sf = f32(s);
    // Idea 2 — click shell pulse: each shell breathes as the ripple front
    // reaches a staggered radius (mouse orbit unchanged).
    var clickPulse = 0.0;
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
      let rp = u.ripples[ri];
      let age = time - rp.z;
      if (age >= 0.0 && age < 2.4) {
        let shellReach = 0.12 + sf * 0.14;
        clickPulse += exp(-abs(age * 0.55 - shellReach) * 9.0) * exp(-age * 1.15);
      }
    }
    let scale = (baseScale + sf * shellGap * (1.0 + mids * 0.2)) * (1.0 + clickPulse * 0.22);
    let thick = edgeGlow * (1.0 - sf * 0.08) * (1.0 + clickPulse * 0.45);

    // Project this shell's 12 vertices (3-D kept for the depth cues, 2-D for the distances).
    var pv: array<vec2<f32>, 12>;
    var pz: array<f32, 12>;
    for (var vi = 0; vi < 12; vi = vi + 1) {
      let w = rotX(rotY(rotY(verts[vi] * scale, sf * GOLDEN_ANGLE), yaw), pitch);
      let persp = 1.0 / max(1.0 - w.z * 0.12, 0.4);
      pv[vi] = w.xy * persp;
      pz[vi] = w.z;
    }

    // Nearest projected edge and the depth at that point.
    var dMin = 1e9;
    var zNear = 0.0;
    for (var ei = 0; ei < 30; ei = ei + 1) {
      let e = edges[ei];
      let a = pv[e.x];
      let b = pv[e.y];
      let ba = b - a;
      let h = clamp(dot(pix - a, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
      let dseg = length(pix - (a + ba * h));
      if (dseg < dMin) { dMin = dseg; zNear = mix(pz[e.x], pz[e.y], h); }
    }
    let d = dMin - thick;
    minDist = min(minDist, d);

    let edge = exp(-abs(d) * 80.0);
    let facet = exp(-max(d, 0.0) * 25.0);
    let hue = fract(sf * 0.17 + hueDrift + time * 0.04 + length(pix) * 0.3);
    // Idea 2 (2026-11): signed depth cue. Front edges are brighter and warmer, back edges dimmer and cooler;
    // HEAD's silhouette term below is symmetric in z.
    let depthCue = clamp(zNear / scale, -1.0, 1.0);
    let spec = spectral(hue + treble * 0.1 - depthCue * 0.05);
    let sil = 1.0 - abs(depthCue);
    let cueGain = 0.78 + 0.3 * depthCue;

    // Idea 1 — dual dodeca vertices: triangle centroids of the icosa faces (projected).
    var dualGlow = 0.0;
    for (var fi = 0; fi < 20; fi = fi + 1) {
      let fa = faces[fi];
      let centroid = verts[fa.x] + verts[fa.y] + verts[fa.z];
      let wd = rotX(rotY(rotY(normalize(centroid) * scale, sf * GOLDEN_ANGLE), yaw), pitch);
      let dd = length(pix - wd.xy / max(1.0 - wd.z * 0.12, 0.4));
      dualGlow += exp(-dd * dd * 420.0);
    }

    // Idea 1 (2026-11): five-fold vertex beads. The 12 vertices are where five edges meet; HEAD marked only
    // the 20 three-fold face centres.
    var beadGlow = 0.0;
    for (var bi = 0; bi < 12; bi = bi + 1) {
      let db = length(pix - pv[bi]);
      beadGlow += exp(-db * db * 900.0) * (0.6 + 0.4 * smoothstep(-0.6, 0.6, pz[bi] / scale));
    }

    color += spec * edge * (1.2 + bass * 0.5) * (0.55 + sil * 0.9) * cueGain;
    color += spec * facet * 0.25 * (0.6 + mids * 0.4);
    color += spec * dualGlow * (0.28 + treble * 0.22) * (1.0 + clickPulse);
    color += vec3<f32>(1.0, 0.96, 0.88) * beadGlow * (0.45 + treble * 0.4) * (1.0 + clickPulse * 0.6);
    facetHue = mix(facetHue, hue, edge);
    alpha = max(alpha, max(edge * (0.7 - sf * 0.08), max(dualGlow * 0.35, beadGlow * 0.5)));
  }

  // Inner glow core
  let core = exp(-length(pix) * 1.8) * spectral(facetHue + 0.1);
  color += core * (0.4 + treble * 0.3);

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.04 + mids * 0.02);
  alpha = clamp(alpha + length(core) * 0.3, 0.0, 1.0);
  let depthOut = clamp(1.0 - minDist * 3.0, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  color = acesToneMap(color * (1.15 + bass * 0.2));

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
