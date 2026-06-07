// ═══════════════════════════════════════════════════════════════════
//  Glitch Slice Mirror
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / u.config.zw;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let paramIntensity = u.zoom_params.x;
    let paramSpeed = u.zoom_params.y;
    let paramScale = u.zoom_params.z;
    let paramDetail = u.zoom_params.w;

    let audioBoost = 1.0 + bass * 0.5 + mids * 0.25;

    // Mirror Logic — branchless
    let mirrorActive = uv.x > mouse.x;
    var target_uv = uv;
    target_uv.x = select(target_uv.x, mouse.x - (uv.x - mouse.x), mirrorActive);

    // Glitch Logic near seam
    let glitch_width = 0.1 * max(paramIntensity * 2.0, 0.001);
    let dist_to_seam = abs(uv.x - mouse.x);
    let inGlitch = dist_to_seam < glitch_width;

    let intensity = (1.0 - dist_to_seam / max(glitch_width, 0.001)) * audioBoost * f32(inGlitch);

    // Blocky noise
    let block_size = vec2<f32>(
        0.02 + paramScale * 0.06,
        0.01 + paramScale * 0.02
    );
    let seed = floor(uv / max(block_size, vec2<f32>(0.001))) + time * (0.1 + paramSpeed * 2.0);
    let noise = hash(fract(seed));

    let bigNoise = noise > 0.8;
    target_uv.x = select(target_uv.x, target_uv.x + (noise - 0.5) * 0.1 * intensity, bigNoise);

    // Clamp after displacement
    target_uv = clamp(target_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic Aberration
    let split = (0.005 + paramDetail * 0.03) * intensity * noise;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(target_uv + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(target_uv - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // Luminance-based alpha
    let lum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let glitchAlpha = clamp(lum, 0.3, 1.0);

    var glitchColor = vec4<f32>(r, g, b, glitchAlpha);

    // Scanline darkening — branchless
    let scanline = sin(uv.y * (50.0 + paramDetail * 300.0));
    let inScanline = scanline > 0.9;
    glitchColor = select(glitchColor, vec4<f32>(glitchColor.rgb * 0.5, glitchColor.a), inScanline);

    // Sample base texture
    let baseColor = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0);

    // Mix between base and glitch based on whether we're in glitch region
    var finalColor = mix(baseColor, glitchColor, f32(inGlitch));

    // Alpha strategy: blend based on glitch intensity and luminance
    let finalLum = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    finalColor.a = clamp(0.5 + intensity * 0.3 + finalLum * 0.2, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, target_uv, 0.0).r;

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
