// ═══════════════════════════════════════════════════════════════════
//  Digital Glitch
//  Category: visual-effects
//  Features: post-processing, rgb-split, scan-lines, data-mosh
//  Complexity: Medium
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let glitchAmount = u.zoom_params.x;
    let rgbShift = u.zoom_params.y * 0.04;
    let blockSize = u.zoom_params.z * 20.0 + 4.0;
    let scanLineIntensity = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let mouseInfluence = length(uv - mouse) * 2.0;

    // Seed-based glitch blocks
    let blockX = floor(uv.x * blockSize);
    let blockY = floor(uv.y * blockSize);
    let blockSeed = hash(vec2<f32>(blockX, blockY) + floor(time * 8.0));
    let blockSeed2 = hash(vec2<f32>(blockX, blockY) + floor(time * 12.0 + 50.0));

    // Horizontal slice displacement
    let sliceY = floor(uv.y * 30.0);
    let sliceSeed = hash1(sliceY + floor(time * 15.0));
    let sliceOffset = (sliceSeed - 0.5) * glitchAmount * 0.15 * step(0.85, sliceSeed);

    // Mouse amplifies glitch near cursor
    let mouseGlitch = glitchAmount * (1.0 + smoothstep(0.1, 0.0, mouseInfluence) * 2.0);

    var displacedUV = uv;
    displacedUV.x += sliceOffset * mouseGlitch;

    // Block displacement
    if (blockSeed > 0.92) {
        displacedUV.x += (blockSeed2 - 0.5) * mouseGlitch * 0.1;
    }
    if (blockSeed > 0.97) {
        displacedUV.y += (hash1(blockX) - 0.5) * mouseGlitch * 0.03;
    }

    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // RGB channel split
    let shiftAmount = rgbShift * mouseGlitch * (0.5 + blockSeed * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(shiftAmount, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(shiftAmount, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Scan lines
    let scanLine = sin(uv.y * resolution.y * 0.7) * 0.5 + 0.5;
    let scanLineMask = mix(1.0, scanLine, scanLineIntensity);
    color *= scanLineMask;

    // Block color inversion
    if (blockSeed > 0.95 && blockSeed2 > 0.5) {
        color = vec3<f32>(1.0) - color;
        color *= vec3<f32>(1.2, 0.8, 1.1);
    }

    // Digital noise
    let noise = hash(uv * 100.0 + time * 73.0) - 0.5;
    color += noise * mouseGlitch * 0.15;

    // Corruption lines (rare)
    if (hash(vec2<f32>(floor(uv.y * 80.0), floor(time * 20.0))) > 0.995) {
        color = vec3<f32>(1.0, 0.0, 0.5);
    }

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
