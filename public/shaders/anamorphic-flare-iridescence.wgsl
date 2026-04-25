// ═══════════════════════════════════════════════════════════════════
//  anamorphic-flare-iridescence
//  Category: advanced-hybrid
//  Features: lens-flare, thin-film-interference, spectral-render, mouse-driven, HDR
//  Complexity: Very High
//  Chunks From: anamorphic-flare, spec-iridescence-engine
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Cinematic anamorphic lens flare combined with thin-film interference.
//  The flare streaks and ghost elements carry rainbow iridescence colors
//  modulated by viewing angle. Film thickness varies across the flare
//  structure, creating soap-bubble chromatic effects on the lens artifacts.
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
const TWO_PI: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn hexagonAperture(uv: vec2<f32>, size: f32) -> f32 {
  let r = length(uv);
  let angle = atan2(uv.y, uv.x);
  let sectorAngle = fract(angle / (PI / 3.0)) * (PI / 3.0) - PI / 6.0;
  let dist = r * cos(sectorAngle) / cos(PI / 6.0);
  return smoothstep(size + 0.01, size - 0.01, dist);
}

fn anamorphicStreak(uv: vec2<f32>, lightPos: vec2<f32>, streakLength: f32, width: f32) -> f32 {
  let toLight = uv - lightPos;
  let distX = abs(toLight.x);
  let distY = abs(toLight.y);
  let hStreak = exp(-distX / streakLength) * exp(-distY * 50.0 / width);
  let vStreak = exp(-distY / (streakLength * 0.1)) * exp(-distX * 100.0 / width);
  return hStreak * 0.9 + vStreak * 0.1;
}

fn ghostElement(uv: vec2<f32>, lightPos: vec2<f32>, offset: vec2<f32>, size: f32) -> f32 {
  let center = vec2<f32>(0.5, 0.5);
  let ghostPos = center + (center - lightPos) * offset * 2.0 + offset;
  let dist = length(uv - ghostPos);
  let hexUV = (uv - ghostPos) / size;
  let hex = hexagonAperture(hexUV, 0.8);
  let falloff = exp(-dist * dist * 8.0 / size);
  return hex * falloff;
}

fn centralGlow(uv: vec2<f32>, lightPos: vec2<f32>, size: f32) -> f32 {
  let dist = length(uv - lightPos);
  let core = exp(-dist * 15.0 / size);
  let corona = exp(-dist * 5.0 / size) * 0.3;
  return core + corona;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;

  let flareIntensity = u.zoom_params.x * 3.0;
  let streakLength = u.zoom_params.y * 0.8 + 0.05;
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.z);
  let filmIOR = mix(1.2, 2.4, u.zoom_params.w);

  let lightPos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var flareColor = vec3<f32>(0.0);

  // Viewing angle for iridescence
  let toCenter = uv - vec2<f32>(0.5);
  let distCenter = length(toCenter);
  let cosTheta = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.01));

  // 1. Anamorphic streak with iridescence
  let streak = anamorphicStreak(uv, lightPos, streakLength, 2.0);
  let streakThickness = filmThicknessBase * (0.5 + streak * 300.0);
  let streakIrid = thinFilmColor(streakThickness, cosTheta, filmIOR);
  flareColor += streak * streakIrid * flareIntensity;

  // 2. Ghost reflections with per-ghost interference
  let ghostCount = i32(u.zoom_params.y * 5.0 + 1.0);
  for (var i: i32 = 0; i < ghostCount; i++) {
    let fi = f32(i);
    let ghostOffset = vec2<f32>(
      sin(fi * 1.3 + time * 0.1) * 0.15 + fi * 0.08,
      cos(fi * 0.7) * 0.1 + fi * 0.05
    );
    let ghostSize = 0.08 - fi * 0.01;
    let ghostIntensity = (0.4 - fi * 0.06) * flareIntensity;
    let ghost = ghostElement(uv, lightPos, ghostOffset, ghostSize);
    let ghostThickness = filmThicknessBase * (0.8 + fi * 0.3);
    let ghostIrid = thinFilmColor(ghostThickness, cosTheta, filmIOR);
    flareColor += ghost * ghostIntensity * ghostIrid;
  }

  // 3. Central glow with interference halo
  let glow = centralGlow(uv, lightPos, 0.15);
  let glowThickness = filmThicknessBase * (1.0 + glow * 200.0);
  let glowIrid = thinFilmColor(glowThickness, cosTheta, filmIOR);
  flareColor += glow * glowIrid * flareIntensity * 0.8;

  // 4. Starburst with spectral dispersion
  let toLight = uv - lightPos;
  let angle = atan2(toLight.y, toLight.x);
  let dist = length(toLight);
  let starburst = pow(abs(sin(angle * 6.0)), 20.0) * exp(-dist * 3.0);
  let starThickness = filmThicknessBase * (0.3 + starburst * 400.0);
  let starIrid = thinFilmColor(starThickness, cosTheta, filmIOR);
  flareColor += starburst * starIrid * flareIntensity * 0.3;

  // 5. Rainbow halo ring
  let haloDist = abs(dist - 0.25);
  let haloIntensity = exp(-haloDist * 100.0) * 0.5;
  let rainbowPhase = angle * 3.0;
  let rainbow = vec3<f32>(
    (sin(rainbowPhase) + 1.0) * 0.5,
    (sin(rainbowPhase + TWO_PI / 3.0) + 1.0) * 0.5,
    (sin(rainbowPhase + 2.0 * TWO_PI / 3.0) + 1.0) * 0.5
  );
  flareColor += rainbow * haloIntensity * flareIntensity * 0.2;

  // Mouse interaction: local thickness perturbation
  if (isMouseDown) {
    let mouseDist = length(uv - lightPos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
    let mouseIrid = thinFilmColor(filmThicknessBase + mouseInfluence * 300.0, cosTheta, filmIOR);
    flareColor = mix(flareColor, mouseIrid * flareIntensity, mouseInfluence * 0.5);
  }

  let finalColor = baseColor.rgb + flareColor;
  let tonemapped = finalColor / (1.0 + finalColor * 0.1);

  // Alpha stores film thickness for downstream
  textureStore(writeTexture, gid.xy, vec4<f32>(tonemapped, filmThicknessBase / 1000.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(flareColor, filmThicknessBase / 1000.0));

  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
