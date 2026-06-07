// ═══════════════════════════════════════════════════════════════════
//  Holographic Projection Failure v2
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: holographic-projection-failure
//  Upgraded: 2026-05-30
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

const PI: f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn rand(co: vec2<f32>) -> f32 {
  return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn bitTruncate(v: f32, bits: f32) -> f32 {
  let levels = exp2(bits);
  return floor(v * levels) / levels;
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let baseInstability = u.zoom_params.x;
  let chromaticSplit = u.zoom_params.y;
  let scanDrift = u.zoom_params.z;
  let staticNoise = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Bass triggers cascading failure modes: desync, corruption, drift
  let desyncTrigger = step(0.65, bass) * baseInstability;
  let corruptionTrigger = step(0.55, bass * (0.5 + rand(vec2<f32>(time * 0.1, 0.0)))) * baseInstability;
  let driftTrigger = step(0.45, bass * mids) * baseInstability;

  // Scanline desync with horizontal jitter per scanline band
  let scanlineID = floor(uv.y * resolution.y / 3.0);
  let scanJitter = sin(scanlineID * 17.0 + time * 4.0) * desyncTrigger * 0.04;
  let vHoldJitter = sin(scanlineID * 7.0 + time * 2.0) * scanDrift * 0.02;
  let driftOffset = vec2<f32>(scanJitter + sin(time * 0.7) * driftTrigger * 0.02, vHoldJitter);

  // Phase wrapping errors in holographic interference pattern
  let phase = time * 0.8 + uv.x * 8.0 + uv.y * 5.0 + depth * TAU + scanlineID * 0.1;
  let wrappedPhase = fract(phase / TAU) * TAU;
  let wrapError = smoothstep(0.85 * TAU, TAU, phase) * corruptionTrigger * 0.5;

  // Cyan/magenta holographic color separation with temporal drift
  let holoBase = vec3<f32>(
    0.25 + 0.35 * sin(wrappedPhase),
    0.55 + 0.25 * sin(wrappedPhase + 2.094),
    0.75 + 0.25 * sin(wrappedPhase + 4.188)
  );
  let holoCyan = vec3<f32>(0.0, 0.9, 1.0);
  let holoMagenta = vec3<f32>(1.0, 0.0, 0.85);
  let driftColor = sin(uv.y * 6.0 + time * 0.5) * 0.5 + 0.5;
  let holoColor = mix(holoBase, mix(holoCyan, holoMagenta, driftColor), 0.3 + driftTrigger * 0.2);

  // Block corruption with variable block sizes
  let blockSize = vec2<f32>(mix(20.0, 4.0, corruptionTrigger), mix(5.0, 2.0, corruptionTrigger));
  let block = floor((uv + driftOffset) * resolution / blockSize);
  let blockNoise = rand(block + time * 0.5);
  let corruptionMask = step(1.0 - corruptionTrigger * 0.7, blockNoise);

  // Bit-depth truncation artifacts (posterization)
  let bitDepth = mix(8.0, 3.0, corruptionTrigger * staticNoise);
  let sampleUV = clamp(uv + driftOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let truncated = vec3<f32>(
    bitTruncate(src.r, bitDepth),
    bitTruncate(src.g, bitDepth),
    bitTruncate(src.b, bitDepth)
  );

  // Chromatic aberration from drift and depth parallax
  let shift = chromaticSplit * 0.025 * (1.0 + driftTrigger) * (0.8 + depth * 0.4);
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromatic = vec3<f32>(rSample, src.g, bSample);

  // Flicker from desync failures
  let flicker = step(rand(vec2<f32>(time * 15.0, scanlineID)), 0.92 - desyncTrigger * 0.4);

  // Ghost image from previous frame offset
  let ghost = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.01 * sin(time), 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.15 * driftTrigger;

  // Combine corrupted source with holographic overlay
  let glitched = mix(chromatic, truncated, corruptionMask * 0.6);
  let hologram = mix(glitched * flicker + ghost, holoColor, 0.35 + treble * 0.2);

  // Mouse repairs the projection in a local radius
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let repairRadius = smoothstep(0.22, 0.0, mouseDist) * mouseDown;
  let repaired = mix(hologram, src.rgb, repairRadius * 0.8);

  // Depth controls projection plane distance
  let planeDist = mix(0.5, 1.0, depth);
  let projected = mix(repaired, repaired * planeDist + vec3<f32>(0.02, 0.05, 0.08) * (1.0 - planeDist), 0.3);

  let finalColor = acesTone(max(projected, vec3<f32>(0.0)));

  // Static noise overlay
  let staticOverlay = rand(uv * resolution + time * 100.0) * staticNoise * 0.25;
  let withStatic = finalColor + vec3<f32>(staticOverlay * (0.5 + desyncTrigger));

  // Alpha: projection stability × (1.0 - failure_intensity) × depth
  let failureIntensity = max(desyncTrigger, max(corruptionTrigger, driftTrigger));
  let stability = 1.0 - failureIntensity * 0.6 + repairRadius * 0.4;
  let alpha = clamp(stability * (1.0 - failureIntensity * 0.5) * depth + staticOverlay * 0.3, 0.12, 0.9);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(withStatic, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(failureIntensity, flicker, wrapError, alpha));
}
