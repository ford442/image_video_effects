// ═══════════════════════════════════════════════════════════════════
//  Mandelbox Explorer
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: running-derivative distance estimate with 3D gradient-normal metallic lighting; fold-itinerary coloring (box reflections vs sphere inversions)
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
  config: vec4<f32>,       // x=time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=time, yz=mouse uv, w=mouse down
  zoom_params: vec4<f32>,  // x=Box Scale, y=Iterations, z=Slice Thickness, w=Specular
  ripples: array<vec4<f32>, 50>,
};

// Mandelbox: boxFold + sphereFold + scale, typical scale ≈ 2.5
fn boxFold(v: vec3<f32>) -> vec3<f32> {
  return clamp(v, vec3<f32>(-1.0), vec3<f32>(1.0)) * 2.0 - v;
}

fn sphereFold(v: vec3<f32>) -> vec3<f32> {
  let r2 = dot(v, v);
  if (r2 < 0.25) {
    return v * 4.0;
  } else if (r2 < 1.0) {
    return v / r2;
  }
  return v;
}

fn fractalDimension(orbitMin: f32) -> f32 {
  // 3D fractal dimension of Mandelbox boundary: ~2.0-2.5
  return 2.0 + orbitMin * 0.5;
}

// IDEA 1 helper: Mandelbox distance estimate via running derivative.
// dr tracks |d z / d pos|: box folds are isometries (dr unchanged), sphere
// folds scale by their fold factor, the scale step multiplies by |scale|.
// DE = |z| / |dr| is a conservative (Lipschitz-bounded) boundary distance.
fn mandelboxDE(pos: vec3<f32>, c: vec3<f32>, scale: f32, minR2: f32, iters: i32) -> f32 {
  var z = pos;
  var dr = 1.0;
  for (var i = 0; i < iters; i = i + 1) {
    z = boxFold(z);
    let r2 = dot(z, z);
    if (r2 < minR2) {
      let f = 1.0 / minR2;
      z = z * f;
      dr = dr * f;
    } else if (r2 < 1.0) {
      let f = 1.0 / r2;
      z = z * f;
      dr = dr * f;
    }
    z = z * scale + c;
    dr = dr * abs(scale) + 1.0;
    if (dot(z, z) > 10000.0) { break; }
  }
  return length(z) / max(abs(dr), 1e-4);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let held = clamp(u.zoom_config.w, 0.0, 1.0);

  let scale = mix(-2.5, 2.5, clamp(u.zoom_params.x + bass * 0.06, 0.0, 1.0));
  let maxIter = i32(mix(30.0, 90.0, u.zoom_params.y));
  // Holding the mouse scrubs the slice through the third axis with mouse.y
  let sliceThick = mix(0.0, 0.6, u.zoom_params.z) + held * (mouse.y - 0.5) * 1.2;
  let specular = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 4.0;

  let angle = (mouse.x - 0.5) * 3.14159;
  let ca = cos(angle);
  let sa = sin(angle);
  p = vec2<f32>(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

  // Click ripples: a fold-radius shock — the sphere fold's inner radius
  // swells as a ring passes, briefly re-wiring the inversion shells.
  var foldShock = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.0) {
      let d = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      foldShock = max(foldShock, exp(-abs(d - age * 0.45) * 40.0) * exp(-age * 1.5));
    }
  }
  let minR2 = 0.25 * (1.0 + foldShock * 1.4);

  var z = vec3<f32>(p.x, p.y, sliceThick);
  let c = vec3<f32>(p.x, p.y, 0.0);
  var orbitMin = 1e9;
  var orbitAvg = 0.0;
  var boxReflections = 0.0;
  var shellInversions = 0.0;
  var coreScalings = 0.0;
  var itersRun = 0.0;

  for (var i = 0; i < maxIter; i = i + 1) {
    // IDEA 2 bookkeeping: which folds actually fired this iteration
    let a = abs(z);
    boxReflections = boxReflections + step(1.0, a.x) + step(1.0, a.y) + step(1.0, a.z);
    z = boxFold(z);
    let r2 = dot(z, z);
    if (r2 < minR2) {
      coreScalings = coreScalings + 1.0;
      z = z * (1.0 / minR2);
    } else if (r2 < 1.0) {
      shellInversions = shellInversions + 1.0;
      z = sphereFold(z);
    }
    z = z * scale + c;
    itersRun = itersRun + 1.0;
    let lz = length(z);
    orbitMin = min(orbitMin, lz);
    orbitAvg = orbitAvg + lz;
    if (dot(z, z) > 10000.0) { break; }
  }
  orbitAvg = orbitAvg / f32(maxIter);

  let fdim = fractalDimension(orbitMin);

  let ao = exp(-orbitMin * 4.0);
  let temp = fract(orbitAvg * 0.1 + 0.5);
  let warm = vec3<f32>(0.95, 0.78, 0.55);
  let cool = vec3<f32>(0.55, 0.72, 0.92);
  var color = mix(warm, cool, temp);
  color = mix(vec3<f32>(0.15, 0.18, 0.25), color, 1.0 - ao * 0.8);

  // ── IDEA 2: fold itinerary ──
  // The orbit's symbolic history: reflection-dominated orbits (box fold)
  // read as cold brushed steel, inversion-dominated (sphere shell) as gold,
  // core-scaled orbits (inside min radius) as deep oxidised violet.
  let foldTotal = boxReflections / 3.0 + shellInversions + coreScalings + 1e-3;
  let wBox = (boxReflections / 3.0) / foldTotal;
  let wShell = shellInversions / foldTotal;
  let wCore = coreScalings / foldTotal;
  let steel = vec3<f32>(0.62, 0.70, 0.80);
  let gold = vec3<f32>(1.0, 0.76, 0.36);
  let violet = vec3<f32>(0.42, 0.26, 0.62);
  let itinCol = steel * wBox + gold * wShell + violet * wCore;
  let itinShift = 0.35 + mids * 0.15;
  color = mix(color, color * itinCol * 1.6, itinShift);
  // escape speed banding: orbits that escaped early carry a fine iso-band
  let escapeBand = smoothstep(0.35, 0.5, abs(fract(itersRun * 0.5 + fdim) - 0.5)) * step(itersRun, f32(maxIter) - 0.5);
  color = color * (1.0 - escapeBand * 0.18);

  let highlight = exp(-orbitMin * orbitMin * 12.0);
  color = color + vec3<f32>(1.0, 0.95, 0.78) * highlight * specular * 3.5;

  // ── IDEA 1: distance estimate + gradient normal lighting ──
  // Shading only (no marching), evaluated on a capped iteration budget so the
  // four samples share one consistent field.
  let deIters = min(maxIter, 28);
  let pos3 = vec3<f32>(p.x, p.y, sliceThick);
  let de0 = mandelboxDE(pos3, c, scale, minR2, deIters);
  let h = 0.004;
  let deX = mandelboxDE(pos3 + vec3<f32>(h, 0.0, 0.0), c + vec3<f32>(h, 0.0, 0.0), scale, minR2, deIters);
  let deY = mandelboxDE(pos3 + vec3<f32>(0.0, h, 0.0), c + vec3<f32>(0.0, h, 0.0), scale, minR2, deIters);
  let deZ = mandelboxDE(pos3 + vec3<f32>(0.0, 0.0, h), c, scale, minR2, deIters);
  let grad = vec3<f32>(deX - de0, deY - de0, deZ - de0);
  let n = normalize(grad + vec3<f32>(0.0, 0.0, 1e-5));
  let lightDir = normalize(vec3<f32>(cos(time * 0.2), sin(time * 0.2), 0.8));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfV = normalize(lightDir + viewDir);
  let shell = exp(-max(de0, 0.0) * 18.0);
  let diffuse = max(dot(n, lightDir), 0.0);
  let shininess = mix(8.0, 96.0, specular);
  let blinn = pow(max(dot(n, halfV), 0.0), shininess) * specular * (1.0 + treble * 0.8);
  color = color * (0.75 + 0.45 * diffuse * shell);
  color = color + vec3<f32>(1.0, 0.93, 0.8) * blinn * shell * 1.6;
  // iso-distance contours hugging the boundary
  let contour = smoothstep(0.08, 0.0, abs(fract(de0 * 24.0) - 0.5)) * exp(-de0 * 6.0);
  color = color + vec3<f32>(0.35, 0.55, 0.9) * contour * 0.18 * (1.0 + treble * 0.5);
  color = color + vec3<f32>(1.0, 0.55, 0.9) * foldShock * 0.6;

  let edge = smoothstep(0.25, 0.65, 1.0 - ao);
  color = vec3<f32>(
    color.r * (1.0 + edge * 0.12),
    color.g * (1.0 + edge * 0.04),
    color.b * (1.0 - edge * 0.1)
  );

  // Chromatic aberration before tonemap
  let density = 1.0 - ao;
  let depth = density * clamp(orbitMin * 2.5, 0.0, 1.0);
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // Single ACES tonemap
  var display = acesToneMap(color * 2.2);

  // Temporal feedback in display space: exact clamped load from C
  let maxC = vec2<i32>(dims) - vec2<i32>(1);
  let prev = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxC), 0);
  display = mix(display, prev.rgb * 0.94, 0.05);

  let alpha = clamp(density * clamp(orbitMin * 3.0, 0.0, 1.0) + shell * 0.2 + foldShock * 0.3, 0.0, 1.0);
  let finalColor = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
