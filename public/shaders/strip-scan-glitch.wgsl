@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // x=time, y=unused, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=time, y=mouseX, z=mouseY, w=mouseDown/active
  zoom_params: vec4<f32>,         // Parameters 1-4
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    // x: Strip Count (10 - 200)
    // y: Speed (Vertical scroll speed)
    // z: Jitter (Horizontal glitchiness)
    // w: RGB Split (Chromatic aberration)

    let stripCountParam = u.zoom_params.x;
    let speedParam = u.zoom_params.y;
    let jitterParam = u.zoom_params.z;
    let rgbSplitParam = u.zoom_params.w;

    let mouseX = u.zoom_config.y;
    let mouseY = u.zoom_config.z;

    // Derived values
    // Mix mouseX into strip count for interactive density
    let stripCount = mix(10.0, 300.0, stripCountParam + (mouseX * 0.5));
    let speed = (speedParam - 0.5) * 4.0 + (mouseY - 0.5) * 4.0;
    let time = u.config.x;

    // Quantize X to create strips
    let stripIdx = floor(uv.x * stripCount);
    let stripCenterU = (stripIdx + 0.5) / stripCount;

    // Determine offset for this strip
    // We want the offset to vary by strip and time
    // Use a random-ish hash based on stripIdx

    let stripHash = fract(sin(stripIdx * 12.9898) * 43758.5453);

    // Vertical displacement
    // Use the brightness of the strip (sampled at top or center) to modulate speed?
    // Let's sample the center of the screen at this x for a "scan" value
    // Changed to use non_filtering_sampler to ensure compatibility with float32 textures
    let stripBrightness = textureSampleLevel(readTexture, non_filtering_sampler, vec2<f32>(stripCenterU, 0.5), 0.0).g;

    // Calculate Y offset
    // Sine wave pattern + constant flow
    let yOffset = speed * time * (0.5 + stripHash * 0.5) + sin(uv.y * 10.0 + time) * 0.05 * jitterParam;

    // Horizontal Jitter (Glitch)
    // Occurs randomly or periodically
    let jitter = (fract(sin(time * 10.0 + stripIdx) * 43758.5453) - 0.5) * 2.0;
    var xOffset = 0.0;

    // Apply jitter if threshold met
    if (abs(jitter) > (1.0 - jitterParam * 0.8)) {
        xOffset = jitter * 0.02 * jitterParam;
    }

    // Final UVs per channel for RGB split
    let split = rgbSplitParam * 0.02; // max 2% shift

    let uvR = vec2<f32>(uv.x + xOffset + split, uv.y + yOffset);
    let uvG = vec2<f32>(uv.x + xOffset,         uv.y + yOffset);
    let uvB = vec2<f32>(uv.x + xOffset - split, uv.y + yOffset);

    // Use non_filtering_sampler here as well
    let sampleR = textureSampleLevel(readTexture, non_filtering_sampler, fract(uvR), 0.0).r;
    let sampleG = textureSampleLevel(readTexture, non_filtering_sampler, fract(uvG), 0.0).g;
    let sampleB = textureSampleLevel(readTexture, non_filtering_sampler, fract(uvB), 0.0).b;

    let finalColor = vec4<f32>(sampleR, sampleG, sampleB, 1.0);

    textureStore(writeTexture, global_id.xy, finalColor);
}
