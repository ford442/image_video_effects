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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
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

    // Params
    let minSize = mix(0.001, 0.05, u.zoom_params.x); // High Res (near mouse)
    let maxSize = mix(0.02, 0.2, u.zoom_params.y);   // Low Res (far)
    let focusRadius = u.zoom_params.z;
    let gridContrast = u.zoom_params.w;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate Grid Size based on distance
    // smoothstep creates a smooth transition zone
    let factor = smoothstep(0.0, focusRadius, dist);
    let currentGridSize = mix(minSize, maxSize, factor);

    // Ensure non-zero
    let safeGridSize = max(currentGridSize, 0.001);

    // Pixelate UV
    // We snap to the grid
    // For proper aspect ratio handling of square blocks, we should correct UVs
    let aspectVec = vec2<f32>(aspect, 1.0);
    let scaledUV = uv * aspectVec;
    let snappedScaledUV = floor(scaledUV / safeGridSize) * safeGridSize;
    let pixelatedUV = snappedScaledUV / aspectVec;

    // Add 0.5 * gridSize to sample center of pixel?
    let centerOffset = vec2<f32>(safeGridSize, safeGridSize) / aspectVec * 0.5;
    let sampleUV = pixelatedUV + centerOffset;

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Grid lines
    var finalColor = color;
    if (gridContrast > 0.0) {
        // Distance from current UV to grid edge
        // In Scaled Space
        let inCellUV = fract(scaledUV / safeGridSize);
        // Distance to edge (0 or 1)
        let dX = min(inCellUV.x, 1.0 - inCellUV.x);
        let dY = min(inCellUV.y, 1.0 - inCellUV.y);
        let edgeDist = min(dX, dY) * safeGridSize * resolution.y; // approximate pixels?

        // If near edge, darken
        let line = smoothstep(0.0, 1.0, edgeDist); // 1 pixel width approx?
        // Actually edgeDist is in UV space * resolution -> pixels
        // Let's just use simple threshold
        if (dX < 0.05 || dY < 0.05) {
             finalColor = mix(finalColor, vec3<f32>(0.0), gridContrast);
        }
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
