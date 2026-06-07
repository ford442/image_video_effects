// ═══════════════════════════════════════════════════════════════════
//  ASCII Glyph
//  Category: stylize
//  Features: animated, depth-luminance, bass-character-swap, upgraded-rgba
//  Complexity: High
//  Chunks From: ascii-glyph, bass_env
//  Created: 2024-01-01
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let glyphSize = mix(4.0, 32.0, u.zoom_params.x) * bass_env(bass, mids);
    let brightness = u.zoom_params.y;
    let colorAmount = u.zoom_params.z;
    let densityBoost = u.zoom_params.w;

    let pixelUV = uv * resolution;
    let cell = floor(pixelUV / glyphSize);
    let cellUV = fract(pixelUV / glyphSize);
    let cellCenter = (cell + 0.5) * glyphSize / resolution;

    // Sample luminance at cell center with depth weighting
    let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenter, 0.0);
    let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depthLuma = mix(luma, luma * (1.0 - depth), 0.3);

    // Character density: higher for bright areas, boosted by densityBoost
    let charDensity = smoothstep(0.3, 0.9, depthLuma + densityBoost * 0.2);

    // Bass character swap: swap glyph patterns on strong beats
    let beatSwap = hash12(cell + vec2<f32>(floor(bass * 5.0), 0.0));
    let glyphPattern = hash12(cell + vec2<f32>(beatSwap, 0.0));

    let glyphThreshold = glyphPattern;
    let isGlyph = step(glyphThreshold, charDensity);

    // Glyph SDF approximation: simple cross/dot
    let crossDist = min(abs(cellUV.x - 0.5), abs(cellUV.y - 0.5));
    let dotDist = length(cellUV - vec2<f32>(0.5));
    let glyphShape = select(1.0 - smoothstep(0.0, 0.15, crossDist), 1.0 - smoothstep(0.0, 0.2, dotDist), glyphPattern > 0.5);
    let glyphAlpha = glyphShape * isGlyph;

    // Depth-based color: foreground brighter, background darker
    let glyphColor = mix(
        vec3<f32>(0.8, 0.9, 1.0),
        centerColor.rgb * (1.0 + treble * 0.5),
        colorAmount
    );
    let depthColor = mix(vec3<f32>(0.3, 0.4, 0.5), glyphColor, depth);

    let finalRGB = depthColor * glyphAlpha * brightness;
    let alpha = clamp(glyphAlpha * brightness + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
