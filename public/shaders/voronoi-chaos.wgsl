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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Voronoi Chaos
// Generates a Voronoi grid where cell centers are agitated by mouse position and time.
//
// Param1: Cell Size (Default: 0.5)
// Param2: Chaos Amount (Default: 0.5)
// Param3: Color Mix (Default: 0.5) - Mixes between distorted sampling and cell ID color
// Param4: Center Dot Size (Default: 0.2)

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Params
    let cellsScale = u.zoom_params.x * 20.0 + 4.0;
    let chaos = u.zoom_params.y;
    let colorMix = u.zoom_params.z;
    let dotSize = u.zoom_params.w * 0.1;

    // Aspect corrected coordinates for voronoi calculation
    let aspect = resolution.x / resolution.y;
    let st = vec2<f32>(uv.x * aspect, uv.y) * cellsScale;

    let i_st = floor(st);
    let f_st = fract(st);

    var m_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var m_id = vec2<f32>(0.0);

    // Search neighbors
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let id = i_st + neighbor;

            // Random point in cell
            var point = hash2(id);

            // Animate point
            // Base movement
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);

            // Mouse interaction: push points away from mouse
            if (mousePos.x >= 0.0) {
                 // Convert grid ID to UV space
                 let cellCenterUV = (id + point) / cellsScale;
                 cellCenterUV.x /= aspect; // revert aspect

                 let dToMouse = distance(cellCenterUV, mousePos);
                 let repulsion = smoothstep(0.5, 0.0, dToMouse) * chaos;

                 // Shift point relative to cell center
                 point = point + vec2<f32>(sin(dToMouse * 20.0 - time * 5.0), cos(dToMouse * 20.0 - time * 5.0)) * repulsion;
            }

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = point;
                m_id = id;
            }
        }
    }

    // Now we have the closest point info (m_dist) and the cell ID (m_id)

    // Calculate color
    // 1. Distortion sampling
    // Re-calculate the random point for the closest cell ID to get consistent sampling
    var finalPoint = hash2(m_id);
    finalPoint = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * finalPoint);

    // Re-apply mouse chaos to find exact center UV
    let cellCenterGrid = m_id + finalPoint;

    // Sampling at cell center (creating mosaic effect)
    let sampleUV_Grid = cellCenterGrid / cellsScale;
    let sampleUV = vec2<f32>(sampleUV_Grid.x / aspect, sampleUV_Grid.y);

    let colDistorted = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // 2. Cell Color (random)
    let colCell = vec4<f32>(hash2(m_id), 0.5 + 0.5*sin(m_id.x), 1.0);

    // Mix
    var color = mix(colDistorted, colCell, colorMix * 0.2); // Keep mostly image by default

    // Add center dots
    if (m_dist < dotSize) {
        color = mix(color, vec4<f32>(0.0, 0.0, 0.0, 1.0), 0.5);
    }

    // Highlight cells near mouse
    if (mousePos.x >= 0.0) {
       let d = distance(sampleUV, mousePos);
       if (d < 0.1) {
           color = color + vec4<f32>(0.2, 0.2, 0.2, 0.0) * (1.0 - d * 10.0);
       }
    }

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
