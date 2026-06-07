// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking (Mouse)
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, vhs-degradation, chroma-bleed, scanline-dropouts, upgraded-rgba
//  Complexity: High
//  Chunks From: vhs-tracking-mouse, IGN-dither, bass_env
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn rand(co: vec2<f32>) -> f32 {
    let seed = max(dot(co, vec2<f32>(12.9898, 78.233)), 0.001);
    return fract(sin(seed) * 43758.5453);
}

fn ign_noise(p: vec2<i32>) -> f32 {
  let f = vec2<f32>(p);
  return fract(52.9829189 * fract(dot(f, vec2<f32>(0.06711056, 0.00583715))));
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y, select(0.5, u.zoom_config.z, u.zoom_config.z >= 0.0));

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let barHeight = u.zoom_params.x * 0.3 + 0.05;
    let strength = u.zoom_params.y * 0.1 * bass_env(bass, mids);
    let noiseAmt = u.zoom_params.z;
    let colorShift = u.zoom_params.w * 0.02;

    let distY = abs(uv.y - mousePos.y);
    let in_bar = distY < barHeight;
    let bar_intensity = smoothstep(barHeight, 0.0, distY) * f32(in_bar);

    // Tracking wobble + horizontal hold instability
    let wobble = sin(uv.y * 80.0 + time * 25.0) * strength * bar_intensity;
    let holdWobble = sin(time * 3.0 + bass * 5.0) * 0.008 * bar_intensity;
    let jitter = (rand(vec2<f32>(uv.y, floor(time * 60.0))) - 0.5) * strength * 3.0 * bar_intensity;
    let displacedUV = clamp(uv + vec2<f32>(wobble + jitter + holdWobble, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV = select(uv, displacedUV, in_bar);

    // Chroma bleed: R/G/B sample at different horizontal offsets
    let bleedAmount = colorShift * (1.0 + bar_intensity * 3.0);
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(bleedAmount, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(bleedAmount * 0.3, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(bleedAmount * 0.8, 0.0), 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Scanline dropouts
    let dropoutNoise = rand(vec2<f32>(uv.x * 200.0, time * 10.0));
    let dropout = step(0.96 - bar_intensity * 0.1, dropoutNoise);
    color = mix(color, vec3<f32>(0.05), dropout * f32(in_bar));

    // Tape hiss / grain
    let n = rand(uv + vec2<f32>(time, time));
    let ign = ign_noise(coords);
    let noiseValue = (n - 0.5) * noiseAmt * f32(in_bar) + (ign - 0.5) * noiseAmt * 0.3;
    color = color + noiseValue;

    // Tracking-loss flash on treble spikes
    let flash = step(0.75, treble) * bar_intensity * rand(vec2<f32>(time * 3.0, 0.0));
    color = mix(color, vec3<f32>(1.0), flash);

    // Vignette darkening at edges
    let vig = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.5;
    color = color * (0.7 + 0.3 * vig);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + bar_intensity * 0.35 + luma * 0.15 + treble * 0.05 + flash * 0.3, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
