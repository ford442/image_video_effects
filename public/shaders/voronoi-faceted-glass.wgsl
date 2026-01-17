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

// Random function
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let aspect = resolution.x / resolution.y;
    var uvCorrected = vec2<f32>(uv.x * aspect, uv.y);

    // Grid size
    let density = 10.0;
    let gridUV = uvCorrected * density;
    let gridIndex = floor(gridUV);
    let gridFract = fract(gridUV);

    var minDist = 1.0;
    var cellId = vec2<f32>(0.0);
    var cellCenter = vec2<f32>(0.0);

    // Check 3x3 neighbors
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let p = gridIndex + neighbor;

            // Random point in cell, animated
            var point = hash22(p);

            // Animate point
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);

            // Mouse interaction: push points away or pull them
            let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
            let worldPoint = (p + point) / density;
            let distToMouse = distance(worldPoint, mousePos);

            // Distortion based on mouse
            if (distToMouse < 0.5) {
                // Shift point slightly away from mouse
                let push = normalize(worldPoint - mousePos) * (0.5 - distToMouse) * 0.5;
                // point is local to cell (0-1), but we are effectively modifying its apparent position
                // It's easier to modify the distance calculation
                // Let's just animate the point normally for now to ensure stability
            }

            let diff = neighbor + point - gridFract;
            let dist = length(diff);

            if (dist < minDist) {
                minDist = dist;
                cellId = p;
                cellCenter = (p + point) / density;
            }
        }
    }

    // cellCenter is the UV coordinate of the Voronoi cell center (corrected for aspect)
    // Convert back to UV space
    var sampleUV = cellCenter;
    sampleUV.x = sampleUV.x / aspect;

    // Add some "glass" refraction based on distance to center of cell
    // Edges of cells distort more?
    // Let's just sample the image at the cell center (mosaic effect)
    // And mix it with a slightly distorted version based on local coordinates

    // "Glass" look: the UV used to sample the texture is the original UV,
    // but displaced by the vector to the cell center.
    // vec2 offset = (uv - sampleUV);
    // actually, let's just sample AT the cell center for a faceted look
    // Then add some shading at the edges (minDist is distance to center)

    // To make it look like glass, we might want to sample *around* the center based on normal
    // But simple mosaic is: sample at sampleUV.

    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add cell borders/highlights
    // minDist is distance to the seed point.
    // Border is where minDist of two cells are close? No, that's complex to find here without second pass.
    // But we can darken edges based on minDist (0 at center, 0.5+ at edges)
    // Actually minDist is distance to the *closest* point. It maxes out around 0.5-0.7.

    let shade = 1.0 - smoothstep(0.3, 0.6, minDist);
    color = color * (0.8 + 0.2 * shade); // Slight vignetting per cell

    // Highlight based on mouse
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    if (distance(uv, mousePos) < 0.1) {
        color = color + vec4<f32>(0.1, 0.1, 0.1, 0.0);
    }

    textureStore(writeTexture, global_id.xy, color);
}
