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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Luminescent Glass Tiles
// Param1: Grid Density
// Param2: Refraction Strength
// Param3: Mouse Influence Radius
// Param4: Mouse Chaos/Turbulence

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let density = max(u.zoom_params.x * 50.0, 1.0);
    let refractStr = u.zoom_params.y * 0.5;
    let radius = max(u.zoom_params.z, 0.01);
    let turbulence = u.zoom_params.w;

    // Grid calculations
    let gridUV = uv * vec2<f32>(density * aspect, density);
    let cellID = floor(gridUV);
    let cellUV = fract(gridUV); // 0..1 within cell

    // Find center of cell in global UV space
    let cellCenterGrid = cellID + vec2<f32>(0.5);
    let cellCenterUV = cellCenterGrid / vec2<f32>(density * aspect, density);

    // Sample video luminance at cell center to drive distortion
    let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenterUV, 0.0);
    let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Mouse influence
    let diff = cellCenterUV - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist);

    // Distortion logic
    // 'Bulge' effect based on luma: brighter = more magnification (smaller field of view)
    // 0.5 is center of cell.
    var distUV = cellUV - 0.5;

    // Scale the cell content.
    // If scale < 1.0, we zoom in (bulge). If scale > 1.0, we zoom out (shrink).
    // Let's make bright cells zoom in.
    var scale = 1.0 - (luma * refractStr * 2.0);

    // Add mouse turbulence
    if (mouseFactor > 0.0) {
        scale = scale * (1.0 - mouseFactor * turbulence);
        // Maybe rotate too?
        let angle = mouseFactor * turbulence * 3.14;
        let s = sin(angle);
        let c = cos(angle);
        distUV = vec2<f32>(distUV.x * c - distUV.y * s, distUV.x * s + distUV.y * c);
    }

    distUV = distUV * scale;
    distUV = distUV + 0.5; // Back to 0..1

    // Clamp to keep inside cell? Or allow bleed?
    // Glass tiles usually clamp or repeat.
    // Let's clamp to create distinct tiles.
    // But we need to map back to global UV.

    // Reconstruct Global UV from distorted Cell UV
    // Global = (CellID + DistortedCellUV) / Density
    let finalUV = (cellID + distUV) / vec2<f32>(density * aspect, density);

    // Optional: Add a border
    let border = max(abs(distUV.x - 0.5), abs(distUV.y - 0.5));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Darken edges of tiles
    if (border > 0.45) {
        color = color * 0.5;
    }

    // Highlight based on luma (glass glow)
    color = color + vec4<f32>(luma * 0.2 * mouseFactor, luma * 0.2 * mouseFactor, luma * 0.2 * mouseFactor, 0.0);

    textureStore(writeTexture, global_id.xy, color);
}
