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
  zoom_params: vec4<f32>,  // x=PixelSize, y=Radius, z=Softness, w=Invert
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    let mousePos = u.zoom_config.yz;

    let pixelSizeParam = max(0.001, u.zoom_params.x * 0.1); // 0.001 to 0.1 (screen relative)
    let radius = u.zoom_params.y * 0.5; // 0.0 to 0.5
    let softness = u.zoom_params.z * 0.2; // 0.0 to 0.2
    let invert = u.zoom_params.w > 0.5;

    // Calculate Pixelated UV
    // Snap UV to grid
    let grid = vec2<f32>(pixelSizeParam, pixelSizeParam * (resolution.x / resolution.y));
    // Or just use square pixels
    // Let's use square pixels based on width
    let px = pixelSizeParam;
    let py = pixelSizeParam * (resolution.x / resolution.y);
    // Wait, if resolution.y < resolution.x, py should be larger to maintain squareness?
    // pixelSizeParam is fraction of width.
    // X steps: 1/px. Y steps: 1/py.
    // To make square: stepX_pixels = stepY_pixels.
    // stepX_uv * ResX = stepY_uv * ResY
    // stepY_uv = stepX_uv * (ResX / ResY)

    let stepX = pixelSizeParam;
    let stepY = pixelSizeParam * (resolution.x / resolution.y);

    let pixelatedUV = vec2<f32>(
        floor(uv.x / stepX) * stepX + stepX * 0.5,
        floor(uv.y / stepY) * stepY + stepY * 0.5
    );

    // Distance to mouse
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mask
    // smoothstep(edge0, edge1, x) returns 0 if x < edge0, 1 if x > edge1
    // We want mask=1 for "Pixelated", mask=0 for "Clear"
    // If Invert (Obscure mode): Pixelated near mouse.
    //    Dist < Radius -> Pixelated.
    //    mask = 1.0 - smoothstep(Radius, Radius + Softness, Dist)
    // If !Invert (Reveal mode): Clear near mouse.
    //    Dist < Radius -> Clear.
    //    mask = smoothstep(Radius, Radius + Softness, Dist)

    var mask = 0.0;
    if (invert) {
        mask = 1.0 - smoothstep(radius, radius + softness + 0.001, dist);
    } else {
        mask = smoothstep(radius, radius + softness + 0.001, dist);
    }

    // Mix UVs
    // Ideally we don't mix UVs because that interpolates between blocky and smooth, looking weird.
    // We should mix the COLORS.

    let colorClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let colorPixel = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV, 0.0); // Use non_filtering for crisp blocks

    let finalColor = mix(colorClear, colorPixel, mask);

    textureStore(writeTexture, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
