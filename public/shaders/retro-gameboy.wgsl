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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn get_palette(intensity: f32, shift: f32) -> vec3<f32> {
    let col0 = vec3<f32>(15.0, 56.0, 15.0) / 255.0;
    let col1 = vec3<f32>(48.0, 98.0, 48.0) / 255.0;
    let col2 = vec3<f32>(139.0, 172.0, 15.0) / 255.0;
    let col3 = vec3<f32>(155.0, 188.0, 15.0) / 255.0;

    let val = clamp(intensity + shift, 0.0, 1.0) * 3.0;
    let idx = floor(val);
    let frac = fract(val);

    if (idx < 0.5) { return col0; }
    if (idx < 1.5) { return col1; }
    if (idx < 2.5) { return col2; }
    return col3;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let pixel = vec2<i32>(global_id.xy);

    let pSizeParam = u.zoom_params.x;
    let contrast = u.zoom_params.y;
    let gridStrength = u.zoom_params.z;
    let shadowOffset = u.zoom_params.w;

    // Depth awareness: nearer objects get finer pixel blocks
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseBlock = max(1.0, floor(pSizeParam * 10.0 + 1.0));
    let blockSize = max(1.0, baseBlock * (1.0 - depth * 0.5));

    let quantizedPos = floor(vec2<f32>(global_id.xy) / blockSize) * blockSize;
    let quantizedUV = quantizedPos / resolution;

    // Audio reactivity: bass drives palette shift, mids add scanline pulse
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let paletteShift = bass * 0.15;
    let scanPulse = 1.0 + mids * 0.3;

    // Mouse interaction
    let mContrast = (mouse.x - 0.5) * 2.0;
    let mBright = (mouse.y - 0.5) * 1.0;
    let finalContrast = clamp(contrast + mContrast * 0.5, 0.0, 2.0);
    let finalBright = mBright;

    // Chromatic aberration on pixel edges
    let pixelPos = vec2<f32>(global_id.xy) % blockSize;
    let edgeDist = min(min(pixelPos.x, pixelPos.y), min(blockSize - pixelPos.x, blockSize - pixelPos.y));
    let edgeFactor = smoothstep(0.0, 1.5, edgeDist);
    let caOffset = (1.0 - edgeFactor) * 0.008 * (1.0 + depth);

    let rUV = clamp(quantizedUV + vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = quantizedUV;
    let bUV = clamp(quantizedUV - vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let rRaw = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let gRaw = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let bRaw = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var rawColor = vec3<f32>(rRaw, gRaw, bRaw);

    // Ghosting / Shadow
    let offsetUV = clamp(quantizedUV - vec2<f32>(shadowOffset * 0.01, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let shadowColor = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0).rgb;

    let lumRaw = dot(rawColor, vec3<f32>(0.299, 0.587, 0.114));
    let lumShadow = dot(shadowColor, vec3<f32>(0.299, 0.587, 0.114));

    let cLumRaw = (lumRaw - 0.5) * finalContrast + 0.5 + finalBright;
    let cLumShadow = (lumShadow - 0.5) * finalContrast + 0.5 + finalBright;
    let finalLum = mix(cLumRaw, cLumShadow, 0.3 * shadowOffset);

    // Map to palette
    let paletteColor = get_palette(finalLum, paletteShift);

    // Pixel grid
    var grid = 1.0;
    if (blockSize > 1.5 && gridStrength > 0.0) {
        let border = step(blockSize - 1.0, pixelPos.x) + step(blockSize - 1.0, pixelPos.y);
        grid = 1.0 - clamp(border, 0.0, 1.0) * gridStrength * 0.5;
    }

    // Scanline modulation from audio mids
    let scanLine = sin(f32(global_id.y) * 3.14159 / blockSize) * 0.5 + 0.5;
    var finalColor = paletteColor * grid * mix(1.0, scanLine, mids * 0.4) * scanPulse;

    // Temporal feedback: scanline persistence
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    let persistence = 0.75;
    finalColor = mix(finalColor, prev, persistence * (1.0 - grid * 0.3));

    // ACES tone mapping
    finalColor = acesToneMap(finalColor);

    // Semantic alpha: foreground pixels more opaque, grid lines slightly transparent
    let alpha = mix(0.55, 1.0, depth) * grid;

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
