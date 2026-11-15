// ═══════════════════════════════════════════════════════════════════
//  Photonic Caustics — trace
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: Cauchy IOR split (§12.2F); Beer–Lambert in the pool (§12.2F); second batch adds
//  A packing: caustic rgb (alpha 1). Normals live only in the emit pass
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const PHOTONS_PER_PASS: i32 = 16;

fn hash31(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn fresnelSchlick(cosTheta: f32, ior: f32) -> f32 {
  let r0 = (1.0 - ior) / (1.0 + ior);
  let r0sq = r0 * r0;
  let oneMinus = clamp(1.0 - cosTheta, 0.0, 1.0);
  return r0sq + (1.0 - r0sq) * pow(oneMinus, 5.0);
}

fn refractRay(incident: vec3<f32>, normal: vec3<f32>, eta: f32) -> vec3<f32> {
  let cosi = clamp(-dot(normal, incident), 0.0, 1.0);
  let sin2t = eta * eta * (1.0 - cosi * cosi);
  let tir = sin2t > 1.0;
  let cost = sqrt(max(1.0 - sin2t, 0.0));
  let refr = incident * eta + normal * (eta * cosi - cost);
  return select(refr, reflect(incident, normal), tir);
}

fn depthNormal(uv: vec2<f32>, texel: vec2<f32>, steep: f32) -> vec3<f32> {
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let nz = mix(0.35, 0.12, steep);
  return normalize(vec3<f32>((hL - hR) * 2.0, (hU - hD) * 2.0, nz));
}

// n(λ) = 1 + B/λ², relative to green. λ in µm.
fn cauchyScales(bDisp: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.650 * 0.650, 0.550 * 0.550, 0.450 * 0.450);
  let n = vec3<f32>(1.0) + vec3<f32>(bDisp) / lam2;
  return n / max(n.y, 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texel = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;

  let baseIOR = mix(1.1, 1.8, u.zoom_params.x);
  let lightSize = mix(0.05, 0.3, u.zoom_params.y);
  let dispersion = mix(0.0, 0.1, u.zoom_params.z);
  let intensity = mix(0.5, 3.0, u.zoom_params.w);

  let lightPos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let incoming = textureLoad(dataTextureC, vec2<i32>(coord), 0);

  // Emit stores light height ≤ 0.63 (mouse up) or ≥ 1.7 (mouse down).
  // A caustic from the previous repeat stores alpha 1.
  let isNormal = incoming.a < 0.75 || incoming.a > 1.35;
  let rebuilt = depthNormal(uv, texel, u.zoom_params.x);
  let hitNormal = select(rebuilt, normalize(incoming.rgb + vec3<f32>(0.0, 0.0, 0.0001)), isNormal);
  let rebuiltHeight = mix(0.5, 2.0, u.zoom_config.w) * mix(0.85, 1.25, u.zoom_params.y);
  let lightHeight = select(rebuiltHeight, incoming.a, isNormal);
  let stratum = u32(clamp(extraBuffer[133], 0.0, 3.0));

  var causticAccum = vec3<f32>(0.0);
  let batchOffset = i32(fract(frame * 0.1 + f32(stratum) * 0.37) * f32(PHOTONS_PER_PASS));

  // ── Idea 1: Cauchy split. Dispersion is B (§12.2F) ────────────────
  let scales = cauchyScales(dispersion * 1.6);
  let iorR = baseIOR * scales.x;
  let iorG = baseIOR * scales.y;
  let iorB = baseIOR * scales.z;

  for (var p = 0; p < PHOTONS_PER_PASS; p = p + 1) {
    let pid = p + batchOffset;
    let seed = vec3<f32>(uv, f32(pid) + time * 0.01 + f32(stratum) * 17.0);
    let randomAngle = hash31(seed) * 2.0 * PI;
    let randomRadius = sqrt(max(hash31(seed + vec3<f32>(1.0, 0.0, 0.0)), 0.0)) * lightSize;
    let photonOrigin = lightPos + vec2<f32>(cos(randomAngle), sin(randomAngle)) * randomRadius;

    let toPixel = uv - photonOrigin;
    let dist2D = length(toPixel);
    let dir2D = toPixel / max(dist2D, 0.001);
    let lightDir = normalize(vec3<f32>(dir2D, -lightHeight));

    let cosTheta = abs(dot(lightDir, hitNormal));
    let refractR = refractRay(lightDir, hitNormal, 1.0 / max(iorR, 0.05));
    let refractG = refractRay(lightDir, hitNormal, 1.0 / max(iorG, 0.05));
    let refractB = refractRay(lightDir, hitNormal, 1.0 / max(iorB, 0.05));

    let convergenceR = abs(dot(refractR, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceG = abs(dot(refractG, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceB = abs(dot(refractB, vec3<f32>(0.0, 0.0, -1.0)));
    let fresnel = 1.0 - fresnelSchlick(cosTheta, baseIOR);
    let attenuation = 1.0 / (1.0 + dist2D * 5.0);

    // ── Idea 2: Beer–Lambert. Red dies first along the same path ────
    let absorb = exp(-dist2D * vec3<f32>(2.4, 0.55, 0.18));
    causticAccum = causticAccum + vec3<f32>(
      pow(convergenceR, 4.0),
      pow(convergenceG, 4.0),
      pow(convergenceB, 4.0)
    ) * fresnel * attenuation * absorb;
  }

  causticAccum = causticAccum / f32(PHOTONS_PER_PASS) * intensity;

  // ── Idea 3: a second repeat adds onto the caustic it just read ────
  // Two strata are averaged so the repeat does not double the exposure.
  let prev = select(incoming.rgb, vec3<f32>(0.0), isNormal);
  let batches = select(1.0, 2.0, !isNormal);
  let summed = (prev + causticAccum) / batches;
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(summed, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(clamp(1.0 - length(summed) * 0.25, 0.0, 1.0), 0.0, 0.0, 0.0));
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = f32(stratum + 1u);
  }
}
