// ═══════════════════════════════════════════════════════════════════
//  Volumetric God Rays v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11, 2026-10-31
//  Ideas: photo-luma occluder in the march; sun-disk core at the source; dust Beer-Lambert; Cauchy split along the march
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn miePhase(g: f32, cosTheta: f32) -> f32 {
  let gg = g * g;
  let denom = max(1.0 + gg - 2.0 * g * cosTheta, 0.001);
  return (1.0 - gg) / (4.0 * 3.14159265 * pow(denom, 1.5));
}

fn hash12(p: vec2<f32>) -> f32 {
  var pp = fract(p * vec2<f32>(0.1031, 0.1030));
  pp = pp + dot(pp, pp.yx + 33.33);
  return fract((pp.x + pp.y) * 43758.5453);
}

fn cauchyScale(bDisp: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.4225, 0.3025, 0.2025);
  let n = 1.0 + bDisp / lam2;
  return n / max(n.y, 1e-4);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  let hasAudio = arrayLength(&plasmaBuffer) > 0u;
  let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
  let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
  let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

  let density = max(u.zoom_params.x, 0.001);
  let decay = clamp(u.zoom_params.y, 0.0, 1.0);
  let weight = u.zoom_params.z;
  let exposure = clamp(u.zoom_params.w, 0.0, 1.0);

  let srcDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOcclusion = mix(0.3, 1.0, srcDepth);
  let extinction = mix(0.7, 1.0, srcDepth);

  let dustDensity = density * (1.0 + bass * 0.8);
  let numSamples = 48;
  let deltaTextCoord = uv - mousePos;
  let stepSize = (deltaTextCoord * dustDensity) / f32(numSamples);

  var currentUV = uv;
  let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let baseColor = baseSample.rgb;
  let mouseSrc = textureSampleLevel(readTexture, u_sampler, clamp(mousePos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sunLuma = dot(mouseSrc.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var accumulatedR = 0.0;
  var accumulatedG = 0.0;
  var accumulatedB = 0.0;
  var illuminationDecay = depthOcclusion;

  let rayDir = normalize(deltaTextCoord + vec2<f32>(0.0001));
  let lightDir = -rayDir;

  for (var i = 0; i < numSamples; i++) {
    currentUV = currentUV - stepSize;
    if (any(currentUV < vec2<f32>(0.0)) || any(currentUV > vec2<f32>(1.0))) { break; }
    if (illuminationDecay < 0.003) { break; }

    var sampleColor = textureSampleLevel(readTexture, u_sampler, currentUV, 0.0).rgb;
    let sampleLuma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
    // Idea 1: dark photo along the march extinguishes the shaft
    illuminationDecay = illuminationDecay * mix(0.45, 1.0, smoothstep(0.05, 0.35, sampleLuma));

    let dustNoise = hash12(currentUV * 200.0 + f32(i) * 1.618);
    let dust = 0.85 + dustNoise * 0.3;
    let sampleRayDir = normalize(uv - currentUV + vec2<f32>(0.0001));
    let cosTheta = dot(sampleRayDir, lightDir);
    let phase = miePhase(0.6, cosTheta);
    let edgeFade = length(currentUV - mousePos);
    // ── Idea 4: Cauchy split along the march (§12.2F) ───────────────
    // R and B sample different distances toward the source. The old
    // single-sample R-up/B-down tint is replaced by that spatial split.
    let scales = cauchyScale(0.012 + 0.02 * edgeFade);
    let chrom = 0.003 + 0.006 * edgeFade;
    let uvR = clamp(currentUV - rayDir * chrom * scales.x, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(currentUV - rayDir * chrom * scales.z, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    let contrib = illuminationDecay * weight * phase * dust * extinction;
    accumulatedR += sampleR * contrib;
    accumulatedG += sampleColor.g * contrib;
    accumulatedB += sampleB * contrib;
    // ── Idea 3: dust Beer–Lambert (§12.2F) ──────────────────────────
    // decay still multiplies every step. Denser motes add optical depth.
    let optical = max(dust - 0.9, 0.0) * dustDensity * 0.045;
    illuminationDecay = illuminationDecay * decay * exp(-optical);
  }

  let accumulatedColor = vec3<f32>(accumulatedR, accumulatedG, accumulatedB);
  let mouseDist = length(uv - mousePos);
  let bloom = exp(-mouseDist * 8.0) * (0.5 + treble * 0.5);
  // Idea 2: sun-disk gated by highlight at the source
  let sunDisk = smoothstep(0.045, 0.0, mouseDist) * smoothstep(0.25, 0.7, sunLuma) * (0.8 + treble * 0.4);
  var finalRGB = baseColor * ((1.0 - exposure) + 0.4) + accumulatedColor * exposure
    + vec3<f32>(bloom * 0.3, bloom * 0.25, bloom * 0.15)
    + vec3<f32>(1.0, 0.96, 0.82) * sunDisk * exposure * 1.6;

  let haze = mids * 0.15 * (1.0 - srcDepth);
  finalRGB += vec3<f32>(haze * 0.9, haze * 0.95, haze * 1.1);
  finalRGB = acesToneMap(finalRGB);

  let scatteredLuma = dot(accumulatedColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(scatteredLuma * exposure * 2.0 * dustDensity * extinction + sunDisk, 0.0, 1.0) * baseSample.a;

  let display = vec4<f32>(finalRGB, alpha);
  textureStore(writeTexture, coords, display);
  textureStore(writeDepthTexture, coords, vec4<f32>(srcDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, display);
}
