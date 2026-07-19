// ═══════════════════════════════════════════════════════════════════
//  Sierpinski Tetrahedron
//  Category: generative
//  Features: procedural, fractal, sierpinski, tetrahedron, 3d-projection,
//            audio-reactive, mouse-driven, chromatic-aberration, aces-tonemap,
//            temporal-feedback, depth-aware, domain-warping, multi-orbit-trap,
//            lod-noise, branchless-argmin, squared-sdf
//  Complexity: High
//  Created: 2026-05-31
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2), 3), fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8), 3));
  return p + 0.25 * q + 0.15 * r;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.45;
  let n0 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
  let n1 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
  let n2 = fbm(p + vec2<f32>(0.0, e) + t, 4);
  let n3 = fbm(p - vec2<f32>(0.0, e) + t, 4);
  return vec2<f32>(n3 - n2, n0 - n1) / (2.0 * e);
}

fn worley2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  var md = 1.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let g = vec2<f32>(f32(x), f32(y));
      let o = hash21(i + g);
      let r = g + vec2<f32>(o, hash21(i + g + 17.3)) - f;
      md = min(md, dot(r, r));
    }
  }
  return sqrt(md);
}

fn schlickFresnel(cosTheta: f32, r0: f32) -> f32 {
  return r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
}

fn spring_damper(prev: f32, goal: f32, vel: ptr<function, f32>, k: f32, d: f32) -> f32 {
  let force = (goal - prev) * k;
  (*vel) = (*vel) + force;
  (*vel) = (*vel) * (1.0 - d);
  return prev + (*vel);
}

fn ignDither(pixel: vec2<i32>) -> f32 {
  return fract(52.9829189 * fract(0.06711056 * f32(pixel.x) + 0.00583715 * f32(pixel.y))) * 2.0 / 255.0;
}

fn sdCapsuleSq(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  let d = pa - ba * h;
  return dot(d, d);
}

fn jewelColor(idx: f32, shade: f32) -> vec3<f32> {
  let j0 = vec3<f32>(0.0, 0.6, 0.3) * shade;
  let j1 = vec3<f32>(0.0, 0.3, 0.7) * shade;
  let j2 = vec3<f32>(0.7, 0.1, 0.2) * shade;
  let j3 = vec3<f32>(0.5, 0.2, 0.6) * shade;
  let f = fract(idx);
  let c1 = mix(j0, j1, clamp(f * 3.0, 0.0, 1.0));
  let c2 = mix(j1, j2, clamp((f - 0.33) * 3.0, 0.0, 1.0));
  let c3 = mix(j2, j3, clamp((f - 0.66) * 3.0, 0.0, 1.0));
  return select(select(c3, c2, f < 0.66), c1, f < 0.33);
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let angle = atan2(uv.y - 0.5, uv.x - 0.5);
  let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
  return vec3<f32>(
    color.r * (1.0 + shift.x * 0.8),
    color.g,
    color.b * (1.0 - shift.y * 0.5)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;

  let bassRaw = plasmaBuffer[0].x;
  let midsRaw = plasmaBuffer[0].y;
  let trebleRaw = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  var bassVel = 0.0;
  var midsVel = 0.0;
  var trebleVel = 0.0;
  let bass = spring_damper(extraBuffer[0], bassRaw, &bassVel, 0.12, 0.08);
  let mids = spring_damper(extraBuffer[1], midsRaw, &midsVel, 0.1, 0.09);
  let treble = spring_damper(extraBuffer[2], trebleRaw, &trebleVel, 0.14, 0.07);
  extraBuffer[0] = bass;
  extraBuffer[1] = mids;
  extraBuffer[2] = treble;

  let clickPulse = select(0.0, 1.0, u.zoom_config.w > 0.5);
  extraBuffer[3] = mix(extraBuffer[3], mouse.x, 0.15);
  extraBuffer[4] = mix(extraBuffer[4], mouse.y, 0.15);
  extraBuffer[5] = mix(extraBuffer[5], clickPulse, 0.2);

  // Distance-based LOD: lower quality at the screen edges.
  let centerDist = length(uv01 - 0.5);
  let lod = 1.0 - clamp(centerDist * 2.0, 0.0, 1.0);

  let recCtrl = clamp(u.zoom_params.x + bass * 0.25, 0.0, 1.0) * mix(0.65, 1.0, lod);
  let recursion = i32(mix(4.0, 10.0, recCtrl));

  let rotSpeed = mix(0.1, 0.6, u.zoom_params.y) * (1.0 + bass * 0.5);
  let persp = mix(1.5, 4.0, u.zoom_params.z);
  let caAmt = u.zoom_params.w;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthFactor = mix(0.5, 1.5, depth);

  // LOD noise: fewer octaves in the periphery.
  let warpOct = i32(mix(2.0, 4.0, lod));
  let warpUv = domainWarp(uv01 * 3.0 + vec2<f32>(time * 0.03), time * 0.05);
  let warpField = fbm(warpUv * 2.0, warpOct);
  let curlField = curlNoise(uv01 * 4.0 + vec2<f32>(time * 0.02), time * 0.04);
  let cellAccent = worley2(uv01 * 18.0 + curlField * 0.5);
  let aspect = res.x / max(res.y, 1.0);
  var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p += (warpField - 0.5) * (0.04 + bass * 0.04);
  p += curlField * (0.03 + mids * 0.02);
  p += (mouse - vec2<f32>(0.5)) * extraBuffer[5] * 0.08;

  let yaw = (mouse.x - 0.5) * TAU + time * rotSpeed;
  let pitch = (mouse.y - 0.5) * PI * 0.8 + sin(time * 0.3) * 0.2;

  const V = array<vec3<f32>, 4>(
    vec3<f32>(0.0, 1.0, 0.0),
    vec3<f32>(-0.816, -0.333, 0.577),
    vec3<f32>(0.816, -0.333, 0.577),
    vec3<f32>(0.0, -0.333, -1.155)
  );
  const E = array<vec2<u32>, 6>(
    vec2<u32>(0u, 1u), vec2<u32>(0u, 2u), vec2<u32>(0u, 3u),
    vec2<u32>(1u, 2u), vec2<u32>(1u, 3u), vec2<u32>(2u, 3u)
  );

  // Inline rotation to keep matrix math out of the fractal loop.
  let cx = cos(pitch); let sx = sin(pitch);
  let cy = cos(yaw);   let sy = sin(yaw);
  var rp = vec3<f32>(p.x * persp * depthFactor, p.y * persp * depthFactor, 2.5);
  rp = vec3<f32>(rp.x, cx * rp.y - sx * rp.z, sx * rp.y + cx * rp.z);
  rp = vec3<f32>(cy * rp.x + sy * rp.z, rp.y, -sy * rp.x + cy * rp.z);

  var point = rp;
  var minTrapSq = 1e9;
  var trapIdx = 0.0;

  for (var i = 0; i < recursion; i = i + 1) {
    let d0 = dot(point - V[0], point - V[0]);
    let d1 = dot(point - V[1], point - V[1]);
    let d2 = dot(point - V[2], point - V[2]);
    let d3 = dot(point - V[3], point - V[3]);

    // Branchless argmin using captured comparisons.
    var nearest = d0; var vi = 0u;
    let c1 = d1 < nearest; nearest = select(nearest, d1, c1); vi = select(vi, 1u, c1);
    let c2 = d2 < nearest; nearest = select(nearest, d2, c2); vi = select(vi, 2u, c2);
    let c3 = d3 < nearest; nearest = select(nearest, d3, c3); vi = select(vi, 3u, c3);

    var edgeTrapSq = 1e9;
    for (var e = 0u; e < 6u; e = e + 1u) {
      let ab = E[e];
      edgeTrapSq = min(edgeTrapSq, sdCapsuleSq(point, V[ab.x], V[ab.y]));
    }

    let lenP = length(point);
    let shellD = abs(lenP - 0.9);
    let trapSq = min(min(nearest, edgeTrapSq * 0.49), shellD * shellD * 0.25);

    // Branchless update of best orbit trap.
    let better = trapSq < minTrapSq;
    minTrapSq = select(minTrapSq, trapSq, better);
    trapIdx = select(trapIdx, f32(vi), better);

    // Early exit once we are already extremely close to the structure.
    if (minTrapSq < 1e-6) { break; }

    point = (point + V[vi]) * 0.5;
  }

  let prev = textureLoad(dataTextureC, pixel, 0);
  var minTrap = sqrt(minTrapSq);
  minTrap = mix(minTrap, prev.r, 0.03 + mids * 0.02);

  let density = exp(-minTrap * 12.0);
  let edge = exp(-abs(minTrap - 0.05) * 30.0);

  var color = jewelColor(trapIdx * 0.25 + mids * 0.1 + treble * 0.05, 0.7 + density * 0.6);
  let spec = pow(edge, 4.0) * (0.8 + bass * 0.5);
  color = color + vec3<f32>(0.9, 0.85, 0.8) * spec;

  let viewDir = normalize(vec3<f32>(p.x, p.y, 1.0));
  let fresnel = schlickFresnel(clamp(dot(viewDir, vec3<f32>(0.0, 0.0, 1.0)), 0.0, 1.0), 0.04);
  color = color + vec3<f32>(0.85, 0.92, 1.0) * fresnel * density * (0.35 + treble * 0.2);

  let bgGlow = vec3<f32>(0.05, 0.08, 0.12) * warpField * (1.0 - density);
  color = color + bgGlow;
  color = color + vec3<f32>(0.12, 0.18, 0.28) * (1.0 - cellAccent) * 0.15 * (1.0 - density);

  color = genChromaticShift(color, uv01, caAmt * 0.02 * (1.0 + bass), time);
  color = acesToneMap(color * (1.2 + treble * 0.1));
  color = color + vec3<f32>(ignDither(pixel));

  let alpha = clamp(density * (f32(recursion) / 10.0) * depthFactor * (0.85 + extraBuffer[5] * 0.15), 0.0, 1.0);
  let depthOut = clamp(0.3 + density * 0.7, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(minTrap, trapIdx, density, alpha));
}
