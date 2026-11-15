// ═══════════════════════════════════════════════════════════════════
//  Liquid (Ambient)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: isotropic 9-point wave Laplacian (§12.2D) & bathymetric scene-depth shoaling; chromatic Snell vector refraction (§12.2F) with depth parallax & raking sun glint
//  A packing: raw (height, velocity, foam, coverage)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0), dims - vec2<i32>(1));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Snell lateral deflection for eye ray (0, 0, -1) entering water normal n with index ratio eta = n_air / n_water
fn snellLateral(n: vec3<f32>, eta: f32) -> vec2<f32> {
  let cosI = clamp(n.z, 0.05, 1.0);
  let sin2T = eta * eta * max(1.0 - cosI * cosI, 0.0);
  let cosT = sqrt(max(1.0 - sin2T, 0.0));
  return (eta * cosI - cosT) * n.xy;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let intensity = u.zoom_params.x;
  let speed = mix(0.25, 1.45, u.zoom_params.y);
  let scale = mix(5.0, 18.0, u.zoom_params.z);
  let detail = u.zoom_params.w;

  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let ul = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 1), dims), 0);
  let ur = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 1), dims), 0);
  let dl = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, -1), dims), 0);
  let dr = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, -1), dims), 0);

  let initialized = c.a > 0.00001;
  var height = select(0.12, c.r, initialized);
  var velocity = select(0.0, c.g, initialized);
  let hL = select(0.12, l.r, initialized);
  let hR = select(0.12, r.r, initialized);
  let hD = select(0.12, d.r, initialized);
  let hU = select(0.12, t.r, initialized);
  let hUL = select(0.12, ul.r, initialized);
  let hUR = select(0.12, ur.r, initialized);
  let hDL = select(0.12, dl.r, initialized);
  let hDR = select(0.12, dr.r, initialized);

  // ── Idea 1: isotropic 9-point wave Laplacian (§12.2D) & bathymetric scene-depth shoaling ──
  let laplacian = (10.0 / 3.0) * (0.20 * (hL + hR + hD + hU) + 0.05 * (hUL + hUR + hDL + hDR) - height);
  let shoal = mix(1.0, clamp(1.08 - sourceDepth * 0.58, 0.42, 1.05), 0.30 + u.zoom_params.z * 0.45);

  let p = (uv - 0.5) * aspectVec;
  let depthPhase = sourceDepth * u.zoom_params.z * 2.4;
  let ambient = sin(p.x * scale + depthPhase + time * speed * (0.72 + bass * 0.2))
    * cos(p.y * scale * 1.21 - depthPhase * 0.7 - time * speed * (0.61 + mids * 0.16));
  let crossWave = sin((p.x + p.y) * scale * 0.67 - time * speed * 0.48) * detail;
  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec;
  let mouseDist = length(mouseDelta);
  let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  var impulse = exp(-mouseDist * mouseDist * 62.0) * held * (0.008 + intensity * 0.035);
  var clickEnergy = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    let isLive = f32(age >= 0.0 && age < 3.0);
    let safeAge = clamp(age, 0.0, 3.0);
    let dist = length((uv - ripple.xy) * aspectVec);
    let ring = isLive * exp(-pow((dist - safeAge * (0.15 + speed * 0.06)) * 38.0, 2.0)) * exp(-safeAge * 1.1);
    impulse += ring * sin(safeAge * 7.0) * (0.014 + intensity * 0.05);
    clickEnergy += ring;
  }

  velocity = clamp(velocity * mix(0.93, 0.975, detail)
    + laplacian * mix(0.12, 0.065, detail) * shoal
    + (0.12 - height) * 0.012
    + (ambient + crossWave * 0.45) * intensity * 0.0018
    + impulse, -0.65, 0.65);
  height = clamp(height + velocity * mix(0.085, 0.05, detail), 0.01, 0.9);
  let foam = clamp(max(c.b * 0.94, abs(laplacian) * 8.0 + abs(velocity) * 0.55 + clickEnergy * 0.35), 0.0, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.01, 0.1, height)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, coverage));

  // ── Idea 2: chromatic Snell vector refraction (§12.2F) with depth parallax & raking sun glint ──
  let gradIso = vec2<f32>(
    (hL - hR) + 0.5 * (hUL - hUR + hDL - hDR),
    (hD - hU) + 0.5 * (hDL - hUL + hDR - hUR)
  ) * 0.5 * (4.0 + intensity * 12.0);
  let normal = normalize(vec3<f32>(gradIso, 0.28));
  let parallaxColumn = (height + (1.0 - sourceDepth) * 0.16 * intensity) * (0.045 + intensity * 0.16);
  let uvR = clamp(uv + snellLateral(normal, 0.756) * parallaxColumn / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = clamp(uv + snellLateral(normal, 0.748) * parallaxColumn / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(uv + snellLateral(normal, 0.738) * parallaxColumn / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  let sourceRGB = vec3<f32>(sR.r, sG.g, sB.b);
  let sourceA = max(sR.a, max(sG.a, sB.a));

  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let sunDir = normalize(vec3<f32>(-0.36, 0.44, 0.82));
  let sunGlint = pow(max(dot(reflect(-sunDir, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), mix(26.0, 92.0, detail))
    * (0.28 + detail * 0.55 + treble * 0.22);
  let focusCurve = max(-laplacian, 0.0) * 18.0 + abs(laplacian) * 6.0;
  let caustic = pow(clamp(focusCurve + clickEnergy * 0.35, 0.0, 1.2), mix(1.5, 2.4, detail));

  let color = sourceRGB * exp(-height * vec3<f32>(0.25, 0.1, 0.04))
    + vec3<f32>(0.18, 0.52, 0.92) * fresnel * (0.18 + mids * 0.13)
    + vec3<f32>(0.7, 0.94, 1.12) * caustic * (0.14 + treble * 0.2)
    + vec3<f32>(1.05, 0.98, 0.88) * sunGlint
    + vec3<f32>(0.75, 0.88, 1.0) * foam * (0.04 + bass * 0.08);
  let alpha = clamp(sourceA + (1.0 - sourceA) * coverage * (0.2 + height * 0.58) + fresnel * 0.06 + sunGlint * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(max(color, vec3<f32>(0.0))), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.92, height * 0.24 + foam * 0.025), 0.0, 0.0, 0.0));
}
