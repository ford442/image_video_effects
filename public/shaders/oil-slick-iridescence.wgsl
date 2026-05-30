// ═══════════════════════════════════════════════════════════════════
//  Oil Slick Iridescence
//  Category: image
//  Features: audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  Simulates thin-film optical interference (like oil on water).
//  A procedural height map modulates film thickness; the resulting
//  phase shifts produce wavelength-dependent constructive/destructive
//  interference visible as shifting rainbow colours overlaid on the
//  source image. Bass warps the height map; mouse creates ripples.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=Thickness, y=IridescentStrength, z=FlowSpeed, w=Blend
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),             hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < oct; i++) {
        val  += vnoise(p * freq) * amp;
        freq *= 2.0;
        amp  *= 0.5;
    }
    return val;
}

// Thin-film interference: given phase, return intensity for wavelength lambda
fn thinFilmIntensity(phase: f32) -> f32 {
    return 0.5 + 0.5 * cos(phase);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio
    let bass   = extraBuffer[0];
    let mid    = extraBuffer[1];
    let treble = extraBuffer[2];

    // Params
    let thicknessBase = mix(0.2, 2.0, u.zoom_params.x) * (1.0 + bass * 1.5);
    let iriStr        = mix(0.0, 1.0, u.zoom_params.y);
    let flowSpeed     = mix(0.05, 0.5, u.zoom_params.z);
    let blend         = mix(0.0, 1.0, u.zoom_params.w);

    // Source
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Flowing height field
    let flowUV = uv + vec2<f32>(time * flowSpeed * 0.3, time * flowSpeed * 0.2);
    let h      = fbm(flowUV * 4.0, 5) * thicknessBase;

    // Mouse ripple contribution
    let mouse = u.zoom_config.yz;
    let mDist = length(uv - mouse);
    let ripple = sin(mDist * 30.0 - time * 6.0) * exp(-mDist * 8.0) * u.zoom_config.w;
    let filmThickness = h + ripple * 0.3;

    // Thin-film IOR (oil, n≈1.46)
    let n = 1.46;
    // Wavelengths for R (700nm), G (546nm), B (440nm)
    let cosTheta = 0.85; // assume near-normal incidence
    let pathDiff = 2.0 * n * filmThickness * cosTheta;

    let phaseR = TAU * pathDiff / 700.0;
    let phaseG = TAU * pathDiff / 546.0;
    let phaseB = TAU * pathDiff / 440.0;

    let iR = thinFilmIntensity(phaseR);
    let iG = thinFilmIntensity(phaseG);
    let iB = thinFilmIntensity(phaseB);

    let iridCol = vec3<f32>(iR, iG, iB) * iriStr * (1.0 + mid * 0.5);

    // Blend onto source
    var finalRGB = mix(src.rgb, src.rgb * iridCol + iridCol * 0.15, blend);
    finalRGB = clamp(finalRGB, vec3<f32>(0.0), vec3<f32>(1.5));

    // Semantic alpha
    let alpha = clamp(src.a, 0.0, 1.0);

    let outColor = vec4<f32>(finalRGB, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(filmThickness * 0.1, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(iR, iG, iB, filmThickness));
}
