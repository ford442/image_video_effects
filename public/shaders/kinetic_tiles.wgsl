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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
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

    // Parameters
    // x: Grid Density (10.0 to 100.0)
    // y: Influence Radius (0.1 to 1.0)
    // z: Rotation Amount (0.0 to PI)
    // w: Scale/Inset (0.5 to 1.0)

    let gridDensity = u.zoom_params.x * 90.0 + 10.0;
    let radius = u.zoom_params.y * 0.8 + 0.05;
    let maxRotation = u.zoom_params.z * 3.14159 * 2.0;
    let scale = u.zoom_params.w * 0.5 + 0.5;

    // Mouse
    let mouse = u.zoom_config.yz;

    // Grid calculations
    // Adjust UV for aspect ratio to make square cells
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let cellIndex = floor(uvAspect * gridDensity);
    let cellUV = fract(uvAspect * gridDensity); // 0.0 to 1.0 inside cell

    // Find cell center in global UV space
    // We need to map back from aspect corrected space
    let cellCenterAspect = (cellIndex + 0.5) / gridDensity;
    let cellCenter = vec2<f32>(cellCenterAspect.x / aspect, cellCenterAspect.y);

    // Distance from mouse to cell center
    let diff = cellCenter - mouse;
    // Correct diff for aspect for proper circular distance
    let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
    let dist = length(diffAspect);

    var angle: f32 = 0.0;
    var currentScale: f32 = 1.0;

    if (dist < radius) {
        let pct = 1.0 - smoothstep(0.0, radius, dist);
        angle = pct * maxRotation;
        currentScale = 1.0 - (pct * (1.0 - scale)); // Shrink near mouse if scale < 1.0
    }

    // Rotate cellUV around center (0.5, 0.5)
    let s = sin(angle);
    let c = cos(angle);
    let centered = cellUV - 0.5;
    let rotated = vec2<f32>(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    );

    // Apply scale (zoom in/out of cell)
    // If we want gaps, we clamp
    let scaled = rotated / currentScale; // divide by scale to zoom in (if scale < 1, we zoom in? No, we want to shrink content?
    // Actually, usually "scale" means size of content.
    // If currentScale is 0.8 (smaller), we want to see more? Or do we want gaps?
    // Let's treat 'scale' as the size of the valid image area.

    let finalCellUV = scaled + 0.5;

    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    // Check bounds of cell
    if (finalCellUV.x >= 0.0 && finalCellUV.x <= 1.0 && finalCellUV.y >= 0.0 && finalCellUV.y <= 1.0) {
        // Map back to global texture UV
        // We know the cell bounds in global UV.
        // But simpler:
        // We want to sample the texture at the location corresponding to this cell,
        // but offset by the rotation.

        // Strategy: We want the image to look "chopped up".
        // So we sample the texture at the "cell center" + "offset within cell".
        // But the "offset within cell" is rotated.

        // Convert finalCellUV back to global offset
        // The width of a cell in UV space:
        // X width = (1.0 / gridDensity) / aspect
        // Y height = (1.0 / gridDensity)

        let cellWidth = vec2<f32>(1.0 / (gridDensity * aspect), 1.0 / gridDensity);

        let offsetFromCenter = (finalCellUV - 0.5) * cellWidth;

        let sampleUV = cellCenter + offsetFromCenter;

        color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    } else {
        // Gap color (black or maybe dark grey)
        color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    textureStore(writeTexture, global_id.xy, color);

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
