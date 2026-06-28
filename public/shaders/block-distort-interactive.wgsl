// ================================================================
//  Block Distort — Lighting & Glow Enhanced
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, volumetric-glow, rim-lighting
//  Complexity: Medium-High
//  Chunks From: block-distort-interactive
//  Created: 2026-05-30
//  Enhanced: 2026-06-28
// ================================================================

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
  zoom_params: vec4<f32>,  // x=BlockSize, y=PushStrength, z=RGBSplit, w=Radius
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// ═══ Volumetric Light Accumulation ═══
fn volumetricGlow(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32, radius: f32, time: f32) -> f32 {
  let d = length(uv - lightPos);
  let core = exp(-d * d * (15.0 / radius));
  // Scattering halo with noise modulation
  let noise = hash21(uv * 8.0 + time * 0.5);
  let halo = exp(-d * 3.0) * (0.6 + noise * 0.4);
  return (core * 0.7 + halo * 0.3) * intensity;
}

// ═══ Rim Lighting on Grid Edges ═══
fn rimLight(viewDir: vec2<f32>, edgeNormal: vec2<f32>, strength: f32) -> f32 {
  let rim = 1.0 - max(dot(viewDir, edgeNormal), 0.0);
  return pow(rim, 3.0) * strength;
}

// ═══ Bloom-weighted alpha ═══
fn bloomAlpha(rgb: vec3<f32>, baseAlpha: f32) -> f32 {
  let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 2.5;
  return clamp(baseAlpha + bloomWeight, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let blockScale = mix(8.0, 72.0, u.zoom_params.x);
  let pushStrength = u.zoom_params.y * 0.20;
  let rgbSplit = u.zoom_params.z * 0.03;
  let radius = mix(0.05, 0.75, u.zoom_params.w);

  let grid = floor(uv * blockScale);
  let cellCenter = (grid + 0.5) / blockScale;
  let delta = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let influence = 1.0 - smoothstep(0.0, radius, dist);
  let direction = safeNormalize(delta + vec2<f32>(0.0005, 0.0));
  let shove = direction * pushStrength * influence * (1.0 + bass * 0.8);
  let wobble = vec2<f32>(sin(time * 2.0 + grid.y), cos(time * 1.7 + grid.x)) * 0.01 * treble;
  let sampleUV = clamp(uv + shove + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

  let splitVec = safeNormalize(direction + vec2<f32>(0.0005, 0.0005)) * rgbSplit * influence;
  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let gridLine = 1.0 - smoothstep(0.46, 0.50, max(abs(fract(uv * blockScale) - 0.5).x, abs(fract(uv * blockScale) - 0.5).y));
  let prismTint = mix(vec3<f32>(0.10, 0.9, 1.0), vec3<f32>(1.0, 0.30, 0.8), 0.5 + 0.5 * sin(time + grid.x * 0.3));
  finalColor = finalColor + prismTint * (gridLine * 0.10 + influence * 0.12 * mids);

  // ═══ VOLUMETRIC LIGHTING ═══
  // Light source at mouse position, pulsing with bass
  let lightIntensity = 1.0 + bass * 1.5 + sin(time * 4.0) * 0.3;
  let volGlow = volumetricGlow(uv, mouse, lightIntensity, radius * 1.5, time);
  // Warm key light color (5600K approx: warm white with slight gold)
  let keyLightColor = vec3<f32>(1.0, 0.92, 0.78);
  finalColor = finalColor + keyLightColor * volGlow * influence * 0.6;

  // Secondary fill glow from cell centers (cool blue 3200K)
  let fillGlow = volumetricGlow(uv, cellCenter, 0.5 + mids * 0.8, 0.15, time + 1.0);
  let fillColor = vec3<f32>(0.65, 0.75, 1.0);
  finalColor = finalColor + fillColor * fillGlow * gridLine * 0.4;

  // ═══ RIM LIGHTING ON GRID EDGES ═══
  let viewDir = safeNormalize(uv - mouse + vec2<f32>(0.0001));
  // Grid edge normal approximation: direction away from cell center
  let cellEdge = abs(fract(uv * blockScale) - 0.5);
  let edgeFactor = smoothstep(0.48, 0.50, max(cellEdge.x, cellEdge.y));
  let edgeNormal = safeNormalize(uv - cellCenter);
  let rim = rimLight(viewDir, edgeNormal, 1.0 + bass * 2.0);
  // Hot rim light color (7000K: bluish white)
  let rimColor = vec3<f32>(0.85, 0.90, 1.0);
  finalColor = finalColor + rimColor * rim * edgeFactor * influence * 0.8;

  // ═══ AUDIO-REACTIVE LIGHT PULSE ═══
  // Bass drives a pulsing glow ring around the mouse
  let pulseRing = smoothstep(0.02, 0.0, abs(dist - radius * 0.5 - bass * 0.2));
  let pulseColor = mix(vec3<f32>(1.0, 0.4, 0.1), vec3<f32>(0.2, 0.6, 1.0), mids);
  finalColor = finalColor + pulseColor * pulseRing * bass * 0.5;

  // Treble-driven sparkle on grid intersections
  let sparkle = hash21(grid + time * 0.1) * treble * gridLine * 0.3;
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.8) * sparkle;

  // Light attenuation: falloff from mouse
  let falloff = 1.0 / (1.0 + 2.0 * dist + 4.0 * dist * dist);
  finalColor = finalColor * (0.7 + falloff * 0.3);

  // ═══ ENHANCED ALPHA WITH BLOOM WEIGHT ═══
  let finalAlpha = bloomAlpha(finalColor, clamp(0.70 + influence * 0.18 + gridLine * 0.08 + volGlow * 0.2, 0.42, 0.98));
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.22 + influence * 0.68 + volGlow * 0.15, 0.30), 0.0, 1.0);

  // Premultiplied alpha writeback
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor * finalAlpha, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, gridLine, volGlow, finalAlpha));
}
