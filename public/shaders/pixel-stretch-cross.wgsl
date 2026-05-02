// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Cross — Visualist Upgrade
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgrades: HDR workflow, ACES tone mapping, atmospheric glow,
//            chromatic aberration, split-tone color grading,
//            depth-aware intensity, vignette
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

// Param 1: Stretch Width
// Param 2: Decay
// Param 3: Mix Strength
// Param 4: Opacity

// ═══ SRGB ↔ Linear conversion for HDR workflow ═══
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}

fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}

// ═══ ACES Filmic Tone Mapping (approximate) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Color temperature: warm highlights, cool shadows ═══
fn colorTemperature(col: vec3<f32>, temp: f32) -> vec3<f32> {
    let warm = vec3<f32>(1.14, 1.02, 0.90);
    let cool = vec3<f32>(0.90, 0.98, 1.12);
    return col * mix(cool, warm, clamp(temp, 0.0, 1.0));
}

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = get_mouse();
    let time = u.config.x;
    let audio = plasmaBuffer[0];

    let stretch_width = u.zoom_params.x;
    let decay = u.zoom_params.y * 10.0;
    let mix_strength = u.zoom_params.z;
    let opacity = u.zoom_params.w;

    // Audio-reactive pulse and animated shimmer
    let pulse = 1.0 + audio.x * 0.3;
    let shimmer = 1.0 + sin(time * 3.0 + uv.x * 10.0) * 0.05 * audio.y;

    // Sample source color and depth
    let srcSrgb = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcLin = vec4<f32>(srgbToLinear(srcSrgb.rgb), srcSrgb.a);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 1.0 - depth * 0.35;

    // Chromatic aberration offset scales with stretch width
    let ca = stretch_width * 0.025;

    var hdr = srcLin.rgb;
    var glowAccum = vec3<f32>(0.0);

    // ═══ Horizontal stretch arm ═══
    if (abs(uv.y - mouse.y) < stretch_width) {
        let dist = abs(uv.x - mouse.x);
        let factor = exp(-dist * decay) * mix_strength * pulse * depthFactor;

        let smearUv = vec2<f32>(mouse.x, uv.y);
        let r = textureSampleLevel(readTexture, u_sampler, smearUv + vec2<f32>(ca, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, smearUv, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, smearUv - vec2<f32>(ca, 0.0), 0.0).b;
        let smear = srgbToLinear(vec3<f32>(r, g, b));

        // Volumetric glow bloom along the arm
        let glow = exp(-dist * decay * 0.4) * 0.4 * shimmer * (1.0 + audio.y * 0.5);
        glowAccum = glowAccum + smear * glow;
        hdr = mix(hdr, smear, factor);
    }

    // ═══ Vertical stretch arm ═══
    if (abs(uv.x - mouse.x) < stretch_width) {
        let dist = abs(uv.y - mouse.y);
        let factor = exp(-dist * decay) * mix_strength * pulse * depthFactor;

        let smearUv = vec2<f32>(uv.x, mouse.y);
        let r = textureSampleLevel(readTexture, u_sampler, smearUv + vec2<f32>(0.0, ca), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, smearUv, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, smearUv - vec2<f32>(0.0, ca), 0.0).b;
        let smear = srgbToLinear(vec3<f32>(r, g, b));

        let glow = exp(-dist * decay * 0.4) * 0.4 * shimmer * (1.0 + audio.y * 0.5);
        glowAccum = glowAccum + smear * glow;
        hdr = mix(hdr, smear, factor);
    }

    // Composite additive atmospheric glow
    hdr = hdr + glowAccum;

    // Center hot spot for extra punch
    let centerDist = length(uv - mouse);
    let hotSpot = exp(-centerDist * 18.0) * 0.7 * mix_strength * pulse * depthFactor;
    hdr = hdr + srcLin.rgb * hotSpot;

    // Split-tone color grading: warm highlights, cool shadows
    let lum = dot(hdr, vec3<f32>(0.299, 0.587, 0.114));
    let temp = smoothstep(0.0, 0.5, lum);
    let audioTemp = audio.z * 0.15;
    hdr = colorTemperature(hdr, temp + audioTemp);

    // ACES tone mapping with slight HDR boost
    var mapped = acesToneMap(hdr * (1.0 + mix_strength * 0.3));

    // Vignette for atmospheric depth
    let vignette = 1.0 - smoothstep(0.4, 1.2, length(uv - 0.5) * 1.4);
    mapped = mapped * (0.88 + vignette * 0.12);

    // Final composite with opacity control
    let outSrgb = mix(srcSrgb.rgb, linearToSrgb(mapped), opacity);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outSrgb, srcSrgb.a));
}
