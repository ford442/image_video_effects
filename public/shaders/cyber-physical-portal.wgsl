// ═══════════════════════════════════════════════════════════════════
//  Cyber Physical Portal — Batch 66
//  fp128 Kerr lensing angle, closed-form accretion runners, racing rim
//  packets, C smear through the throat, capped click EMP, held deepens
//  well, ACES + semantic alpha.
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

const TAU: f32 = 6.28318530718;

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  let f = e - (t - p);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rim_runner(angle: f32, time: f32, bass: f32) -> f32 {
  let head = fract(time * (0.85 + bass * 1.4));
  let d = abs(fract((angle / TAU) - head) - 0.5) * 2.0;
  return pow(max(0.0, 1.0 - d * 5.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }
  let pixel = vec2<i32>(gid.xy);

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let portalRadius = mix(0.05, 0.42, u.zoom_params.x);
  let lensingStrength = mix(0.0, 4.5, u.zoom_params.y) * select(1.0, 1.25, held);
  let gridDensity = mix(5.0, 48.0, u.zoom_params.z);
  let glow = mix(0.06, 0.8, u.zoom_params.w);

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let lensingScale = mix(0.6, 1.5, depth);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let angle = atan2(centered.y, centered.x);

  let eventHorizon = portalRadius * 0.85;
  let rimStart = portalRadius;
  let rimEnd = portalRadius + 0.04;

  let mask = 1.0 - smoothstep(rimStart, rimEnd, dist);
  let coreMask = 1.0 - smoothstep(0.0, eventHorizon, dist);
  let rimMask = smoothstep(rimStart, rimEnd, dist) * (1.0 - smoothstep(rimEnd, rimEnd + 0.08, dist));

  let spinSpeed = 1.5 + bass * 3.0 + mids * 1.2;
  let frameDrag = lensingStrength * mask * (1.0 - dist / max(portalRadius, 1e-4)) * lensingScale;

  // fp128 integrated spin angle — stable at high spin rates
  let spinRate = fp128_mul(fp128(frameDrag), fp128(1.0 + bass * 0.5));
  let spinPhase = fp128_sum(fp128_mul(spinRate, fp128(time)), fp128(angle));
  let draggedAngle = fp128_val(spinPhase);

  let lensedDist = dist + frameDrag * 0.015;
  let lensedCentered = vec2<f32>(cos(angle), sin(angle)) * lensedDist;
  let lensedUV = clamp(mouse + lensedCentered / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let prev = textureLoad(dataTextureC, pixel, 0);
  let throatSmear = mix(prev.rgb * 0.82, textureSampleLevel(readTexture, u_sampler, lensedUV, 0.0).rgb, 0.18 * coreMask);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lensedSrc = mix(textureSampleLevel(readTexture, u_sampler, lensedUV, 0.0).rgb, throatSmear, coreMask * 0.35);

  let gridUV = vec2<f32>(draggedAngle * 2.5, dist * gridDensity) + vec2<f32>(time * spinSpeed * 0.3, -time * spinSpeed * 0.7);
  let grid = abs(fract(gridUV) - 0.5);
  let ring = 1.0 - smoothstep(0.0, 0.035, min(grid.x, grid.y));

  var accretion = 0.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let bandPhase = time * (2.0 + f32(i) * 0.7) + bass * 4.0;
    let bandR = eventHorizon + f32(i) * 0.018 + sin(bandPhase) * 0.008 + cos(bandPhase * 1.37) * 0.004;
    accretion = accretion + smoothstep(0.015, 0.0, abs(dist - bandR)) * (0.6 + hash12(vec2<f32>(bandR, bandPhase)) * 0.4);
  }

  let runner = rim_runner(angle, time, bass);
  let rimHue = 0.5 + 0.5 * sin(time * 1.4 + dist * 18.0 + bass * 2.0 + runner * 2.0);
  let cyanMagenta = mix(vec3<f32>(0.08, 0.92, 1.0), vec3<f32>(1.0, 0.15, 0.85), rimHue);
  let hologram = cyanMagenta * (ring * 0.35 + coreMask * (glow + bass * 0.25) + accretion * 0.5 + runner * 0.4);

  let chromaR = textureSampleLevel(readTexture, u_sampler, clamp(lensedUV + vec2<f32>(0.003 * frameDrag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromaB = textureSampleLevel(readTexture, u_sampler, clamp(lensedUV - vec2<f32>(0.003 * frameDrag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticLensed = vec3<f32>(chromaR, lensedSrc.g, chromaB);

  var portalColor = mix(chromaticLensed, chromaticLensed * vec3<f32>(0.3, 0.95, 0.55) + cyanMagenta * 0.4, 0.5);
  portalColor = portalColor + hologram;
  portalColor = portalColor + cyanMagenta * rimMask * glow * 0.6;

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.5) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.03, 0.0, abs(rDist - age * 0.42)) * exp(-age * 1.5);
    }
  }
  portalColor = portalColor + cyanMagenta * clickBurst * (0.5 + treble * 0.4);

  let bloom = pow(max(max(portalColor.r, portalColor.g), portalColor.b), 2.0) * 1.8 * mask;
  portalColor = portalColor + vec3<f32>(bloom * 0.5, bloom * 0.3, bloom * 0.6);

  let finalColor = acesToneMap(mix(src.rgb, portalColor, mask));
  let rimIntensity = rimMask * glow + ring * 0.4 + coreMask * glow + accretion * 0.3 + runner * 0.25;
  let lensingConfidence = clamp(frameDrag / 4.5, 0.0, 1.0);
  let finalAlpha = clamp(rimIntensity * lensingConfidence * depth + mask * 0.15 + clickBurst * 0.12, 0.06, 0.96);

  let baseDepth = textureLoad(readDepthTexture, vec2<i32>(clamp(vec2<i32>(lensedUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1))), 0).r;
  let outDepth = clamp(mix(depth, baseDepth * 0.3, mask), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(throatSmear, finalAlpha));
}
