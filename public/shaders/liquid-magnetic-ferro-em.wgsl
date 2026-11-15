// ═══════════════════════════════════════════════════════════════════
//  Liquid Magnetic Ferro EM
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: flux-tube-aligned Rosensweig chaining & nonlinear capillary surface tension (§12.2D); Lorentz equipotential induction filaments & magnetite carrier-fluid optics
//  A packing: raw MHD state (R=height, G=velocity, B=EM potential, A=surface charge); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
const TAU: f32 = 6.28318530718;

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn dipoleField(p: vec2<f32>, origin: vec2<f32>, polarity: f32) -> vec2<f32> {
  let delta = p - origin; let r2 = max(dot(delta, delta), 0.0025);
  return polarity * vec2<f32>(delta.x, -delta.y) / (r2 * sqrt(r2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
  let fieldStrength = clamp(u.zoom_params.x, 0.0, 1.0);
  let sharpness = clamp(u.zoom_params.y, 0.0, 1.0);
  let emCoupling = clamp(u.zoom_params.z, 0.0, 1.0);
  let dipoleControl = clamp(u.zoom_params.w, 0.0, 1.0);

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let dl = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, -1), dims), 0);
  let dr = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, -1), dims), 0);
  let ul = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 1), dims), 0);
  let ur = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 1), dims), 0);

  let initialized = dot(abs(c), vec4<f32>(1.0)) > 0.00001;
  var height = select(0.1, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  var potential = select(0.0, c.b, initialized); var charge = select(0.0, c.a, initialized);
  let hL = select(0.1, l.r, initialized); let hR = select(0.1, r.r, initialized);
  let hD = select(0.1, d.r, initialized); let hU = select(0.1, t.r, initialized);
  let hDL = select(0.1, dl.r, initialized); let hDR = select(0.1, dr.r, initialized);
  let hUL = select(0.1, ul.r, initialized); let hUR = select(0.1, ur.r, initialized);
  let lapH = (10.0 / 3.0) * (0.20 * (hL + hR + hD + hU) + 0.05 * (hDL + hDR + hUL + hUR) - height);
  let potentialLaplacian = l.b + r.b + d.b + t.b - 4.0 * potential;

  // ── Idea 1 (part a): nonlinear capillary mean-curvature surface tension (§12.2D) ─
  // κ = ∇·(∇h / sqrt(1 + |∇h|²)) rounds droplet saddles and tautens Rosensweig cone tips.
  let sE = vec2<f32>(hR - height, 0.25 * (hUR + hU - hDR - hD)) * 12.0;
  let sW = vec2<f32>(height - hL, 0.25 * (hUL + hU - hDL - hD)) * 12.0;
  let sN = vec2<f32>(0.25 * (hUR + hR - hUL - hL), hU - height) * 12.0;
  let sS = vec2<f32>(0.25 * (hDR + hR - hDL - hL), height - hD) * 12.0;
  let meanCurv = (sE.x * inverseSqrt(1.0 + dot(sE, sE)) - sW.x * inverseSqrt(1.0 + dot(sW, sW))
                + sN.y * inverseSqrt(1.0 + dot(sN, sN)) - sS.y * inverseSqrt(1.0 + dot(sS, sS))) * 0.08;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var magnet = u.zoom_config.yz; var magnetVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) { magnet = vec2<f32>(extraBuffer[133], extraBuffer[134]); magnetVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var mp = magnet; var mv = magnetVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { mp = u.zoom_config.yz; mv = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    mv += ((u.zoom_config.yz - mp) * 170.0 - mv * 24.0) * dt; mp += mv * dt;
    extraBuffer[133] = mp.x; extraBuffer[134] = mp.y; extraBuffer[135] = mv.x; extraBuffer[136] = mv.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let p = uv * aspectVec; let magnetP = magnet * aspectVec;
  var field = dipoleField(p, magnetP, select(-0.25, 0.9, u.zoom_config.w > 0.5));
  let dipoleCount = 2 + i32(floor(dipoleControl * 4.0));
  for (var i = 0; i < 6; i += 1) {
    let activeDipole = f32(i < dipoleCount);
    let fi = f32(i); let angle = time * (0.11 + mids * 0.04) + fi * TAU / f32(dipoleCount);
    let origin = (vec2<f32>(0.5) + vec2<f32>(cos(angle), sin(angle)) * (0.2 + 0.06 * sin(time * 0.17 + fi))) * aspectVec;
    field += activeDipole * dipoleField(p, origin, select(-0.18, 0.18, (i % 2) == 0));
  }
  field *= (0.0015 + fieldStrength * 0.006) * (1.0 + bass * 0.35);
  var emWave = sin(length(p - magnetP) * (24.0 + sharpness * 18.0) - time * (3.0 + mids * 2.0));
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    let liveMask = f32(age >= 0.0 && age < 2.8);
    let safeAge = max(age, 0.0);
    let dist = length((uv - ripple.xy) * aspectVec);
    let ring = liveMask * exp(-pow((dist - safeAge * 0.22) * 42.0, 2.0)) * exp(-safeAge * 1.1);
    let polarity = select(-1.0, 1.0, (i % 2u) == 0u);
    potential += ring * polarity * (0.08 + emCoupling * 0.16); charge += ring * polarity * 0.06; clickEnergy += ring;
  }
  potential = clamp(potential * 0.972 + potentialLaplacian * 0.08 + emWave * emCoupling * 0.012, -1.5, 1.5);
  let potGrad = vec2<f32>(r.b - l.b, t.b - d.b);
  charge = clamp(charge * 0.96 + (potGrad.x + potGrad.y) * 0.04 + dot(field, vec2<f32>(0.7, 0.3)) * emCoupling, -1.0, 1.0);
  let fieldLen = length(field);
  let fieldEnergy = min(fieldLen, 1.5);

  // ── Idea 1 (part b): flux-tube-aligned anisotropic Rosensweig chaining ────
  // Tangential dipole flux stretches hex modes into ridges bridging North and South poles.
  let bHat = field * inverseSqrt(max(fieldLen * fieldLen, 1e-8));
  let bPerp = vec2<f32>(-bHat.y, bHat.x);
  let chainAniso = clamp(fieldEnergy * (1.8 + fieldStrength * 2.2), 0.0, 0.55);
  let baseFreq = 11.0 + sharpness * 12.0;
  let projParallel = dot(p, bHat) * baseFreq * (1.0 - chainAniso * 0.52);
  let projCross = dot(p, bPerp) * baseFreq * (1.0 + chainAniso * 0.85);
  let latticeP = mix(p * baseFreq, vec2<f32>(projParallel, projCross), smoothstep(0.002, 0.08, fieldEnergy)) + field * 2.0;

  let hexMode = (cos(latticeP.x) + 2.0 * cos(latticeP.x * 0.5) * cos(latticeP.y * 0.8660254)) / 3.0;
  let spikeTarget = pow(clamp(hexMode * 0.5 + 0.5, 0.0, 1.0), mix(3.0, 9.0, sharpness));
  let equilibrium = 0.08 + spikeTarget * (0.03 + fieldStrength * 0.16) + abs(potential) * emCoupling * 0.025;
  let capRestore = meanCurv * mix(0.045, 0.018, sharpness);
  velocity = clamp(velocity * mix(0.94, 0.982, sharpness) + lapH * mix(0.11, 0.05, sharpness) + capRestore
    + (equilibrium - height) * 0.04 + charge * fieldEnergy * 0.025 + clickEnergy * 0.015, -0.9, 0.9);
  height = clamp(height + velocity * mix(0.08, 0.04, sharpness), 0.005, 1.2);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, potential, charge));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (6.0 + sharpness * 17.0) + field * 0.2;
  let normal = normalize(vec3<f32>(gradient, 0.2)); let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let sourceUV = clamp(uv + normal.xy * (0.012 + height * 0.045) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = 0.35 + 0.65 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let fieldDir = atan2(field.y, field.x) / TAU;
  let emTint = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.33, 0.67) + fieldDir + potential * 0.08));
  let light = normalize(vec3<f32>(-0.4, 0.5, 0.78));
  let counterLight = normalize(vec3<f32>(0.62, -0.45, 0.64));
  let specular = pow(max(dot(normal, normalize(viewDir + light)), 0.0), mix(26.0, 150.0, sharpness));
  let counterSpec = pow(max(dot(normal, normalize(viewDir + counterLight)), 0.0), mix(18.0, 80.0, sharpness));

  // ── Idea 2: Lorentz equipotential induction filaments & magnetite carrier absorption ─
  let equipotContour = exp(-abs(fract(potential * 5.5 - time * 0.25) - 0.5) * 18.0);
  let lorentzArc = equipotContour * smoothstep(0.015, 0.22, length(potGrad) + abs(charge) * 0.5) * emCoupling;
  let magnetiteTrans = exp(-max(height - 0.06, 0.0) * vec3<f32>(2.4, 2.9, 3.6));

  let color = source.rgb * magnetiteTrans * (0.22 + (1.0 - fresnel) * 0.38)
    + emTint * fresnel * (0.45 + emCoupling * 0.45 + mids * 0.1)
    + vec3<f32>(1.05, 0.96, 0.82) * specular * (0.75 + bass * 0.35)
    + emTint * counterSpec * 0.28
    + mix(vec3<f32>(0.25, 0.78, 1.25), vec3<f32>(1.15, 0.62, 0.22), step(0.0, charge)) * lorentzArc * (0.42 + mids * 0.35)
    + vec3<f32>(0.3, 0.62, 1.1) * abs(charge) * treble * 0.16;
  let alpha = clamp(source.a * 0.35 + smoothstep(0.005, 0.16, height) * 0.56 + fresnel * 0.1 + lorentzArc * 0.12 + clickEnergy * 0.05, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(max(color, vec3<f32>(0.0))), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(max(sourceDepth * 0.76, height * 0.58 + fieldEnergy * 0.03), 0.0, 1.0), 0.0, 0.0, 0.0));
}
