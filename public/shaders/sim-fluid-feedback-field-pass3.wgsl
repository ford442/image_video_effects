// ═══════════════════════════════════════════════════════════════════
//  Sim: Fluid Feedback Field (Pass 3: Composite)
//  Category: simulation
//  Features: simulation, multi-pass-3, composite, glow, color-grading
//  Complexity: Very High
//  Upgraded: 2026-05-23
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 3 reads the density field from dataTextureC (copy
//              of Pass 2's dataTextureB), applies glow and color
//              grading, and writes the final image to writeTexture.
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=GlowIntensity
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ GLOW CALCULATION ═══
fn calculateGlow(uv: vec2<f32>, intensity: f32) -> vec3<f32> {
    var glow = vec3<f32>(0.0);
    let samples = 16;
    
    for (var i = 0; i < samples; i++) {
        let angle = f32(i) * TAU / f32(samples);
        let radius = 0.02 * (1.0 + f32(i % 4) * 0.3);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleColor = textureSampleLevel(dataTextureC, u_sampler, uv + offset, 0.0).rgb;
        glow += sampleColor;
    }
    
    return glow / f32(samples) * intensity;
}

// ═══ MAIN: COMPOSITE ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Parameters — bass amplifies glow
    let glowAmount = mix(0.5, 2.0, clamp(u.zoom_params.w, 0.0, 1.0)) * (1.0 + bass * 0.4);

    // Read density from dataTextureC (copy of Pass 2's dataTextureB)
    let density = textureLoad(dataTextureC, coord, 0).rgb;
    let densityMag = length(density);
    
    // Sample original image
    let baseColorSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseColor = baseColorSample.rgb;
    
    // Calculate glow
    let glow = calculateGlow(uv, glowAmount);
    
    // Volumetric approximation (screen-space scattering)
    var scattered = vec3<f32>(0.0);
    let scatterSamples = 8;
    let scatterDir = normalize(vec2<f32>(0.5) - uv);
    for (var i = 0; i < scatterSamples; i++) {
        let t = f32(i) / f32(scatterSamples);
        let sampleUV = uv + scatterDir * t * 0.1;
        let sampleDensity = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0).rgb;
        scattered += sampleDensity * (1.0 - t);
    }
    scattered /= f32(scatterSamples);
    
    // Combine everything
    var color = baseColor * (1.0 - densityMag * 0.5);
    color += density * 2.0;
    color += glow * densityMag;
    color += scattered * 0.5;
    
    // Color grading - boost saturation
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(luma), color, 1.3);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let effectIntensity = clamp(densityMag, 0.0, 1.0);
    let finalAlpha = mix(baseColorSample.a, 1.0, effectIntensity * 0.7);
    
    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - densityMag * 0.2), 0.0, 0.0, 1.0));
}
