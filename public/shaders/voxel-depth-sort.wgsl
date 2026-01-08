// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let gridSize = max(2.0, u.zoom_params.x * 50.0 + 5.0); // 5 to 55 pixels
    let extrusion = u.zoom_params.y * 100.0; // max shift pixels
    let shadowStrength = u.zoom_params.z; // 0-1
    let gapSize = u.zoom_params.w; // 0-1 relative to grid

    // Mouse determines the "light" or "view" angle
    let mouse = u.zoom_config.yz;
    // Calculate shift vector: direction from center of screen (0.5, 0.5) to mouse?
    // Or just relative to the pixel?
    // Let's make it a global tilt: Mouse deviation from center determines tilt.
    let tilt = (mouse - vec2<f32>(0.5, 0.5)) * 2.0; // -1 to 1 range

    // Identify grid cell
    let cellCoord = floor(global_id.xy / gridSize);
    let cellCenter = (cellCoord * gridSize) + (gridSize * 0.5);
    let cellUV = cellCenter / resolution;

    // Sample luma of the cell (block height)
    let color = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate "top face" offset based on height and tilt
    let offset = tilt * luma * extrusion;

    // Determine if current pixel is part of the top face of this cell
    // The top face is a square of size (gridSize * (1.0 - gapSize)) centered at cellCenter + offset

    let localPos = vec2<f32>(global_id.xy);
    let topCenter = cellCenter + offset;
    let blockSize = gridSize * (1.0 - gapSize * 0.5); // gap

    let inTopX = abs(localPos.x - topCenter.x) < (blockSize * 0.5);
    let inTopY = abs(localPos.y - topCenter.y) < (blockSize * 0.5);

    var finalColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    if (inTopX && inTopY) {
        // Pixel is on the top face
        finalColor = color;
    } else {
        // Pixel is background or side
        // Check if it's in the "base" footprint?
        // Or create a "side" effect by checking if it's between base and top?
        // Simplified: Just draw a shadow/darker version if it's within the bounding box of the extrusion

        // Let's draw the "base" dimly if not top
        let inBaseX = abs(localPos.x - cellCenter.x) < (blockSize * 0.5);
        let inBaseY = abs(localPos.y - cellCenter.y) < (blockSize * 0.5);

        if (inBaseX && inBaseY) {
            // It's the "hole" where the block came from
            finalColor = vec4<f32>(0.0, 0.0, 0.0, 1.0); // hole
        } else {
            // Check if it is a side?
            // Simple projection: Iterate a few steps? Too expensive.

            // Just use the original pixel but darkened heavily, to serve as background
            let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
            finalColor = bg * (1.0 - shadowStrength);
        }

        // Try to draw sides?
        // If we are between cellCenter and topCenter...
        // This is complex for arbitrary directions.
        // Let's settle for top face + dark background for a "floating blocks" look.
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
