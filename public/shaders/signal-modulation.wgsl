// ═══════════════════════════════════════════════════════════════════
//  Signal Modulation
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, chromatic-aberration, spectral-bands, upgraded-rgba
//  Complexity: High
//  Chunks From: signal-modulation, bass_env, hue_preserve_clamp
//  Upgraded: 2026-05-31
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn huePreserveClamp(col: vec3<f32>, maxRGB: f32) -> vec3<f32> {
  let mx = max(max(col.r, col.g), col.b);
  if (mx > maxRGB) {
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    return mix(col * (maxRGB / mx), vec3<f32>(lum), 0.15);
  }
  return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAtten = mix(1.0, 0.6, depth);

    let freq = mix(1.0, 50.0, u.zoom_params.x) * bass_env(bass, mids);
    let amp = mix(0.0, 0.5, u.zoom_params.y) * (1.0 + mids * 0.3);
    let speed = mix(0.0, 10.0, u.zoom_params.z) * (1.0 + treble * 0.25);
    let colorSplit = u.zoom_params.w * 0.02 * (1.0 + bass * 0.1);
    let lineWidth = 0.006 + amp * 0.03;

    let proximity = distance(uv, mousePos);
    let wave = 0.5 + amp * sin((uv.x + proximity * 2.0) * freq + time * speed);
    let distanceToWave = abs(uv.y - wave);
    let signal = 1.0 - smoothstep(lineWidth, lineWidth + 0.005, distanceToWave);
    let displacement = signal * amp * 0.1;

    // Spectral band visualization: divide screen into 8 frequency bands
    let band = floor(uv.y * 8.0);
    let bandNoise = fract(sin(band * 12.9898 + time) * 43758.5453);
    let bandAmp = mix(0.1, 1.0, bandNoise) * (1.0 + bass * 0.5);
    let bandMask = smoothstep(0.0, 0.02, abs(fract(uv.y * 8.0) - 0.5)) * signal * bandAmp;

    let baseUV = clamp(uv + vec2<f32>(0.0, displacement), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let offset = vec2<f32>(colorSplit * signal * (0.5 + treble * 0.5), 0.0);
    let uvR = clamp(baseUV + offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvG = baseUV;
    let uvB = clamp(baseUV - offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
    let glow = vec3<f32>(0.15 + bandMask * 0.5, 0.35 + treble * 0.08 + bandMask * 0.3, 0.55 + bandMask * 0.2) * signal;
    var finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
        baseColor.g,
        textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
    ) + glow;

    // Noise floor
    let noiseFloor = (fract(sin(dot(uv + time, vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02 * signal;
    finalColor = finalColor + vec3<f32>(noiseFloor);

    finalColor = huePreserveClamp(finalColor, 1.8) * depthAtten;
    let alpha = clamp(baseColor.a * 0.45 + signal * 0.35 + bass * 0.05 + bandMask * 0.2, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r + signal * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
