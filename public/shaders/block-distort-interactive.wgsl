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
    let time = u.config.x;

    // Parameters
    let blockSize = mix(10.0, 100.0, u.zoom_params.x);
    let pushStrength = u.zoom_params.y * 2.0;
    let rgbSplit = u.zoom_params.z * 0.1;
    let radius = u.zoom_params.w * 0.5 + 0.1;

    let mouse = u.zoom_config.yz;

    // Grid Logic
    // Convert UV to Block Grid Coordinates
    let gridUV = uv * vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);
    let cellID = floor(gridUV);
    let cellCenterGrid = cellID + 0.5;
    let cellCenterUV = cellCenterGrid / vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);

    // Distance from Cell Center to Mouse
    let distVec = (cellCenterUV - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Push calculation
    // Cells near mouse get pushed away
    let pushMask = smoothstep(radius, 0.0, dist); // 1 at mouse, 0 at radius
    let pushDir = normalize(distVec);

    // Displacement
    // We want the UVs to look up pixels "behind" the push?
    // If the block is pushed AWAY from mouse, we need to sample CLOSER to mouse?
    // Visual logic: The "image" is pushed.
    // So we sample at (uv - displacement).

    let displacement = pushDir * pushMask * pushStrength * 0.1;

    // But we are in "block" mode. The entire block moves.
    // So we calculate the displacement for the CENTER of the block, and apply it to the whole block.

    // Apply displacement to UV
    // Simple RGB Split based on displacement amount
    let split = displacement * rgbSplit * 5.0;

    let r = textureSampleLevel(readTexture, u_sampler, uv - displacement + split, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv - displacement, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - displacement - split, 0.0).b;

    // Add block edges
    let cellUV = fract(gridUV); // 0-1 within block
    let edgeDist = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
    let edge = (1.0 - smoothstep(0.0, 0.05, edgeDist)) * pushMask; // Only show edges when pushed?

    var col = vec3<f32>(r, g, b);
    col = col + vec3<f32>(edge * 0.5);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
