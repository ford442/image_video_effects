@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Write State
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Read State
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=IsMouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Sliding Tile Glitch
// Param1: Grid Density
// Param2: Slide Probability/Speed
// Param3: Chaos (Random direction vs aligned)
// Param4: Reset Speed

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;

    let gridDensity = u.zoom_params.x * 20.0 + 5.0; // 5 to 25
    let slideSpeed = u.zoom_params.y * 0.05;
    let chaos = u.zoom_params.z;
    let decay = u.zoom_params.w * 0.05;

    // 1. Determine Grid Cell
    let gridUV = uv * gridDensity;
    let cellID = floor(gridUV);

    // Sample previous offset from state (stored in dataTextureC)
    // We sample at the CENTER of the cell to ensure uniform value across the cell
    let cellCenterUV = (cellID + 0.5) / gridDensity;
    var state = textureSampleLevel(dataTextureC, u_sampler, cellCenterUV, 0.0).xy; // xy = offset

    // 2. Mouse Interaction
    var isHover = false;
    if (mousePos.x >= 0.0) {
        // Check if mouse is inside this cell (approximately)
        let mouseGridPos = floor(mousePos * gridDensity);
        if (mouseGridPos.x == cellID.x && mouseGridPos.y == cellID.y) {
            isHover = true;
        }
    }

    if (isHover) {
        // Apply force/offset
        // Random direction
        let r = rand(cellID + vec2<f32>(time, 0.0));
        var dir = vec2<f32>(0.0);

        if (chaos > 0.5) {
            // Random direction
            dir = vec2<f32>(cos(r * 6.28), sin(r * 6.28));
        } else {
            // Axis aligned slide (either X or Y)
            if (r > 0.5) { dir.x = (r - 0.75) * 4.0; } // +/- 1 approx
            else { dir.y = (r - 0.25) * 4.0; }
        }

        state += dir * slideSpeed;
    }

    // Decay (return to zero)
    if (decay > 0.0) {
        state = mix(state, vec2<f32>(0.0), decay);
    }

    // Store new state (redundantly for every pixel in cell, but easy)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(state, 0.0, 1.0));

    // 3. Render
    // Sample image at uv + state
    let readUV = uv + state;
    // Mirror repeat logic manually since sampler might be clamp or repeat
    // Let's rely on sampler's address mode (Repeat usually)

    let color = textureSampleLevel(readTexture, u_sampler, readUV, 0.0);

    // Add grid lines for visual style?
    var finalColor = color.rgb;

    // Optional: Highlight grid edges if chaos is high
    let gridLocal = fract(gridUV);
    let border = 0.05;
    if ((gridLocal.x < border || gridLocal.y < border) && chaos > 0.8) {
        finalColor *= 0.5;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Passthrough depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
