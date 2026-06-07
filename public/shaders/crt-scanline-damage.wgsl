// ═══════════════════════════════════════════════════════════════════
//  CRT Scanline Damage
//  Category: image
//  Features: upgraded-rgba, retro, glitch, barrel-distortion,
//            temporal-phosphor, audio-rgb-separation, depth-aware-barrel
//  Complexity: Medium
//  Created: 2026-05-23
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let scanlineIntensity = u.zoom_params.x;
    let distortionAmount = u.zoom_params.y;
    let flickerSpeed = u.zoom_params.z;
    let rgbSeparation = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Depth-aware barrel distortion: closer objects distort more
    let centered = uv - vec2<f32>(0.5);
    let r2 = dot(centered, centered);
    let r4 = r2 * r2;
    let depthDistortion = distortionAmount * (1.0 + depth * 0.5);
    let distortion = 1.0 + depthDistortion * r2 + depthDistortion * 0.5 * r4;
    let distortedUV = centered * distortion + vec2<f32>(0.5);

    // Audio-driven RGB channel separation
    let sep = rgbSeparation * 0.008 * (1.0 + bass * 0.4);
    let rUV = distortedUV + vec2<f32>(sep, 0.0);
    let gUV = distortedUV;
    let bUV = distortedUV - vec2<f32>(sep, 0.0);

    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let baseAlpha = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;

    let scanline = sin(uv.y * res.y * 3.14159) * 0.5 + 0.5;
    let scanlineMask = mix(1.0, 0.85 + scanline * 0.15, scanlineIntensity);
    col = col * scanlineMask;

    let pixelX = f32(global_id.x) % 3.0;
    let phosphorR = select(1.0, 0.85, pixelX != 0.0);
    let phosphorG = select(1.0, 0.85, pixelX != 1.0);
    let phosphorB = select(1.0, 0.85, pixelX != 2.0);
    col = col * vec3<f32>(phosphorR, phosphorG, phosphorB);

    let flicker = 1.0 + sin(time * flickerSpeed * 10.0) * 0.03 * flickerSpeed;
    col = col * flicker;

    let rollTrigger = hash11(floor(time * 2.0)) < 0.05;
    let rollOffset = fract(hash11(floor(time * 2.0) + 100.0) + time * 0.5);
    let inRollBand = abs(uv.y - rollOffset) < 0.02;
    col = select(col, col * 0.5 + vec3<f32>(0.05), rollTrigger && inRollBand);

    let edgeDarken = 1.0 - smoothstep(0.3, 0.7, r2) * 0.3;
    col = col * edgeDarken;

    // Temporal phosphor decay: previous frame bleeds in for CRT persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let phosphorDecay = mix(col, prev * 0.85, 0.06 + mids * 0.02);
    col = mix(col, phosphorDecay, 0.5);

    let finalColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), baseAlpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
