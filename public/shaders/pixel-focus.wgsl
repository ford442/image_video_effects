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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let mosaicSize = u.zoom_params.x; // Block size (0-1)
    let focusRadius = u.zoom_params.y; // Clear area radius
    let hardness = u.zoom_params.z; // Edge hardness
    let chromatic = u.zoom_params.w; // Chromatic aberration in blur

    // Calculate distance to mouse
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Mixing factor: 0.0 = Pixelated, 1.0 = Clear
    let mixVal = smoothstep(focusRadius, focusRadius * (1.0 - hardness * 0.9), dist);
    // Wait, smoothstep(edge0, edge1, x).
    // If dist < focusRadius, we want Clear (1.0).
    // If dist > focusRadius, we want Pixelated (0.0).
    // So edge0 should be radius, edge1 should be smaller?
    // smoothstep(0.2, 0.1, 0.15) = 0.5.
    // Let's use 1.0 - smoothstep(radius, radius+softness, dist).
    let focus = 1.0 - smoothstep(focusRadius, focusRadius + (1.0 - hardness) * 0.2, dist);

    // Pixelation Logic
    // Grid density
    let density = 50.0 + (1.0 - mosaicSize) * 450.0; // Range 50 to 500
    let pixelUV = floor(uv * density) / density;

    // Sample Clear
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Sample Pixelated
    // Add optional chromatic aberration to the pixelated part
    var colPixel: vec3<f32>;
    if (chromatic > 0.05) {
        let offset = chromatic * 0.01;
        let r = textureSampleLevel(readTexture, u_sampler, pixelUV + vec2<f32>(offset, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, pixelUV - vec2<f32>(offset, 0.0), 0.0).b;
        colPixel = vec3<f32>(r, g, b);
    } else {
        colPixel = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0).rgb;
    }

    let finalColor = mix(colPixel, colClear, focus);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
