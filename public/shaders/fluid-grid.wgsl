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
    let uv = vec2<f32>(global_id.xy) / resolution;

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let gridSize = 10.0 + u.zoom_params.x * 90.0; // 10 to 100
    let viscosity = u.zoom_params.y; // Dampening of movement
    let repulsion = u.zoom_params.z; // Strength of push
    let restitution = u.zoom_params.w; // Spring back force (unused in stateless, but affects curve)

    // Grid Logic
    // We treat the image as a grid of tiles.
    // Determine which tile the current pixel belongs to.
    let tileUV = floor(uv * gridSize) / gridSize;
    let tileCenter = tileUV + vec2<f32>(0.5 / gridSize, 0.5 / gridSize);

    // Calculate distance from mouse to the center of this tile
    let distVec = tileCenter - mousePos;
    let distVecCorrected = vec2<f32>(distVec.x * aspect, distVec.y);
    let dist = length(distVecCorrected);

    // Calculate offset for the tile
    // Push away from mouse
    let push = smoothstep(0.4, 0.0, dist) * repulsion * 0.2;
    let offsetDir = normalize(distVecCorrected);

    // Convert direction back to UV space
    let uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push;

    // Sample UV
    // We sample relative to the pixel's position within the tile,
    // but the tile itself is moved.
    // Actually, we want to know: "What part of the image is at this pixel?"
    // If the grid is pushed AWAY from mouse, then at a specific screen coordinate (near mouse),
    // we should see content that was closer to the mouse (pulled)? No, that's pull.

    // PUSH: Screen pixel P is occupied by content from C.
    // If we push content away, then at P, we see content from "upstream" (closer to mouse).
    // So sample coordinate should be closer to mouse.
    // sampleUV = uv - uvOffset.

    let sampleUV = uv - uvOffset;

    // Optional: Pixelate logic (snap sampleUV to grid?)
    // If we want "Fluid Grid" where tiles move but content inside is static relative to tile:
    // This is complex.
    // Let's stick to "Warp the space", but quantized by grid.

    // To make it look like "Tiles" moving:
    // The offset should be constant for all pixels in the tile.
    // We calculated 'push' based on 'tileCenter'. So 'uvOffset' is constant for the tile.
    // So all pixels in the tile shift together.

    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Draw grid lines?
    let gridLine = fract(uv * gridSize);
    let lineWeight = 0.05 * (1.0 - viscosity); // Viscosity hides grid?
    if (gridLine.x < lineWeight || gridLine.y < lineWeight) {
        color = mix(color, vec4<f32>(0.0, 0.0, 0.0, 1.0), 0.5);
    }

    textureStore(writeTexture, global_id.xy, color);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
