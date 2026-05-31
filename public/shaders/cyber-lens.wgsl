// ═══════════════════════════════════════════════════════════════════
//  Cyber Lens v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration, hud-overlay, glitch
//  Complexity: High
//  Chunks From: cyber-lens
//  Created: 2026-05-31
//  By: 4-Agent Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  let c = x * 0.85 + 0.30;
  return clamp((a / b) * c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hudFlicker(t: f32, bass: f32) -> f32 {
  return 1.0 - step(0.92 + bass * 0.06, fract(sin(t * 37.0) * 43758.5453)) * 0.35;
}

fn hexDist(p: vec2<f32>) -> f32 {
  let s = vec2<f32>(1.0, 1.732);
  let h = s * 0.5;
  let a = fract(p) - 0.5;
  let b = abs(a) - h;
  return dot(max(b, vec2<f32>(0.0)), vec2<f32>(1.0)) + min(max(b.x, b.y), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Param mapping: x=HUDScale, y=TargetSize, z=GlitchIntensity, w=ChromaticAberration
  let hudScale = mix(0.06, 0.45, u.zoom_params.x);
  let targetSize = mix(0.02, 0.18, u.zoom_params.y);
  let glitchIntensity = u.zoom_params.z;
  let chroma = u.zoom_params.w * 0.06;

  // Bass drives HUD flicker frequency
  let flicker = hudFlicker(time, audio.x);
  let bassPulse = 1.0 + audio.x * 0.4;
  let timeWarp = time * bassPulse;

  // Depth controls parallax between HUD layers
  let parallax1 = (uv - 0.5) * depth * 0.04;
  let parallax2 = (uv - 0.5) * depth * 0.015;
  let hudUV1 = uv - parallax1;
  let hudUV2 = uv - parallax2;

  // Cybernetic chromatic aberration around mouse
  let offset = uv - mouse;
  let delta = vec2<f32>(offset.x * aspect, offset.y);
  let dist = length(delta);
  let dir = offset / max(length(offset), 1e-4);
  let lensMask = 1.0 - smoothstep(hudScale, hudScale + 0.03, dist);

  let split = dir * chroma * lensMask * (1.0 + audio.z * 0.6);
  var lensColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(uv - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uv, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(uv + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // Glitch artifacts: horizontal slice displacement driven by bass
  let glitchSeed = floor(timeWarp * 4.0);
  let glitchLine = step(0.88, hash12(vec2<f32>(glitchSeed, uv.y * 40.0))) * glitchIntensity;
  let glitchOffset = (hash12(vec2<f32>(glitchSeed, floor(uv.y * 40.0))) - 0.5) * 0.08 * bassPulse;
  let glitchUV = vec2<f32>(uv.x + glitchOffset * glitchLine, uv.y);
  let glitchColor = textureSampleLevel(readTexture, u_sampler, clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  lensColor = mix(lensColor, glitchColor, glitchLine);

  // Primary HUD grid (layer 1)
  let gridUV = hudUV1 * 48.0;
  let lineX = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.x - timeWarp * 0.5) - 0.5));
  let lineY = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.y + timeWarp * 0.2) - 0.5));
  let grid = max(lineX, lineY) * flicker * (0.5 + audio.y * 0.7);

  // Scan lines
  let scan = 0.85 + 0.15 * sin(uv.y * dims.y * 0.5 + timeWarp * 9.0);

  // Targeting reticle at mouse (layer 1)
  let reticleDist = length((hudUV1 - mouse) * vec2<f32>(aspect, 1.0));
  let reticleRing = smoothstep(targetSize, targetSize - 0.005, reticleDist) - smoothstep(targetSize - 0.005, targetSize - 0.01, reticleDist);
  let reticleCrossH = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.y - mouse.y))) * step(reticleDist, targetSize * 1.3);
  let reticleCrossV = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.x - mouse.x))) * step(reticleDist, targetSize * 1.3);
  let reticle = (reticleRing + reticleCrossH + reticleCrossV) * flicker;

  // Corner brackets (layer 2)
  let cornerUV = abs(hudUV2 - 0.5);
  let cornerBracket = step(cornerUV.x, 0.04) * step(cornerUV.y, 0.003) + step(cornerUV.x, 0.003) * step(cornerUV.y, 0.04);
  let corner = cornerBracket * flicker;

  // Hexagonal threat zone around mouse (layer 2)
  let hexUV = (hudUV2 - mouse) * vec2<f32>(aspect, 1.0) * 14.0;
  let hex = 1.0 - smoothstep(0.0, 0.04, abs(hexDist(hexUV) - 0.42));
  let hexPulse = sin(timeWarp * 3.0 + audio.x * 6.0) * 0.5 + 0.5;
  let threat = hex * hexPulse * flicker;

  // Cyan holographic HUD composition
  let hudColor = vec3<f32>(0.05, 0.95, 0.95) * (grid + corner * 0.8) +
                 vec3<f32>(0.95, 0.35, 1.0) * reticle * 0.9 +
                 vec3<f32>(1.0, 0.2, 0.3) * threat * 0.7;

  // HDR bloom on active targets (reticle)
  let bloom = reticle * 0.5 * (1.0 + audio.y * 0.6);

  // Noise grain
  let grain = (hash13(vec3<f32>(uv * 300.0, time)) - 0.5) * 0.03;

  // Radial glow under lens
  let radialGlow = exp(-dist * 4.0) * 0.12 * bassPulse;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = lensColor * scan + hudColor + vec3<f32>(bloom) + grain + radialGlow;
  finalColor = acesToneMap(finalColor);

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, dist) * 0.2;
  finalColor = finalColor * vignette;

  let hudIntensity = clamp(lensMask + grid * 0.5 + reticle * 0.8 + corner * 0.4, 0.0, 1.0);
  let targetingConfidence = smoothstep(targetSize * 2.0, 0.0, reticleDist);
  let finalAlpha = clamp(hudIntensity * targetingConfidence * depth, 0.08, 0.98);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.3 + hudIntensity * 0.5, 0.25), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(hudIntensity, reticle, flicker, finalAlpha));
}
