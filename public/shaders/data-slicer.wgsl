// ═══════════════════════════════════════════════════════════════════════════════
//  DATA SLICER
//  Distortion effect that slices the image horizontally based on noise and mouse.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SlideSpeed, y=SliceHeight, z=Chaos, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

// --- Hash Functions ---
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;

    // Parameters
    let slideSpeed = u.zoom_params.x * 10.0;
    let sliceHeight = mix(5.0, 100.0, u.zoom_params.y); // Pixel height of slices
    let chaos = u.zoom_params.z;
    let aberration = u.zoom_params.w * 0.1;

    // Mouse Interaction
    let mouseX = u.zoom_config.y;
    let mouseY = u.zoom_config.z;
    let isMouseDown = u.zoom_config.w;

    let fragCoord = vec2<f32>(global_id.xy);
    var uv = fragCoord / resolution;

    // Calculate Slice ID
    let sliceId = floor(fragCoord.y / sliceHeight);

    // Random offset for each slice
    var noiseVal = hash21(vec2<f32>(sliceId, floor(time * 2.0))); // Step noise every 0.5s

    // Animate the noise
    let move = sin(time * slideSpeed + sliceId * 13.52) * chaos;

    // Mouse influence: Slices near mouse Y move more intensely
    let mouseDistY = abs(uv.y - mouseY);
    let influence = smoothstep(0.3, 0.0, mouseDistY);

    // Only apply if mouse is somewhat active (optional, but good for control)
    // Actually, let's make the mouse X control the OFFSET direction/magnitude too
    let mouseOffset = (mouseX - 0.5) * 2.0 * influence;

    var xOffset = move * 0.1;

    if (isMouseDown > 0.5) {
        xOffset = xOffset + mouseOffset + (hash21(vec2<f32>(sliceId, time)) - 0.5) * 0.5 * influence;
    } else {
        xOffset = xOffset + mouseOffset * 0.5;
    }

    // Apply offset
    var uvR = uv;
    var uvG = uv;
    var uvB = uv;

    uvR.x = uvR.x + xOffset + aberration;
    uvG.x = uvG.x + xOffset;
    uvB.x = uvB.x + xOffset - aberration;

    // Wrap UVs
    uvR = fract(uvR);
    uvG = fract(uvG);
    uvB = fract(uvB);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Scanline darkness between slices
    let pixelInSlice = fract(fragCoord.y / sliceHeight);
    var color = vec4<f32>(r, g, b, 1.0);

    if (pixelInSlice < 0.1 || pixelInSlice > 0.9) {
        color = color * 0.8;
    }

    textureStore(writeTexture, global_id.xy, color);

    // Depth Pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
