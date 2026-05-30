// ═══════════════════════════════════════════════════════════════════
//  CRT Phosphor
//  Category: retro-glitch
//  Features: crt-scanlines, phosphor-decay, barrel-distortion, vignette, mouse-reactive
//  Complexity: High
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let curvature = u.zoom_params.x * 0.3;
    let scanlineIntensity = u.zoom_params.y;
    let phosphorGlow = u.zoom_params.z;
    let flicker = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    // Barrel distortion (CRT curvature)
    var centered = uv - vec2<f32>(0.5);
    centered.x *= aspect;

    let dist = length(centered);
    let barrel = 1.0 + curvature * dist * dist;
    let barrelUV = centered * barrel;
    barrelUV.x /= aspect;
    let distortedUV = clamp(barrelUV + vec2<f32>(0.5), vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample base image
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // Phosphor RGB subpixel pattern
    let xPixel = f32(global_id.x) % 3.0;
    let subpixelR = smoothstep(0.0, 0.8, xPixel) * smoothstep(2.0, 1.2, xPixel);
    let subpixelG = smoothstep(0.8, 1.5, xPixel) * smoothstep(2.2, 1.5, xPixel);
    let subpixelB = smoothstep(1.5, 2.2, xPixel) * smoothstep(3.0, 2.2, xPixel);

    let subpixelMask = vec3<f32>(subpixelR, subpixelG, subpixelB) * 2.5;
    color *= mix(vec3<f32>(1.0), subpixelMask, scanlineIntensity * 0.5);

    // Scanlines
    let scanY = f32(global_id.y);
    let scanline = sin(scanY * PI) * 0.5 + 0.5;
    let scanlineMask = mix(1.0, scanline * 0.4 + 0.6, scanlineIntensity);
    color *= scanlineMask;

    // Phosphor glow (bleed between pixels)
    let glowRadius = 0.002;
    var glow = vec3<f32>(0.0);
    glow += textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + vec2<f32>(glowRadius, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.15;
    glow += textureSampleLevel(readTexture, u_sampler, clamp(distortedUV - vec2<f32>(glowRadius, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.15;
    glow += textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + vec2<f32>(0.0, glowRadius), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.15;
    glow += textureSampleLevel(readTexture, u_sampler, clamp(distortedUV - vec2<f32>(0.0, glowRadius), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.15;
    color = mix(color, glow, phosphorGlow * 0.3);

    // CRT vignette (darker at edges due to tube curvature)
    let vignette = 1.0 - smoothstep(0.3, 0.9, dist);
    color *= vignette * 0.7 + 0.3;

    // CRT flicker (power supply hum)
    let flickerAmount = sin(time * 60.0) * 0.02 + sin(time * 50.0) * 0.015;
    color *= 1.0 + flickerAmount * flicker;

    // Mouse-reactive phosphor bloom
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseGlow = exp(-mouseDist * mouseDist * 20.0) * phosphorGlow;
    if (mouseDown) {
        color += vec3<f32>(0.6, 0.8, 1.0) * mouseGlow * 0.5;
    }

    // Occasional NTSC color artifact (dot crawl)
    let dotCrawl = sin(uv.y * 200.0 + time * 20.0) * 0.5 + 0.5;
    let dotCrawlMask = smoothstep(0.45, 0.55, dotCrawl) * scanlineIntensity * 0.1;
    color.r += dotCrawlMask * 0.05;
    color.b -= dotCrawlMask * 0.03;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
