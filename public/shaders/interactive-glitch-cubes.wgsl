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

// Interactive Glitch Cubes
// Param1: Grid Size
// Param2: Extrusion Height (Mouse Sensitivity)
// Param3: Grid Gap
// Param4: Shadow Strength

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let ar = resolution.x / resolution.y;

    // Parameters
    let gridSize = 5.0 + u.zoom_params.x * 50.0;
    let extrusion = u.zoom_params.y;
    let gapBase = u.zoom_params.z * 0.5; // Max 0.5 gap
    let shadowStr = u.zoom_params.w;

    // Grid Setup
    let st = uv * vec2<f32>(ar, 1.0) * gridSize;
    let i_st = floor(st);
    let f_st = fract(st);

    // Calculate global center of this tile
    let tileCenterUV = (i_st + 0.5) / gridSize / vec2<f32>(ar, 1.0);

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let dist = distance(tileCenterUV, mouse);

    // Height Calculation (Closer to mouse = higher)
    // Use a smooth bell curve
    let influence = smoothstep(0.5, 0.0, dist);
    let height = influence * extrusion * 2.0; // 0.0 to 2.0

    // Visual Scale (Perspective: Higher = Bigger)
    let baseScale = 1.0 - gapBase;
    let scale = baseScale * (1.0 + height * 0.3);

    // Parallax Shift
    // Vector from screen center to tile center
    let viewVec = tileCenterUV - vec2<f32>(0.5, 0.5);
    // Shift the "face" outwards based on height
    let shift = viewVec * height * 0.1;

    // Convert shift to local coords
    let shiftLocal = shift * vec2<f32>(ar, 1.0) * gridSize;
    let faceCenter = vec2<f32>(0.5) + shiftLocal;

    // Distance from current pixel to the shifted face center
    let distFace = abs(f_st - faceCenter);
    let limit = scale * 0.5;

    var color = vec3<f32>(0.05); // Dark Background

    // Check if pixel is on the Face
    if (distFace.x < limit && distFace.y < limit) {
        // Map pixel back to texture space
        // Normalize pos on face (-0.5 to 0.5)
        let posOnFace = (f_st - faceCenter) / scale;

        // Sample UV
        let sampleUV = tileCenterUV + posOnFace / gridSize / vec2<f32>(ar, 1.0);

        // Sample Texture
        color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // Lighting: Top face is brighter based on height
        color += height * 0.1;

    } else {
        // Draw Shadow/Sides
        // Simple Drop Shadow logic
        // Let's assume light is top-left, so shadow is bottom-right relative to tile center?
        // Or Shadow is underneath the lifted block.
        // Let's use the 'base' floor position (0.5) for shadow.
        let shadowCenter = vec2<f32>(0.5) + viewVec * 0.05; // Shadow shift
        let distShadow = abs(f_st - shadowCenter);
        let shadowLimit = baseScale * 0.5;

        if (distShadow.x < shadowLimit && distShadow.y < shadowLimit) {
            color = vec3<f32>(0.0); // Deep Black Shadow
        }

        // Side Extrusion (Connecting Face to Base)
        // Only if we want to get fancy. For now, floating tiles is good.
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    // Depth pass
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
