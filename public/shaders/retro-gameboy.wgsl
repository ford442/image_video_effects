// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=PixelSize, y=Contrast, z=GridStrength, w=ShadowOffset
  ripples: array<vec4<f32>, 50>,
};

// Retro GB Palette
// 0: Darkest (0x0F, 0x38, 0x0F) -> (15, 56, 15)
// 1: Dark    (0x30, 0x62, 0x30) -> (48, 98, 48)
// 2: Light   (0x8B, 0xAC, 0x0F) -> (139, 172, 15)
// 3: Lightest(0x9B, 0xBC, 0x0F) -> (155, 188, 15)
fn get_palette(intensity: f32) -> vec3<f32> {
    let col0 = vec3<f32>(15.0, 56.0, 15.0) / 255.0;
    let col1 = vec3<f32>(48.0, 98.0, 48.0) / 255.0;
    let col2 = vec3<f32>(139.0, 172.0, 15.0) / 255.0;
    let col3 = vec3<f32>(155.0, 188.0, 15.0) / 255.0;

    // Quantize intensity to 4 levels
    let val = clamp(intensity, 0.0, 1.0) * 3.0;
    let idx = floor(val);
    let frac = fract(val);

    // Hard steps usually look more "retro", but let's allow slight mix for smoothness if desired?
    // The prompt asks for "retro game boy", so hard quantization is better.
    if (idx < 0.5) { return col0; }
    if (idx < 1.5) { return col1; }
    if (idx < 2.5) { return col2; }
    return col3;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz; // 0..1

    // Parameters
    // Pixel Size: 1.0 (coarse) to 0.0 (native resolution)
    // We map 0..1 to a divider.
    let pSizeParam = u.zoom_params.x;
    let pixelDiv = mix(1.0, 16.0, pSizeParam); // 1.0 = native, 16.0 = very blocky
    // Actually, "Pixel Size" implies blockiness.
    // If pSizeParam is 0, we want high res (divider 1).
    // If pSizeParam is 1, we want low res (divider large).
    // BUT typically pixel shaders work better if we define "pixels per screen" or "size of pixel".
    // Let's use pixel block size in screen pixels.
    let blockSize = max(1.0, floor(pSizeParam * 10.0 + 1.0));

    // Quantize UVs
    let quantizedPos = floor(vec2<f32>(global_id.xy) / blockSize) * blockSize;
    let quantizedUV = quantizedPos / resolution;

    // Parameters continued
    let contrast = u.zoom_params.y; // Base contrast
    let gridStrength = u.zoom_params.z;
    let shadowOffset = u.zoom_params.w;

    // Mouse Interaction
    // Mouse X adds to Contrast (centered at 0.5)
    // Mouse Y adds to Brightness
    let mContrast = (mouse.x - 0.5) * 2.0; // -1 to 1
    let mBright = (mouse.y - 0.5) * 1.0;   // -0.5 to 0.5

    let finalContrast = clamp(contrast + mContrast * 0.5, 0.0, 2.0);
    let finalBright = mBright;

    // Sample Image
    let rawColor = textureSampleLevel(readTexture, u_sampler, quantizedUV, 0.0).rgb;

    // Ghosting / Shadow
    // We sample a second time with a slight offset to simulate LCD lag/ghosting
    let offsetUV = quantizedUV - vec2<f32>(shadowOffset * 0.01, 0.0);
    let shadowColor = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0).rgb;

    // Convert to Grayscale (Luminance)
    let lumRaw = dot(rawColor, vec3<f32>(0.299, 0.587, 0.114));
    let lumShadow = dot(shadowColor, vec3<f32>(0.299, 0.587, 0.114));

    // Apply Contrast & Brightness
    let cLumRaw = (lumRaw - 0.5) * finalContrast + 0.5 + finalBright;
    let cLumShadow = (lumShadow - 0.5) * finalContrast + 0.5 + finalBright;

    // Mix Shadow (LCD Response Time simulation)
    // Darker pixels linger. We use a simple mix.
    let finalLum = mix(cLumRaw, cLumShadow, 0.3 * shadowOffset);

    // Map to Palette
    let paletteColor = get_palette(finalLum);

    // Apply Pixel Grid
    // Darken the edges of the blocks
    var grid = 1.0;
    if (blockSize > 1.5 && gridStrength > 0.0) {
        let pixelPos = vec2<f32>(global_id.xy) % blockSize;
        // Simple 1px line at bottom and right
        let border = step(blockSize - 1.0, pixelPos.x) + step(blockSize - 1.0, pixelPos.y);
        grid = 1.0 - clamp(border, 0.0, 1.0) * gridStrength * 0.5;
    }

    var finalColor = paletteColor * grid;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, quantizedUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
