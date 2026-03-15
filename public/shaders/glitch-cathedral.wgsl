// ═══════════════════════════════════════════════════════════════
//  Glitch Cathedral - Stained Glass with Alpha Shattering
//  Category: retro-glitch
//
//  Stained glass distortion effect:
//  - Geometric cell patterns with rotating elements
//  - RGB channel separation on mouse glitch
//  - Pixel sorting effect with depth
//  - Alpha shattering in glitch regions
//  - Vignette and scanlines with transparency preservation
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

// Mapping notes: mouse in zoom_config.yz; zoom_params: x=cellSize, y=rgbSplit, z=sortStrength, w=patternSpeed

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898,78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let glitchIntensity = u.zoom_config.x;

    // Geometric cell pattern
    let cellSize = max(1.0, u.zoom_params.x);
    let cellUV = fract(uv * cellSize);
    let cellID = floor(uv * cellSize);

    // Rotating pattern within cells
    let patternAngle = time * u.zoom_params.w + hash(cellID);
    let centered = cellUV - vec2<f32>(0.5);
    let rotUV = vec2<f32>(
        cos(patternAngle) * centered.x - sin(patternAngle) * centered.y + 0.5,
        sin(patternAngle) * centered.x + cos(patternAngle) * centered.y + 0.5
    );

    // Distance to cell center for stained glass effect
    let distToCenter = distance(rotUV, vec2<f32>(0.5));
    let glassPattern = smoothstep(0.4, 0.41, distToCenter) * (1.0 - smoothstep(0.59, 0.6, distToCenter));

    // RGB channel separation on mouse glitch
    let rgbSplit = u.zoom_params.y * glitchIntensity;
    let rUV = clamp(uv + (mousePos - uv) * rgbSplit, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = uv;
    let bUV = clamp(uv - (mousePos - uv) * rgbSplit, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample each channel with alpha
    let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
    let gSample = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);

    // Alpha shattering: glitch creates transparency variations
    var finalAlpha = gSample.a;
    if (glitchIntensity > 0.1) {
        // Glitch shards have variable alpha
        let shardNoise = hash(cellID + vec2<f32>(time * 0.5));
        let alphaModulation = 1.0 - glitchIntensity * 0.3 * shardNoise;
        finalAlpha = mix(gSample.a, gSample.a * alphaModulation, glitchIntensity);
    }

    // Pixel sorting effect
    let sortStrength = u.zoom_params.z * glitchIntensity;
    let sortValue = dot(vec3<f32>(rSample.r, gSample.g, bSample.b), vec3<f32>(0.299, 0.587, 0.114));
    let sortedUV = clamp(uv + vec2<f32>(0.0, sortValue * sortStrength * u.zoom_config.w), vec2<f32>(0.0), vec2<f32>(1.0));
    let sortedSample = textureSampleLevel(readTexture, u_sampler, sortedUV, 0.0);
    let sortedColor = sortedSample.rgb;
    // Pixel sorting can also affect alpha
    let sortedAlpha = mix(finalAlpha, sortedSample.a, sortStrength * 0.3);

    // Combine effects
    var finalColor = vec3<f32>(rSample.r, gSample.g, bSample.b) * (1.0 + glassPattern * 2.0);
    finalColor = mix(finalColor, sortedColor, glitchIntensity * 0.5);

    // Add scanlines and digital noise
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.05 + 0.95;
    let digitalNoise = hash(uv + time) * glitchIntensity * 0.1;

    finalColor = finalColor * scanline + digitalNoise;
    // Scanlines affect alpha slightly
    finalAlpha = finalAlpha * scanline;

    // Vignette with alpha preservation
    let vignette = 1.0 - distance(uv, vec2<f32>(0.5)) * 0.5;
    finalColor = finalColor * vignette;
    // Vignette creates subtle edge transparency
    finalAlpha = finalAlpha * (0.9 + vignette * 0.1);

    // Clamp alpha
    finalAlpha = clamp(finalAlpha, 0.0, 1.0);

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Depth with alpha consideration
    let depth = 1.0 - clamp(distance(uv, vec2<f32>(0.5)) * 0.8, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
