// ═══════════════════════════════════════════════════════════════════
//  Poincaré Tiling — Pass 1 (Hyperbolic Disk Tessellation Map)
//  Category: simulation
//  Features: multi-pass, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: iterated {p, q} hyperbolic geodesic circle-inversion tessellation & SU(1,1) disk automorphism; conformal gilded geodesic arcs & hyperbolic-metric click waves (Pass 2)
//  A packing: linear tiled RGB + packed (geodesic edge distance, reflection parity, disk mask) in A.a
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let d = dot(b, b);
  return vec2<f32>(dot(a, b), a.y * b.x - a.x * b.y) / max(d, 1e-6);
}

fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
  return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}

// Returns vec4(fundamentalUV.x, fundamentalUV.y, conformalEdgeDist, parity)
fn poincareTessellate(
  diskZ: vec2<f32>,
  sym: f32,
  time: f32,
  mouseDisk: vec2<f32>,
  held: f32
) -> vec4<f32> {
  let p = max(3.0, floor(sym * 10.0) + 3.0);
  // Dual vertex valence q chosen so (p - 2)(q - 2) > 4 (strictly hyperbolic {p, q})
  let q = select(4.0, select(5.0, 7.0, p < 3.5), p < 4.5);
  let alpha = PI / p;
  let beta = PI / q;
  let sinA = sin(alpha);
  let cosB = cos(beta);
  let radDenom = sqrt(max(cosB * cosB - sinA * sinA, 1e-5));
  let dc = cosB / radDenom;
  let rc = sinA / radDenom;
  let rc2 = rc * rc;
  let centerC = vec2<f32>(dc, 0.0);

  // ── Idea 1: SU(1,1) Poincaré disk automorphism f_a(z) = (z - a) / (1 - conj(a) * z) ──
  let orbitA = vec2<f32>(cos(time * 0.32), sin(time * 0.27)) * 0.26;
  var isoA = mix(orbitA, mouseDisk, held * 0.86);
  let aMag = length(isoA);
  isoA = select(isoA, isoA * (0.78 / max(aMag, 1e-4)), aMag > 0.78);
  let conjA = vec2<f32>(isoA.x, -isoA.y);
  var z = mobius(diskZ, vec2<f32>(1.0, 0.0), -isoA, -conjA, vec2<f32>(1.0, 0.0));

  // ── Idea 1: iterated hyperbolic Coxeter {p, q} sector fold + geodesic circle inversion ──
  let sectorSpan = 2.0 * alpha;
  var parity = 0.0;
  for (var iter = 0; iter < 10; iter = iter + 1) {
    let r = length(z);
    let rawAng = atan2(z.y, z.x) + PI;
    let sectorIdx = floor(rawAng / sectorSpan);
    let localAng = rawAng - (sectorIdx + 0.5) * sectorSpan;
    let foldMirror = f32(localAng < 0.0);
    parity = abs(parity - foldMirror);
    let foldedAng = abs(localAng);
    z = r * vec2<f32>(cos(foldedAng), sin(foldedAng));

    let diff = z - centerC;
    let d2 = dot(diff, diff);
    let insideCircle = d2 < rc2;
    let invZ = centerC + diff * (rc2 / max(d2, 1e-6));
    z = select(z, invZ, insideCircle);
    parity = select(parity, 1.0 - parity, insideCircle);
  }

  let inradius = max(dc - rc, 0.12);
  let fundamentalUV = clamp(vec2<f32>(0.5) + (z / (inradius * 2.15)), vec2<f32>(0.02), vec2<f32>(0.98));
  let geodesicDist = abs(length(z - centerC) - rc) / max(rc, 0.05);
  return vec4<f32>(fundamentalUV, clamp(geodesicDist, 0.0, 1.0), parity);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  let curvature = mix(0.62, 1.22, u.zoom_params.x) * (1.0 - audio.x * 0.06);
  let sym = clamp(u.zoom_params.y + audio.y * 0.04, 0.0, 1.0);
  let animRate = mix(0.2, 1.5, u.zoom_params.z) * (1.0 + audio.z * 0.18);
  let time = u.config.x * animRate;

  let diskP = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 2.04 * curvature;
  let rDisk = length(diskP);
  let inDisk = rDisk < 0.994;
  let safeDiskZ = diskP / max(1.0, rDisk / 0.992);

  let mouseDisk = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 1.55;
  let held = select(0.18, 1.0, u.zoom_config.w > 0.5);

  let tess = poincareTessellate(safeDiskZ, sym, time, mouseDisk, held);
  let sampleUV = select(uv, tess.xy, inDisk);
  let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // Pack geodesic edge distance [0.01..0.99] + parity * 2.0 inside disk; -1.0 outside disk
  let packedMeta = select(-1.0, tess.w * 2.0 + tess.z * 0.98 + 0.01, inDisk);
  textureStore(dataTextureA, pixel, vec4<f32>(col, packedMeta));
}
