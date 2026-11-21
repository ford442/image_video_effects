// ═══════════════════════════════════════════════════════════════════
//  Rain v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, atmospheric
//  Complexity: High
//  Chunks From: rain
//  Created: 2026-05-31
//  By: 4-Agent Shader Upgrade Swarm
//  Upgraded: 2026-11-21
//  Ideas: per-lane terminal velocity + shutter-length streaks (bigger drops fall faster and leave longer tails; heads lead downward); Snell vector refraction through each water streak (§12.2F); Beer-Lambert mist on real scene depth (§12.2F)
//  Rescues: rain fell UP (rainUV.y scrolled the wrong way); droplet lens offset grew linearly with time (dropCenter.y missed the scroll); streaks sat on a perfect comb (all at local.x = 0.5); mist re-rolled as hard cells every 0.5 s and rose
//  A packing: unchanged diagnostics (dropletAlpha, motionBlurStrength, mistLayer, finalAlpha); nothing reads C. Display RGBA on writeTexture only (ACES).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// Smooth lattice noise for the advected mist (replaces the 2 Hz hash-cell flips).
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

const WATER_IOR: f32 = 1.333;
const LENS_GAIN: f32 = 3.5;   // visual gain on the water-streak lens offset (the streak is ~1-3 px wide)

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let rainDensity = mix(6.0, 72.0, u.zoom_params.x);
  let fallSpeed = mix(0.3, 4.2, u.zoom_params.y);
  let windBase = mix(-0.12, 0.12, u.zoom_params.z);
  let wetness = mix(0.06, 0.55, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  let mouseWind = (mouse.x - 0.5) * 0.08;
  let wind = windBase + mouseWind;
  let gust = audio.x * 0.04;

  // ── Idea 1: per-lane terminal velocity + shutter-length streaks ───────
  // A drop column ("lane") draws a size seed: bigger drops fall faster (0.7x..1.3x of the
  // fall slider), are a little wider and leave a longer tail (tail = speed x exposure, kept
  // at constant exposure so a long fast streak is not simply brighter). The head leads at the
  // bottom of the cell, where the splash arcs sit. The scroll sign is fixed (HEAD fell UP).
  let rx = uv.x * rainDensity * aspect + wind * time * 3.0;
  let laneSeed = hash12(vec2<f32>(floor(rx), 31.7));
  let laneSpeed = 0.7 + 0.6 * laneSeed;
  let rainUV = vec2<f32>(rx, uv.y * rainDensity - time * fallSpeed * laneSpeed);
  let cell = floor(rainUV);
  let local = fract(rainUV);

  let dropSeed = hash12(cell);

  let gravity = 1.0 + dropSeed * 2.5;
  let xc = 0.5 + (hash12(cell + vec2<f32>(5.3, 9.1)) - 0.5) * 0.5;   // breaks the regular comb of columns
  let tailLen = mix(0.45, 1.0, laneSeed);
  let behind = 1.0 - local.y;                                        // 0 at the head, 1 at the cell top
  let exposure = clamp(0.72 / tailLen, 0.8, 1.0);
  let streakWidth = (0.005 + dropSeed * 0.012) * (0.75 + 0.5 * laneSeed);
  let slant = wind * local.y * 0.3;
  let streakX = abs(local.x - xc + slant);
  let motionBlur = smoothstep(streakWidth * 2.0, 0.0, streakX) * smoothstep(tailLen, 0.15 * tailLen, behind) * (0.4 + 0.6 * gravity / 3.5) * exposure;

  let dropletAlpha = motionBlur * step(0.65, dropSeed);
  let splash = step(0.92, local.y) * step(0.75, dropSeed) * smoothstep(0.0, 0.06, streakX) * smoothstep(0.12, 0.0, streakX);

  // ── Idea 2: Snell refraction through the water streak (§12.2F) ───────
  // Each streak is a thin water cylinder; its cross-section normal comes from the streak's own
  // x-profile and the view ray is refracted into water (eta = 1/1.333). The photo is sampled at
  // the lateral exit offset: the inverted-image sliver a real streak shows. Replaces HEAD's
  // dropWorld lens, whose offset grew linearly with time (dropCenter.y missed the scroll).
  let waterHalfW = streakWidth * 10.0;
  let sx = clamp((local.x - xc + slant) / waterHalfW, -1.0, 1.0);
  let bodyT = sqrt(max(1.0 - sx * sx, 0.0));
  let rayOut = refract(vec3<f32>(0.0, 0.0, -1.0), vec3<f32>(sx, 0.0, bodyT), 1.0 / WATER_IOR);
  let bendX = rayOut.x / max(-rayOut.z, 0.35);
  let waterMask = step(0.65, dropSeed) * smoothstep(tailLen, 0.15 * tailLen, behind) * smoothstep(1.0, 0.8, abs(sx));
  let lensOffset = vec2<f32>(bendX * bodyT * waterHalfW / (rainDensity * aspect) * LENS_GAIN, 0.0) * waterMask * depthScale;
  let displacedUV = clamp(uv + vec2<f32>(wind * 0.015, 0.008) * dropletAlpha + lensOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  let lightSrc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.002, 0.0), 0.0).rgb;
  let lightEnergy = dot(lightSrc, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = pow(lightEnergy, 3.0) * 2.5 * dropletAlpha * (1.0 + audio.z * 0.5);

  // ── Idea 3: Beer-Lambert mist on real scene depth (§12.2F) ────────────
  // Visibility falls with distance: optical depth tau grows with the sight line through the
  // haze (far = low depth), mistLayer = 1 - exp(-tau). The haze noise is smooth and drifts with
  // the rain (HEAD re-rolled hard cells every 0.5 s and scrolled them upward).
  let mistP = vec2<f32>(uv.x * rainDensity * 0.4 * aspect + wind * time * 1.2, uv.y * rainDensity * 0.4 - time * 0.3);
  let mistNoise = vnoise(mistP);
  let mistPath = 0.6 + 0.5 * (1.0 - depth);
  let mistTau = smoothstep(0.35, 0.8, mistNoise) * wetness * 0.12 * mistPath;
  let mistLayer = 1.0 - exp(-mistTau);

  let rainTint = mix(vec3<f32>(0.62, 0.76, 0.94), vec3<f32>(0.52, 0.92, 1.0), audio.y * 0.4);
  let chromaR = src.rgb + rainTint * dropletAlpha * (0.22 + audio.z * 0.18) + vec3<f32>(bloom * 0.9, bloom * 0.4, bloom * 0.15);
  let chromaG = src.rgb + rainTint * dropletAlpha * (0.20 + audio.z * 0.16) + vec3<f32>(bloom * 0.3, bloom * 0.85, bloom * 0.25);
  let chromaB = src.rgb + rainTint * dropletAlpha * (0.18 + audio.z * 0.14) + vec3<f32>(bloom * 0.1, bloom * 0.35, bloom * 0.8);
  var hdrColor = vec3<f32>(chromaR.r, chromaG.g, chromaB.b);

  hdrColor = mix(hdrColor, hdrColor * 0.72 + rainTint * 0.28, mistLayer);
  hdrColor = mix(hdrColor, hdrColor + vec3<f32>(splash * 0.35), splash);
  let finalColor = acesToneMap(hdrColor * (0.9 + audio.x * 0.15));

  let motionBlurStrength = clamp(motionBlur + splash * 0.5, 0.0, 1.0);
  let finalAlpha = clamp(dropletAlpha * motionBlurStrength * depth + mistLayer * 0.6 + splash * 0.4, 0.04, 0.96);

  let outDepth = clamp(mix(depth, 0.18 + dropletAlpha * 0.68 + splash * 0.22, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dropletAlpha, motionBlurStrength, mistLayer, finalAlpha));
}
