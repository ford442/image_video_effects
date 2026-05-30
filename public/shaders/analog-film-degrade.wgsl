// ═══════════════════════════════════════════════════════════════════
//  Analog Film Degrade
//  Category: image
//  Features: film, degrade, retro, audio-grain, jitter, vignette, color-shift
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer filmic texture, audio-reactive grain, atmospheric degradation)
// ═══════════════════════════════════════════════════════════════════
//  Created: 2026-05-23
//  By: Copilot CLI (tactical swarm)
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

let bass = plasmaBuffer[0].x;
let mids = plasmaBuffer[0].y;
let treble = plasmaBuffer[0].z;

// Grok: Richer filmic response with audio
let filmPulse = 1.0 + bass * 0.3 + treble * 0.5;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * valueNoise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let grainIntensity = u.zoom_params.x;
    let fadeAmount = u.zoom_params.y;
    let scratchFreq = u.zoom_params.z;
    let vignetteStrength = u.zoom_params.w;

    var col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let originalAlpha = col.a;

    // Film grain
    let grainSeed = uv * 512.0 + fract(time * 24.0) * 100.0;
    let grain = (hash21(grainSeed) - 0.5) * grainIntensity;
    col = col + vec4<f32>(grain, grain, grain, 0.0);

    // Dust and scratches
    let scratchTime = floor(time * 8.0);
    let scratchLine = hash11(uv.y * 100.0 + scratchTime) < scratchFreq * 0.02;
    let scratchBright = hash11(uv.x * 200.0 + scratchTime * 1.7) * 0.4;
    let dust = hash21(uv * 300.0 + scratchTime) < scratchFreq * 0.005;
    let dustBright = hash21(uv * 400.0 + scratchTime * 2.3) * 0.3;
    col = col + vec4<f32>(select(0.0, scratchBright, scratchLine));
    col = col + vec4<f32>(select(0.0, dustBright, dust));

    // === Visual Flourish: Richer, more alive film degradation ===
    let luma = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let sepia = vec3<f32>(luma * 1.2, luma * 0.9, luma * 0.6);
    col = vec4<f32>(mix(col.rgb, sepia, fadeAmount * 0.5), col.a);

    // Saturation reduction
    let gray = vec3<f32>(luma);
    col = vec4<f32>(mix(col.rgb, gray, fadeAmount * 0.3), col.a);

    // Audio-reactive film artifacts
    // Bass adds heavy contrast and "print through"
    // Treble adds fine scratches and gate weave
    let heavyDamage = bass * 0.15;
    let fineDamage = treble * 0.08;
    
    // Extra vignette and contrast from bass
    col.rgb = mix(col.rgb, col.rgb * 0.6, heavyDamage * fadeAmount);
    
    // Fine jitter / weave from treble
    let weave = sin(uv.y * 120.0 + time * 40.0) * fineDamage * fadeAmount * 0.03;
    let weaveUV = clamp(uv + vec2<f32>(weave * 0.5, weave), vec2<f32>(0.0), vec2<f32>(1.0));
    let weaveSample = textureSampleLevel(readTexture, u_sampler, weaveUV, 0.0).rgb;
    col.rgb = mix(col.rgb, weaveSample, fineDamage * 0.4);

    // Vignette
    let centerDist = length(uv - vec2<f32>(0.5));
    let vignette = smoothstep(0.5, 0.5 - vignetteStrength * 0.5, centerDist);
    col = col * vignette;

    // Clamp and preserve alpha
    col = clamp(col, vec4<f32>(0.0), vec4<f32>(1.0));
    col.a = originalAlpha;

    textureStore(writeTexture, coords, col);
}
