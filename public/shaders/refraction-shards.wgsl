// --- REFRACTION SHARDS ---
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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    let dotP3 = dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let scale = mix(5.0, 20.0, u.zoom_params.x); // Shard scale
    let refraction = u.zoom_params.y; // Refraction strength
    let roughness = u.zoom_params.z;  // Noise/Roughness
    let chromatic = u.zoom_params.w;  // Chromatic aberration

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(mouseVec);

    // Create Shards (Voronoi-ish)
    // We'll use a simple grid based voronoi for performance
    let uvScaled = uv * vec2<f32>(aspect, 1.0) * scale;
    let i_st = floor(uvScaled);
    let f_st = fract(uvScaled);

    var m_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            // Animate points?
            // point = 0.5 + 0.5 * sin(u.config.x + 6.2831 * point);

            let diff = neighbor + point - f_st;
            let d = length(diff);

            if (d < m_dist) {
                m_dist = d;
                m_point = point;
                cell_id = i_st + neighbor;
            }
        }
    }

    // Determine shard normal/tilt based on mouse position relative to cell center
    // Cell center in UV space
    let cellCenterUV = (cell_id + m_point) / scale / vec2<f32>(aspect, 1.0);

    // Vector from mouse to cell
    let dirToCell = normalize(cellCenterUV - mouse);
    // Mouse distance to cell center
    let distToCell = distance(cellCenterUV * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Tilt amount based on distance (closer = more tilt)
    let tilt = smoothstep(0.5, 0.0, distToCell) * refraction;

    // Calculate refraction offset
    // Shift UV based on tilt direction
    // Randomize slightly per shard using cell_id
    let rand = hash22(cell_id);
    let randomTilt = (rand - 0.5) * roughness * 0.1;

    let offset = (dirToCell * tilt) + randomTilt;

    // Chromatic Aberration
    let offsetR = offset * (1.0 + chromatic);
    let offsetG = offset;
    let offsetB = offset * (1.0 - chromatic);

    let colR = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    var color = vec4<f32>(colR, colG, colB, 1.0);

    // Add shard edges/specular highlight
    // Distance from center of Voronoi cell (m_dist)
    // Edges are where m_dist is high? Voronoi distance metric is distance to feature point.
    // Actually borders are where distances to two closest points are equal.
    // But we only found closest.
    // Let's use m_dist (center) to darken/lighten.
    // Center of shard (m_dist small) -> brighter/specular?

    // Specular glint if facing mouse
    let glint = smoothstep(0.1, 0.0, m_dist) * tilt * 5.0; // Only glint if highly tilted
    color += vec4<f32>(glint);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
