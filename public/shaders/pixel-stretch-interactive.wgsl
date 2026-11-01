// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Interactive
//  Category: image
//  Features: mouse-driven, audio-reactive, anisotropic-stretch, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-06, 2026-11-01
//  Ideas: coherence tear length; luma-sorted streak; Cauchy channel scale (§12.2F); coherence gutter
//  A packing: ACES display RGBA (C is not read)
//  History: created 2026-05-17 (pixel-stretch + structure-tensor + aces chunks); upgraded 2026-05-31
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// ── Idea 3: Cauchy channel scale (§12.2F) ────────────────────────
// n(λ) = 1 + 1/λ², relative to green. Chromatic Scale still sets the
// old ±0.5 reach; the curve decides how red and blue share it.
fn cauchyScale(dispersion: f32) -> vec3<f32> {
  let lam = vec3<f32>(0.650, 0.550, 0.450);
  let n = 1.0 + 1.0 / (lam * lam);
  let rel = n / max(n.y, 0.001);
  let reach = clamp(dispersion, 0.0, 1.0) * 0.5;
  let redDeficit = max(1.0 - rel.x, 0.0);
  let blueExtra = max(rel.z - 1.0, 0.0);
  let norm = max(max(blueExtra, redDeficit), 1e-4);
  return vec3<f32>(1.0 - reach * redDeficit / norm, 1.0, 1.0 + reach * blueExtra / norm);
}

// Structure-tensor terms (E, F, G) at p from 2-texel central differences.
fn tensorAt(p: vec2<f32>, texel: vec2<f32>) -> vec3<f32> {
  let dx = vec2(texel.x * 2.0, 0.0);
  let dy = vec2(0.0, texel.y * 2.0);
  let gx = (textureSampleLevel(readTexture, u_sampler, p + dx, 0.0).rgb
          - textureSampleLevel(readTexture, u_sampler, p - dx, 0.0).rgb) * 0.25;
  let gy = (textureSampleLevel(readTexture, u_sampler, p + dy, 0.0).rgb
          - textureSampleLevel(readTexture, u_sampler, p - dy, 0.0).rgb) * 0.25;
  return vec3(dot(gx, gx), dot(gx, gy), dot(gy, gy));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let texel = 1.0 / resolution;

  let stretchParam = u.zoom_params.x;
  let bloomStr = u.zoom_params.y;
  let grainStr = u.zoom_params.z * 0.1;
  let chromaScale = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.35, 1.0, depth);

  // Structure tensor for edge-directed anisotropic stretch
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let rx = textureSampleLevel(readTexture, u_sampler, uv + vec2(texel.x, 0.0), 0.0).rgb;
  let lx = textureSampleLevel(readTexture, u_sampler, uv - vec2(texel.x, 0.0), 0.0).rgb;
  let ty = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, texel.y), 0.0).rgb;
  let by = textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, texel.y), 0.0).rgb;
  let gx = (rx - lx) * 0.5;
  let gy = (ty - by) * 0.5;
  // FIX: integrate the tensor over a +-2 texel footprint (HEAD used the raw per-pixel
  // tensor, so the stretch was one pixel wide and only fired on hard edges).
  var T = vec3(dot(gx, gx), dot(gx, gy), dot(gy, gy));
  T += tensorAt(uv + vec2(-2.0, -2.0) * texel, texel);
  T += tensorAt(uv + vec2( 2.0, -2.0) * texel, texel);
  T += tensorAt(uv + vec2(-2.0,  2.0) * texel, texel);
  T += tensorAt(uv + vec2( 2.0,  2.0) * texel, texel);
  T *= 0.2;
  let E = T.x;
  let F = T.y;
  let G = T.z;
  let lambda = sqrt((E - G) * (E - G) + 4.0 * F * F);
  // FIX: HEAD took 0.5*atan2(2F, E-G+lambda), a quarter angle. The major-eigenvector angle is
  // 0.5*atan2(2F, E-G) (== atan2(2F, E-G+lambda), but this form stays correct when F=0, E<G).
  let theta = 0.5 * atan2(2.0 * F, E - G);
  var edgeDir = vec2(cos(theta), sin(theta));
  let energy = E + G;
  let edgeAlign = smoothstep(0.004, 0.06, energy);
  // Idea 1: coherence (anisotropy) of the tensor, 0 = isotropic texture, 1 = one clean edge.
  let coherence = clamp(lambda / (energy + 1e-5), 0.0, 1.0);

  // Mouse controls stretch direction; bass drives magnitude
  let toMouse = uv - mouse;
  let mouseDir = toMouse / max(length(toMouse), 1e-4);
  // FIX: eigenvectors are sign-free; fold edgeDir into mouseDir's half-plane so the mix cannot cancel.
  edgeDir = edgeDir * select(1.0, -1.0, dot(edgeDir, mouseDir) < 0.0);
  let dirMix = mix(mouseDir, edgeDir, 0.55);
  let stretchDir = dirMix / max(length(dirMix), 1e-4);

  // Idea 1: coherent structure tears long streaks, isotropic texture only a quarter as far.
  let tearReach = mix(0.25, 1.0, coherence);
  let stretchAmt = stretchParam * (1.0 + bass * 0.8) * depthFactor * edgeAlign * tearReach;

  // Parallax layering: sample near and far layers with depth offset
  let parallaxNear = textureSampleLevel(readTexture, u_sampler, uv + stretchDir * stretchAmt * 0.3, 0.0).rgb;
  let parallaxFar = textureSampleLevel(readTexture, u_sampler, uv - stretchDir * stretchAmt * 0.15, 0.0).rgb;
  let parallaxMix = mix(parallaxFar, parallaxNear, depth);

  // Chromatic pixel smear along stretch axis
  let lumC = luma(c);
  var accR = vec3(0.0);
  var accG = vec3(0.0);
  var accB = vec3(0.0);
  var wSum = 0.0;
  var bloom = vec3(0.0);
  let steps = 8;
  for (var i = 0; i < steps; i = i + 1) {
    let t = (f32(i) / f32(steps - 1)) - 0.5;
    let offset = stretchDir * stretchAmt * t;
    let cScale = cauchyScale(clamp(chromaScale, 0.0, 1.0));
    let rUV = clamp(uv + offset * cScale.x, vec2(0.0), vec2(1.0));
    let gUV = clamp(uv + offset * cScale.y, vec2(0.0), vec2(1.0));
    let bUV = clamp(uv + offset * cScale.z, vec2(0.0), vec2(1.0));
    let gTap = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb;
    let lum = luma(gTap);
    // Idea 2: luma-sorted streak — taps brighter than the centre count more ahead of it and
    // less behind it (darker taps the reverse), so bright content bleeds against the stretch
    // axis and dark content with it: each streak becomes an ordered luma ramp.
    let w = exp(clamp(6.0 * t * (lum - lumC), -4.0, 4.0));
    accR = accR + textureSampleLevel(readTexture, u_sampler, rUV, 0.0).rgb * w;
    accG = accG + gTap * w;
    accB = accB + textureSampleLevel(readTexture, u_sampler, bUV, 0.0).rgb * w;
    wSum = wSum + w;
    let highlight = smoothstep(0.5, 0.9, lum);
    bloom = bloom + vec3(highlight) * lum;
  }
  let invSteps = 1.0 / f32(steps);
  var color = vec3(accR.r, accG.g, accB.b) / max(wSum, 1e-4);

  // HDR bloom on stretched highlights
  bloom = bloom * invSteps * bloomStr * 3.0;
  color = color + bloom * vec3(1.0, 0.9, 0.7);

  // Blend with parallax layers
  color = mix(color, parallaxMix, 0.25 * depthFactor);

  // ── Idea 4: coherence gutter ───────────────────────────────────
  // A dark lip where the centre luma differs from one texel off the
  // stretch axis. Coherence still also sets tear length above.
  let perpStretch = vec2<f32>(-stretchDir.y, stretchDir.x);
  let sideUV = clamp(uv + perpStretch * texel * 1.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let sideL = luma(textureSampleLevel(readTexture, u_sampler, sideUV, 0.0).rgb);
  let gutter = smoothstep(0.02, 0.12, abs(lumC - sideL)) * coherence * edgeAlign;
  color = color * (1.0 - 0.28 * gutter);

  // ACES tone mapping
  color = aces(max(color, vec3(0.0)) * 1.15);

  // Film grain
  let grain = (hash12(uv * resolution + fract(time * 0.7)) - 0.5) * grainStr;
  color = clamp(color + grain, vec3(0.0), vec3(1.0));

  // Semantic alpha: full coverage, nudged up where a streak is actively tearing.
  let alpha = clamp(0.85 + 0.15 * clamp(stretchAmt * 6.0, 0.0, 1.0) + gutter * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4(color, alpha));
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4(color, alpha));
}
